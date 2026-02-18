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
        XCTAssertEqual(CombinedStatusResolver.derive(github: .active, leetcode: .inactive), .inactive)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .inactive, leetcode: .active), .inactive)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .unknown, leetcode: .active), .unknown)
        XCTAssertEqual(CombinedStatusResolver.derive(github: .unknown, leetcode: .unknown), .unknown)
    }
}
