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
