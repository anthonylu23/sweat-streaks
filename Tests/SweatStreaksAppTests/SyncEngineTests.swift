import Foundation
import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore
@testable import SweatStreaksPersistence

@MainActor
final class SyncEngineTests: XCTestCase {
    func testRetryStopsAfterSuccessfulAttempt() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 2, day: 18)
        let range = fetchedRange(for: day)

        let script = ProviderScript(
            events: [
                .failure(ProviderError.network),
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )

        let provider = ScriptedProvider(script: script)
        let sleepRecorder = SleepRecorder()

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: Date()),
            providerFactory: { provider },
            sleepFunction: { duration in
                sleepRecorder.durations.append(duration)
            },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let calls = await script.callCount
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(sleepRecorder.durations.count, 1)

        let stored = try repository.fetchActivityDayRecord(day: day, source: .github)
        XCTAssertEqual(stored?.status, .active)

        let syncRun = try repository.fetchLatestSyncRun(provider: "github")
        XCTAssertEqual(syncRun?.status, .success)
    }

    func testMaxAttemptsStopsAtThreeFailures() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let script = ProviderScript(
            events: [
                .failure(ProviderError.network),
                .failure(ProviderError.network),
                .failure(ProviderError.network)
            ]
        )

        let provider = ScriptedProvider(script: script)
        let sleepRecorder = SleepRecorder()

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: Date()),
            providerFactory: { provider },
            sleepFunction: { duration in
                sleepRecorder.durations.append(duration)
            },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let calls = await script.callCount
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(sleepRecorder.durations.count, 2)

        let syncRun = try repository.fetchLatestSyncRun(provider: "github")
        XCTAssertEqual(syncRun?.status, .failed)
    }

    func testRateLimitEnforcesCooldown() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let script = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [:],
                        fetchedRange: now...now,
                        rateLimitedUntil: now.addingTimeInterval(600),
                        authError: false,
                        warning: "Rate limit reached"
                    )
                )
            ]
        )

        let provider = ScriptedProvider(script: script)

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: now),
            providerFactory: { provider },
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)
        await service.refreshNow(trigger: .manual)

        let calls = await script.callCount
        XCTAssertEqual(calls, 1)

        let state = service.providerSyncState(for: .github)
        XCTAssertNotNil(state?.cooldownUntil)
    }

    func testStaleStateAfterOldSuccessfulSync() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldSuccess = now.addingTimeInterval(-TimeInterval((SyncDefaults.staleThresholdHours + 1) * 3600))

        try repository.logSyncRun(
            SyncRunRecord(provider: "github", startedAt: oldSuccess, finishedAt: oldSuccess, status: .success, errorSummary: nil)
        )

        let script = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [:],
                        fetchedRange: now...now,
                        rateLimitedUntil: nil,
                        authError: true,
                        warning: "Authentication failed"
                    )
                )
            ]
        )

        let provider = ScriptedProvider(script: script)

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: now),
            providerFactory: { provider },
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let state = service.providerSyncState(for: .github)

        XCTAssertEqual(state?.isStale, true)
    }

    func testMultiProviderSyncDerivesCombinedAfterAllRequiredProvidersRun() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 2, day: 18)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let range = fetchedRange(for: day)

        let githubScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let leetCodeScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .leetcode,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let codexScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .codex,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let claudeCodeScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .claudeCode,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let cursorScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .cursor,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: now),
            providerFactories: [
                .github: { ScriptedProvider(source: .github, script: githubScript) },
                .leetcode: { ScriptedProvider(source: .leetcode, script: leetCodeScript) },
                .codex: { ScriptedProvider(source: .codex, script: codexScript) },
                .claudeCode: { ScriptedProvider(source: .claudeCode, script: claudeCodeScript) },
                .cursor: { ScriptedProvider(source: .cursor, script: cursorScript) }
            ],
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let combined = try repository.fetchActivityDayRecord(day: day, source: .combined)
        let githubState = try repository.fetchProviderSyncState(source: .github)
        let leetCodeState = try repository.fetchProviderSyncState(source: .leetcode)
        let codexState = try repository.fetchProviderSyncState(source: .codex)
        let claudeCodeState = try repository.fetchProviderSyncState(source: .claudeCode)
        let cursorState = try repository.fetchProviderSyncState(source: .cursor)

        XCTAssertEqual(combined?.status, .active)
        XCTAssertNotNil(githubState?.lastSuccessAt)
        XCTAssertNotNil(leetCodeState?.lastSuccessAt)
        XCTAssertNotNil(codexState?.lastSuccessAt)
        XCTAssertNotNil(claudeCodeState?.lastSuccessAt)
        XCTAssertNotNil(cursorState?.lastSuccessAt)
    }

    func testCombinedUsesOnlyEnabledProviderTrackingSourcesDuringSync() async throws {
        let day = LocalDay(year: 2026, month: 2, day: 18)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let range = fetchedRange(for: day)

        let disabledManager = try DatabaseManager(inMemory: true)
        let disabledRepository = SweatRepository(dbQueue: disabledManager.dbQueue)
        let disabledGitHubScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let disabledLeetCodeScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .leetcode,
                        days: [day: .inactive],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let disabledService = DefaultSyncService(
            repository: disabledRepository,
            clock: FixedClock(now: now),
            providerFactories: [
                .github: { ScriptedProvider(source: .github, script: disabledGitHubScript) },
                .leetcode: { ScriptedProvider(source: .leetcode, script: disabledLeetCodeScript) }
            ],
            combinedRequiredSources: [.github],
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await disabledService.refreshNow(trigger: .manual)

        let disabledCombined = try disabledRepository.fetchActivityDayRecord(day: day, source: .combined)
        XCTAssertEqual(disabledCombined?.status, .active)

        let enabledManager = try DatabaseManager(inMemory: true)
        let enabledRepository = SweatRepository(dbQueue: enabledManager.dbQueue)
        let enabledGitHubScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let enabledLeetCodeScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .leetcode,
                        days: [day: .inactive],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )
        let enabledService = DefaultSyncService(
            repository: enabledRepository,
            clock: FixedClock(now: now),
            providerFactories: [
                .github: { ScriptedProvider(source: .github, script: enabledGitHubScript) },
                .leetcode: { ScriptedProvider(source: .leetcode, script: enabledLeetCodeScript) }
            ],
            combinedRequiredSources: [.github, .leetcode],
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await enabledService.refreshNow(trigger: .manual)

        let enabledCombined = try enabledRepository.fetchActivityDayRecord(day: day, source: .combined)
        XCTAssertEqual(enabledCombined?.status, .inactive)
    }

    func testManualOverrideAffectsCombinedDuringSync() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 2, day: 18)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let range = fetchedRange(for: day)

        try repository.upsertActivityDayRecord(
            ActivityDayRecord(day: day, source: .leetcode, status: .active, updatedAt: now, provenance: .api)
        )
        try repository.setManualStatus(day: day, source: .leetcode, status: .inactive, note: "Rest day")

        let githubScript = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: range,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: now),
            providerFactories: [.github: { ScriptedProvider(source: .github, script: githubScript) }],
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let combined = try repository.fetchActivityDayRecord(day: day, source: .combined)
        XCTAssertEqual(combined?.status, .inactive)
    }

    func testSyncIgnoresProviderDaysOutsideFetchedLocalRange() async throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let timeZone = TimeZone(secondsFromGMT: 0)!
        let today = LocalDay(year: 2026, month: 5, day: 12)
        let tomorrow = LocalDay(year: 2026, month: 5, day: 13)
        let lower = today.date(in: timeZone)!
        let upper = lower.addingTimeInterval(23 * 60 * 60)

        try repository.upsertActivityDays([
            ActivityDayRecord(day: tomorrow, source: .github, status: .active, updatedAt: lower, provenance: .api),
            ActivityDayRecord(day: tomorrow, source: .combined, status: .active, updatedAt: lower, provenance: .derived)
        ])

        let script = ProviderScript(
            events: [
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [
                            today: .inactive,
                            tomorrow: .active
                        ],
                        fetchedRange: lower...upper,
                        rateLimitedUntil: nil,
                        authError: false,
                        warning: nil
                    )
                )
            ]
        )

        let service = DefaultSyncService(
            repository: repository,
            clock: FixedClock(now: upper),
            providerFactories: [.github: { ScriptedProvider(source: .github, script: script) }],
            sleepFunction: { _ in },
            jitterFunction: { _ in 0 }
        )

        await service.refreshNow(trigger: .manual)

        let todayRecord = try repository.fetchActivityDayRecord(day: today, source: .github)
        let tomorrowRecord = try repository.fetchActivityDayRecord(day: tomorrow, source: .github)
        let tomorrowCombined = try repository.fetchActivityDayRecord(day: tomorrow, source: .combined)

        XCTAssertEqual(todayRecord?.status, .inactive)
        XCTAssertNil(tomorrowRecord)
        XCTAssertNil(tomorrowCombined)
    }

    private func fetchedRange(for day: LocalDay) -> ClosedRange<Date> {
        let start = day.date(in: .current)!
        return start...start.addingTimeInterval(23 * 60 * 60)
    }
}

private struct FixedClock: SyncClock {
    let now: Date
}

private final class SleepRecorder {
    var durations: [UInt64] = []
}

private enum ProviderScriptEvent {
    case success(ProviderFetchResult)
    case failure(Error)
}

private actor ProviderScript {
    private var events: [ProviderScriptEvent]
    private(set) var callCount: Int = 0

    init(events: [ProviderScriptEvent]) {
        self.events = events
    }

    func next() throws -> ProviderFetchResult {
        callCount += 1
        guard !events.isEmpty else {
            throw ProviderError.unknown(message: "No scripted response")
        }

        let event = events.removeFirst()
        switch event {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

private struct ScriptedProvider: ActivityProvider {
    let source: ActivitySource
    let script: ProviderScript

    init(source: ActivitySource = .github, script: ProviderScript) {
        self.source = source
        self.script = script
    }

    func fetchActivityDays(range _: ClosedRange<Date>) async throws -> ProviderFetchResult {
        try await script.next()
    }
}
