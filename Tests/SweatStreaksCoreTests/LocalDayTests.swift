import XCTest
@testable import SweatStreaksCore

final class LocalDayTests: XCTestCase {
    func testISODateRoundTrip() {
        let day = LocalDay(year: 2026, month: 2, day: 18)
        XCTAssertEqual(day.isoDate, "2026-02-18")

        let parsed = LocalDay(isoDate: "2026-02-18")
        XCTAssertEqual(parsed, day)
    }

    func testInvalidISODateRejected() {
        XCTAssertNil(LocalDay(isoDate: "2026/02/18"))
        XCTAssertNil(LocalDay(isoDate: "2026-13-01"))
        XCTAssertNil(LocalDay(isoDate: "hello"))
    }

    func testFromDateUsesTimezone() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let date = formatter.date(from: "2026-02-18T01:30:00Z")!

        let utc = TimeZone(secondsFromGMT: 0)!
        let pst = TimeZone(identifier: "America/Los_Angeles")!

        let utcDay = LocalDay.from(date: date, in: utc)
        let pstDay = LocalDay.from(date: date, in: pst)

        XCTAssertEqual(utcDay.isoDate, "2026-02-18")
        XCTAssertEqual(pstDay.isoDate, "2026-02-17")
    }

    func testCombinedStatusTruthTable() {
        XCTAssertEqual(CombinedStatusResolver.derive(github: .active, leetcode: .active), .active)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .active, leetcode: .inactive), .active)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .inactive, leetcode: .active), .active)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .unknown, leetcode: .active), .active)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .inactive, leetcode: .inactive), .inactive)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .unknown, leetcode: .inactive), .unknown)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .unknown, leetcode: .unknown), .unknown)
    }

    func testCombinedStatusUsesIncludedSources() {
        let statuses: [ActivitySource: DayStatus] = [
            .github: .active,
            .leetcode: .unknown,
            .codex: .inactive
        ]

        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: statuses, includedSources: [.github]),
            .active
        )
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: statuses, includedSources: [.github, .leetcode]),
            .active
        )
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: statuses, includedSources: [.leetcode, .codex]),
            .unknown
        )
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: statuses, includedSources: []),
            .unknown
        )
    }

    func testDefaultCombinedStatusUsesAnyCurrentProviderActivity() {
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: [
                .github: .inactive,
                .leetcode: .inactive,
                .codex: .active,
                .claudeCode: .inactive,
                .cursor: .inactive
            ]),
            .active
        )
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: [
                .github: .inactive,
                .leetcode: .inactive,
                .codex: .unknown,
                .claudeCode: .inactive,
                .cursor: .inactive
            ]),
            .unknown
        )
        XCTAssertEqual(
            CombinedStatusResolver.derive(effectiveStatuses: [
                .github: .inactive,
                .leetcode: .inactive,
                .codex: .inactive,
                .claudeCode: .inactive,
                .cursor: .inactive
            ]),
            .inactive
        )
    }
}
