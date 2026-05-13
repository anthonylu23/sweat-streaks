import Foundation
import SweatStreaksCore
import SweatStreaksPersistence

@MainActor
final class DefaultSyncService: SyncService {
    typealias ProviderFactory = () throws -> ActivityProvider

    private let repository: SweatRepository
    private let providerFactories: [ActivitySource: ProviderFactory]
    private let combinedRequiredSources: [ActivitySource]
    private let clock: SyncClock
    private let sleepFunction: (UInt64) async -> Void
    private let jitterFunction: (Int) -> Int

    private var syncStates: [ActivitySource: ProviderSyncState]

    init(
        repository: SweatRepository,
        clock: SyncClock = SystemClock(),
        providerFactories: [ActivitySource: ProviderFactory],
        combinedRequiredSources: [ActivitySource] = ActivitySource.combinedRequiredSources,
        sleepFunction: @escaping (UInt64) async -> Void = { nanoseconds in try? await Task.sleep(nanoseconds: nanoseconds) },
        jitterFunction: @escaping (Int) -> Int = { _ in Int.random(in: 0...1) }
    ) {
        self.repository = repository
        self.clock = clock
        self.providerFactories = providerFactories
        self.combinedRequiredSources = combinedRequiredSources
        self.sleepFunction = sleepFunction
        self.jitterFunction = jitterFunction
        self.syncStates = (try? repository.fetchProviderSyncStates()) ?? [:]
    }

    convenience init(
        repository: SweatRepository,
        clock: SyncClock = SystemClock(),
        providerFactory: @escaping ProviderFactory,
        sleepFunction: @escaping (UInt64) async -> Void = { nanoseconds in try? await Task.sleep(nanoseconds: nanoseconds) },
        jitterFunction: @escaping (Int) -> Int = { _ in Int.random(in: 0...1) }
    ) {
        self.init(
            repository: repository,
            clock: clock,
            providerFactories: [.github: providerFactory],
            combinedRequiredSources: [.github],
            sleepFunction: sleepFunction,
            jitterFunction: jitterFunction
        )
    }

    func providerSyncState(for source: ActivitySource) -> ProviderSyncState? {
        syncStates[source]
    }

    func refreshNow(trigger _: SyncTrigger) async {
        for source in orderedSources {
            await refresh(source: source)
        }
    }

    private var orderedSources: [ActivitySource] {
        ActivitySource.currentProviderSources.filter { providerFactories[$0] != nil }
    }

    private func refresh(source: ActivitySource) async {
        let providerName = source.rawValue
        let startTime = clock.now

        do {
            if let currentState = syncStates[source],
               let cooldownUntil = currentState.cooldownUntil,
               cooldownUntil > clock.now {
                let summary = "Cooldown active until \(cooldownUntil.formatted(date: .abbreviated, time: .shortened))."
                try recordState(
                    ProviderSyncState(
                        source: source,
                        lastSuccessAt: currentState.lastSuccessAt,
                        cooldownUntil: cooldownUntil,
                        lastError: summary,
                        isStale: computeIsStale(lastSuccessAt: currentState.lastSuccessAt)
                    )
                )
                try repository.logSyncRun(
                    SyncRunRecord(
                        provider: providerName,
                        startedAt: startTime,
                        finishedAt: clock.now,
                        status: .rateLimited,
                        errorSummary: summary
                    )
                )
                return
            }

            guard let factory = providerFactories[source] else { return }
            let provider = try factory()
            let range = try makeFetchRange(for: source)

            var lastErrorMessage: String?
            var authError = false
            var cooldownUntil: Date?
            var didSucceed = false

            for attempt in 1...SyncDefaults.maxAttempts {
                let runResult = await performProviderRun(provider: provider, range: range)

                switch runResult {
                case .success(let response):
                    try deleteClampedProviderDays(from: response)
                    let records = buildRecords(from: response)
                    try repository.upsertActivityDays(records)

                    let status: SyncRunStatus = response.warning == nil ? .success : .partial
                    try repository.logSyncRun(
                        SyncRunRecord(
                            provider: providerName,
                            startedAt: startTime,
                            finishedAt: clock.now,
                            status: status,
                            errorSummary: response.warning
                        )
                    )

                    let latestSuccess = clock.now
                    try recordState(
                        ProviderSyncState(
                            source: source,
                            lastSuccessAt: latestSuccess,
                            cooldownUntil: nil,
                            lastError: response.warning,
                            isStale: computeIsStale(lastSuccessAt: latestSuccess)
                        )
                    )

                    didSucceed = true

                case .authFailure(let message):
                    authError = true
                    lastErrorMessage = message
                    try repository.logSyncRun(
                        SyncRunRecord(
                            provider: providerName,
                            startedAt: startTime,
                            finishedAt: clock.now,
                            status: .authError,
                            errorSummary: message
                        )
                    )

                case .rateLimited(let retryAfter, let message):
                    let fallback = clock.now.addingTimeInterval(TimeInterval(SyncDefaults.rateLimitCooldownMinutes * 60))
                    cooldownUntil = retryAfter ?? fallback
                    lastErrorMessage = message

                    try repository.logSyncRun(
                        SyncRunRecord(
                            provider: providerName,
                            startedAt: startTime,
                            finishedAt: clock.now,
                            status: .rateLimited,
                            errorSummary: message
                        )
                    )

                case .retryableFailure(let message):
                    lastErrorMessage = message
                    if attempt < SyncDefaults.maxAttempts {
                        let delaySeconds = backoffSeconds(attempt: attempt) + jitterFunction(attempt)
                        let nanoseconds = UInt64(max(delaySeconds, 0)) * 1_000_000_000
                        await sleepFunction(nanoseconds)
                        continue
                    }

                    try repository.logSyncRun(
                        SyncRunRecord(
                            provider: providerName,
                            startedAt: startTime,
                            finishedAt: clock.now,
                            status: .failed,
                            errorSummary: message
                        )
                    )
                }

                if didSucceed || authError || cooldownUntil != nil {
                    break
                }
            }

            if !didSucceed {
                let latestSuccess = try repository.fetchLatestSuccessfulSyncRun(provider: providerName)
                let state = ProviderSyncState(
                    source: source,
                    lastSuccessAt: latestSuccess?.startedAt,
                    cooldownUntil: cooldownUntil,
                    lastError: lastErrorMessage,
                    isStale: computeIsStale(lastSuccessAt: latestSuccess?.startedAt)
                )
                try recordState(state)
            }
        } catch ProviderError.auth {
            try? recordAuthFailure(source: source, startedAt: startTime, message: "\(providerName.capitalized) authentication failed.")
        } catch {
            try? recordState(
                ProviderSyncState(
                    source: source,
                    lastSuccessAt: syncStates[source]?.lastSuccessAt,
                    cooldownUntil: syncStates[source]?.cooldownUntil,
                    lastError: "Sync failed: \(error.localizedDescription)",
                    isStale: computeIsStale(lastSuccessAt: syncStates[source]?.lastSuccessAt)
                )
            )
        }
    }

    private func recordAuthFailure(source: ActivitySource, startedAt: Date, message: String) throws {
        let latestSuccess = try repository.fetchLatestSuccessfulSyncRun(provider: source.rawValue)
        try repository.logSyncRun(
            SyncRunRecord(
                provider: source.rawValue,
                startedAt: startedAt,
                finishedAt: clock.now,
                status: .authError,
                errorSummary: message
            )
        )
        try recordState(
            ProviderSyncState(
                source: source,
                lastSuccessAt: latestSuccess?.startedAt,
                cooldownUntil: nil,
                lastError: message,
                isStale: computeIsStale(lastSuccessAt: latestSuccess?.startedAt)
            )
        )
    }

    private func performProviderRun(provider: ActivityProvider, range: ClosedRange<Date>) async -> ProviderRunResult {
        do {
            let response = try await provider.fetchActivityDays(range: range)

            if response.authError {
                return .authFailure(response.warning ?? "\(provider.source.rawValue.capitalized) authentication failed.")
            }

            if response.rateLimitedUntil != nil {
                return .rateLimited(response.rateLimitedUntil, response.warning ?? "\(provider.source.rawValue.capitalized) rate limited.")
            }

            return .success(response)
        } catch ProviderError.network {
            return .retryableFailure("Network error while syncing \(provider.source.rawValue).")
        } catch ProviderError.decoding {
            return .retryableFailure("Could not decode \(provider.source.rawValue) response.")
        } catch ProviderError.rateLimited(let retryAfter) {
            return .rateLimited(retryAfter, "\(provider.source.rawValue.capitalized) rate limit reached.")
        } catch ProviderError.auth {
            return .authFailure("\(provider.source.rawValue.capitalized) authentication failed.")
        } catch ProviderError.unknown(let message) {
            return .retryableFailure(message)
        } catch {
            return .retryableFailure("Unknown sync error: \(error.localizedDescription)")
        }
    }

    private func makeFetchRange(for source: ActivitySource) throws -> ClosedRange<Date> {
        let endDate = clock.now
        let endDay = LocalDay.from(date: endDate, in: .current)

        let hasPriorData = try repository.fetchMostRecentActivityDay(source: source) != nil
        let dayCount = hasPriorData ? SyncDefaults.incrementalBackfillDays : SyncDefaults.initialBackfillDays

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDate) ?? endDate

        let startDay = LocalDay.from(date: startDate, in: .current)
        let lower = startDay.date(in: .current) ?? startDate
        let upperDayStart = endDay.date(in: .current) ?? endDate
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: upperDayStart)
            ?? upperDayStart.addingTimeInterval(24 * 60 * 60)

        return lower...nextDayStart.addingTimeInterval(-0.001)
    }

    private func buildRecords(from response: ProviderFetchResult) -> [ActivityDayRecord] {
        let now = clock.now
        var records: [ActivityDayRecord] = []
        let localRange = localDayRange(for: response.fetchedRange)

        for (day, status) in response.days {
            guard day >= localRange.lowerBound && day <= localRange.upperBound else {
                continue
            }

            records.append(
                ActivityDayRecord(
                    day: day,
                    source: response.source,
                    status: status,
                    updatedAt: now,
                    provenance: .api
                )
            )

            let combinedStatus = deriveCombinedStatus(day: day, freshSource: response.source, freshStatus: status)
            records.append(
                ActivityDayRecord(
                    day: day,
                    source: .combined,
                    status: combinedStatus,
                    updatedAt: now,
                    provenance: .derived
                )
            )
        }

        return records
    }

    private func localDayRange(for range: ClosedRange<Date>) -> ClosedRange<LocalDay> {
        LocalDay.from(date: range.lowerBound, in: .current)...LocalDay.from(date: range.upperBound, in: .current)
    }

    private func deleteClampedProviderDays(from response: ProviderFetchResult) throws {
        let localRange = localDayRange(for: response.fetchedRange)

        for day in response.days.keys where day < localRange.lowerBound || day > localRange.upperBound {
            try repository.deleteActivityDayRecord(day: day, source: response.source)
            try repository.deleteActivityDayRecord(day: day, source: .combined)
        }
    }

    private func deriveCombinedStatus(day: LocalDay, freshSource: ActivitySource, freshStatus: DayStatus) -> DayStatus {
        var sourceStatuses: [ActivitySource: DayStatus] = [:]

        for source in ActivitySource.currentProviderSources {
            if source == freshSource {
                sourceStatuses[source] = freshStatus
            } else {
                sourceStatuses[source] = (try? repository.fetchActivityDayRecord(day: day, source: source)?.status) ?? .unknown
            }
        }

        var overrides: [ActivitySource: OverrideStatus] = [:]
        for source in ActivitySource.currentProviderSources {
            if let manualOverride = try? repository.fetchManualOverride(day: day, source: source) {
                overrides[source] = manualOverride.status
            }
        }

        let effective = StreakEngine.applyOverrides(sourceStatuses: sourceStatuses, overrides: overrides)
        return CombinedStatusResolver.derive(
            effectiveStatuses: effective,
            requiredSources: combinedRequiredSources
        )
    }

    private func recordState(_ state: ProviderSyncState) throws {
        syncStates[state.source] = state
        try repository.upsertProviderSyncState(state, updatedAt: clock.now)
    }

    private func computeIsStale(lastSuccessAt: Date?) -> Bool {
        guard let lastSuccessAt else { return false }
        let threshold = TimeInterval(SyncDefaults.staleThresholdHours * 60 * 60)
        return clock.now.timeIntervalSince(lastSuccessAt) > threshold
    }

    private func backoffSeconds(attempt: Int) -> Int {
        switch attempt {
        case 1: return 2
        case 2: return 8
        default: return 20
        }
    }
}

private enum ProviderRunResult {
    case success(ProviderFetchResult)
    case authFailure(String)
    case rateLimited(Date?, String)
    case retryableFailure(String)
}
