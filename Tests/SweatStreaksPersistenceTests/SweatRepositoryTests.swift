import XCTest
@testable import SweatStreaksCore
@testable import SweatStreaksPersistence

final class SweatRepositoryTests: XCTestCase {
    func testSettingsRoundTrip() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        try repository.setSetting(key: "refreshIntervalMinutes", value: "60")
        let value = try repository.getSetting(key: "refreshIntervalMinutes")

        XCTAssertEqual(value, "60")
    }

    func testDatabaseFileUsesOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SweatStreaksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("test.sqlite").path
        _ = try DatabaseManager(path: path)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testActivityUpsertAndFetch() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let day = LocalDay(year: 2026, month: 2, day: 18)
        let record = ActivityDayRecord(
            day: day,
            source: .github,
            status: .active,
            updatedAt: Date(),
            provenance: .api
        )

        try repository.upsertActivityDayRecord(record)
        let fetched = try repository.fetchActivityDayRecord(day: day, source: .github)

        XCTAssertEqual(fetched?.day, day)
        XCTAssertEqual(fetched?.source, .github)
        XCTAssertEqual(fetched?.status, .active)
    }

    func testAgenticToolSourcesPersistAcrossProviderTables() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 5, day: 12)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try repository.upsertActivityDayRecord(
            ActivityDayRecord(day: day, source: .codex, status: .active, updatedAt: now, provenance: .api)
        )
        try repository.setManualStatus(day: day, source: .claudeCode, status: .inactive, note: "No Claude work")
        try repository.upsertProviderSyncState(
            ProviderSyncState(source: .codex, lastSuccessAt: now, cooldownUntil: nil, lastError: nil, isStale: false),
            updatedAt: now
        )

        XCTAssertEqual(try repository.fetchActivityDayRecord(day: day, source: .codex)?.status, .active)
        XCTAssertEqual(try repository.fetchManualOverride(day: day, source: .claudeCode)?.status, .inactive)
        XCTAssertEqual(try repository.fetchProviderSyncState(source: .codex)?.lastSuccessAt, now)
    }

    func testActivityDelete() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let day = LocalDay(year: 2026, month: 2, day: 18)
        try repository.upsertActivityDayRecord(
            ActivityDayRecord(
                day: day,
                source: .github,
                status: .active,
                updatedAt: Date(),
                provenance: .api
            )
        )

        try repository.deleteActivityDayRecord(day: day, source: .github)

        XCTAssertNil(try repository.fetchActivityDayRecord(day: day, source: .github))
    }

    func testDeleteFutureActivityDays() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let today = LocalDay(year: 2026, month: 5, day: 12)
        let tomorrow = LocalDay(year: 2026, month: 5, day: 13)
        try repository.upsertActivityDays([
            ActivityDayRecord(day: today, source: .github, status: .inactive, updatedAt: Date(), provenance: .api),
            ActivityDayRecord(day: tomorrow, source: .github, status: .active, updatedAt: Date(), provenance: .api),
            ActivityDayRecord(day: tomorrow, source: .combined, status: .active, updatedAt: Date(), provenance: .derived)
        ])

        try repository.deleteActivityDays(after: today)

        XCTAssertNotNil(try repository.fetchActivityDayRecord(day: today, source: .github))
        XCTAssertNil(try repository.fetchActivityDayRecord(day: tomorrow, source: .github))
        XCTAssertNil(try repository.fetchActivityDayRecord(day: tomorrow, source: .combined))
    }

    func testManualOverrideRoundTrip() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let day = LocalDay(year: 2026, month: 2, day: 18)
        try repository.setManualStatus(day: day, source: .github, status: .inactive, note: "Vacation day")

        let fetched = try repository.fetchManualOverride(day: day, source: .github)
        XCTAssertEqual(fetched?.status, .inactive)
        XCTAssertEqual(fetched?.note, "Vacation day")

        try repository.clearManualStatus(day: day, source: .github)
        let cleared = try repository.fetchManualOverride(day: day, source: .github)
        XCTAssertNil(cleared)
    }

    func testManualOverrideRejectsCombinedSource() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 2, day: 18)

        XCTAssertThrowsError(
            try repository.setManualStatus(day: day, source: .combined, status: .active, note: nil)
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidOverrideSource)
        }
    }

    func testFetchManualOverridesByRange() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let day = LocalDay(year: 2026, month: 2, day: 18)

        try repository.setManualStatus(day: day, source: .github, status: .active, note: "Travel")
        try repository.setManualStatus(day: day, source: .leetcode, status: .inactive, note: "Rest")

        let overrides = try repository.fetchManualOverrides(from: day, to: day)

        XCTAssertEqual(overrides[day]?[.github]?.status, .active)
        XCTAssertEqual(overrides[day]?[.leetcode]?.status, .inactive)
    }

    func testProviderSyncStateRoundTrip() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cooldown = now.addingTimeInterval(600)

        try repository.upsertProviderSyncState(
            ProviderSyncState(
                source: .leetcode,
                lastSuccessAt: now,
                cooldownUntil: cooldown,
                lastError: "Rate limited",
                isStale: true
            ),
            updatedAt: now
        )

        let fetched = try repository.fetchProviderSyncState(source: .leetcode)
        let allStates = try repository.fetchProviderSyncStates()

        XCTAssertEqual(fetched?.lastSuccessAt, now)
        XCTAssertEqual(fetched?.cooldownUntil, cooldown)
        XCTAssertEqual(fetched?.lastError, "Rate limited")
        XCTAssertEqual(fetched?.isStale, true)
        XCTAssertEqual(allStates[.leetcode]?.lastSuccessAt, now)
    }

    func testLatestSyncRunAndMostRecentDay() throws {
        let manager = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: manager.dbQueue)

        let firstDay = LocalDay(year: 2026, month: 2, day: 17)
        let secondDay = LocalDay(year: 2026, month: 2, day: 18)

        try repository.upsertActivityDays([
            ActivityDayRecord(day: firstDay, source: .github, status: .inactive, updatedAt: Date(), provenance: .api),
            ActivityDayRecord(day: secondDay, source: .github, status: .active, updatedAt: Date(), provenance: .api)
        ])

        let start = Date()
        try repository.logSyncRun(
            SyncRunRecord(provider: "github", startedAt: start, finishedAt: Date(), status: .success, errorSummary: nil)
        )

        let latestRun = try repository.fetchLatestSyncRun(provider: "github")
        let mostRecentDay = try repository.fetchMostRecentActivityDay(source: .github)

        XCTAssertEqual(latestRun?.status, .success)
        XCTAssertEqual(mostRecentDay, secondDay)
    }
}
