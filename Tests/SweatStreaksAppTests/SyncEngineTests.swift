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

        let script = ProviderScript(
            events: [
                .failure(ProviderError.network),
                .success(
                    ProviderFetchResult(
                        source: .github,
                        days: [day: .active],
                        fetchedRange: Date()...Date(),
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
    let source: ActivitySource = .github
    let script: ProviderScript

    func fetchActivityDays(range _: ClosedRange<Date>) async throws -> ProviderFetchResult {
        try await script.next()
    }
}
