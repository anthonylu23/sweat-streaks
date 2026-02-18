import Foundation
import SweatStreaksCore
import SweatStreaksPersistence

@MainActor
final class DefaultSyncService: SyncService {
    private let repository: SweatRepository
    private let providerFactory: () throws -> ActivityProvider
    private let clock: SyncClock
    private let sleepFunction: (UInt64) async -> Void
    private let jitterFunction: (Int) -> Int

    private var syncStates: [ActivitySource: ProviderSyncState] = [:]

    init(
        repository: SweatRepository,
        clock: SyncClock = SystemClock(),
        providerFactory: @escaping () throws -> ActivityProvider,
        sleepFunction: @escaping (UInt64) async -> Void = { nanoseconds in try? await Task.sleep(nanoseconds: nanoseconds) },
        jitterFunction: @escaping (Int) -> Int = { _ in Int.random(in: 0...1) }
    ) {
        self.repository = repository
        self.clock = clock
        self.providerFactory = providerFactory
        self.sleepFunction = sleepFunction
        self.jitterFunction = jitterFunction
    }

    func providerSyncState(for source: ActivitySource) -> ProviderSyncState? {
        syncStates[source]
    }

    func refreshNow(trigger: SyncTrigger) async {
        do {
            let provider = try providerFactory()
            let source = provider.source
            let providerName = source.rawValue
            let startTime = clock.now

            if let currentState = syncStates[source],
               let cooldownUntil = currentState.cooldownUntil,
               cooldownUntil > clock.now {
                let summary = "Cooldown active until \(cooldownUntil.formatted(date: .abbreviated, time: .shortened))."
                try repository.logSyncRun(
                    SyncRunRecord(
                        provider: providerName,
                        startedAt: startTime,
                        finishedAt: clock.now,
                        status: .rateLimited,
                        errorSummary: summary
                    )
                )

                syncStates[source] = ProviderSyncState(
                    source: source,
                    lastSuccessAt: currentState.lastSuccessAt,
                    cooldownUntil: cooldownUntil,
                    lastError: summary,
                    isStale: computeIsStale(provider: providerName)
                )
                return
            }

            let range = try makeFetchRange(for: source)

            var lastErrorMessage: String?
            var authError = false
            var cooldownUntil: Date?
            var didSucceed = false

            for attempt in 1...SyncDefaults.maxAttempts {
                let runResult = await performProviderRun(provider: provider, range: range)

                switch runResult {
                case .success(let response):
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
                    syncStates[source] = ProviderSyncState(
                        source: source,
                        lastSuccessAt: latestSuccess,
                        cooldownUntil: nil,
                        lastError: response.warning,
                        isStale: computeIsStale(lastSuccessAt: latestSuccess)
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
                let stale = computeIsStale(lastSuccessAt: latestSuccess?.startedAt)

                syncStates[source] = ProviderSyncState(
                    source: source,
                    lastSuccessAt: latestSuccess?.startedAt,
                    cooldownUntil: cooldownUntil,
                    lastError: lastErrorMessage,
                    isStale: stale
                )
            }
        } catch {
            // The service is best-effort for now; caller reads latest state.
        }
    }

    private func performProviderRun(provider: ActivityProvider, range: ClosedRange<Date>) async -> ProviderRunResult {
        do {
            let response = try await provider.fetchActivityDays(range: range)

            if response.authError {
                return .authFailure(response.warning ?? "Authentication failed.")
            }

            if response.rateLimitedUntil != nil {
                return .rateLimited(response.rateLimitedUntil, response.warning ?? "Rate limited.")
            }

            return .success(response)
        } catch ProviderError.network {
            return .retryableFailure("Network error while syncing provider.")
        } catch ProviderError.decoding {
            return .retryableFailure("Could not decode provider response.")
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

        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDate) ?? endDate

        let startDay = LocalDay.from(date: startDate, in: .current)
        let lower = startDay.date(in: .current) ?? startDate
        let upper = endDay.date(in: .current) ?? endDate

        return lower...upper.addingTimeInterval(60 * 60 * 23)
    }

    private func buildRecords(from response: ProviderFetchResult) -> [ActivityDayRecord] {
        let now = clock.now
        var records: [ActivityDayRecord] = []

        for (day, status) in response.days {
            records.append(
                ActivityDayRecord(
                    day: day,
                    source: .github,
                    status: status,
                    updatedAt: now,
                    provenance: .api
                )
            )

            let leetCodeStatus: DayStatus = (try? repository.fetchActivityDayRecord(day: day, source: .leetcode)?.status) ?? .unknown
            let combinedStatus = CombinedStatusResolver.derive(github: status, leetcode: leetCodeStatus)

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

    private func computeIsStale(provider: String) -> Bool {
        let latestSuccess = try? repository.fetchLatestSuccessfulSyncRun(provider: provider)
        return computeIsStale(lastSuccessAt: latestSuccess?.startedAt)
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
