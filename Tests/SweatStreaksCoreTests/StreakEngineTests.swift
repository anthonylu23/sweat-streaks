import XCTest
@testable import SweatStreaksCore

final class StreakEngineTests: XCTestCase {
    func testCurrentStreakStopsAtUnknownDay() {
        let asOf = LocalDay(year: 2026, month: 2, day: 18)
        let dayMinus1 = LocalDay(year: 2026, month: 2, day: 17)
        let dayMinus2 = LocalDay(year: 2026, month: 2, day: 16)

        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                asOf: .active,
                dayMinus1: .unknown,
                dayMinus2: .active
            ],
            asOf: asOf,
            in: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(metrics.current, 1)
        XCTAssertEqual(metrics.longest, 1)
    }

    func testDefaultCurrentStreakStopsWhenTodayIsInactive() {
        let today = LocalDay(year: 2026, month: 2, day: 18)
        let yesterday = LocalDay(year: 2026, month: 2, day: 17)
        let dayBefore = LocalDay(year: 2026, month: 2, day: 16)

        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                today: .inactive,
                yesterday: .active,
                dayBefore: .active
            ],
            asOf: today,
            in: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(metrics.current, 0)
        XCTAssertEqual(metrics.longest, 2)
    }

    func testCurrentStreakCanUseYesterdayAnchorWithoutChangingOtherMetrics() {
        let today = LocalDay(year: 2026, month: 2, day: 18)
        let yesterday = LocalDay(year: 2026, month: 2, day: 17)
        let dayBefore = LocalDay(year: 2026, month: 2, day: 16)

        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                today: .inactive,
                yesterday: .active,
                dayBefore: .active
            ],
            asOf: today,
            currentStreakAsOf: yesterday,
            in: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(metrics.current, 2)
        XCTAssertEqual(metrics.longest, 2)
        XCTAssertEqual(metrics.completion7d, 2.0 / 7.0)
    }

    func testYesterdayAnchorReturnsOneWhenOnlyYesterdayIsActive() {
        let today = LocalDay(year: 2026, month: 2, day: 18)
        let yesterday = LocalDay(year: 2026, month: 2, day: 17)
        let dayBefore = LocalDay(year: 2026, month: 2, day: 16)

        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                today: .inactive,
                yesterday: .active,
                dayBefore: .inactive
            ],
            asOf: today,
            currentStreakAsOf: yesterday,
            in: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(metrics.current, 1)
        XCTAssertEqual(metrics.longest, 1)
    }

    func testStreakMathUsesProvidedTimezoneAcrossDST() {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let asOf = LocalDay(year: 2026, month: 3, day: 9)
        let previous = LocalDay(year: 2026, month: 3, day: 8)
        let beforeDST = LocalDay(year: 2026, month: 3, day: 7)

        let metrics = StreakEngine.computeMetrics(
            source: .combined,
            days: [
                asOf: .active,
                previous: .active,
                beforeDST: .active
            ],
            asOf: asOf,
            in: timeZone
        )

        XCTAssertEqual(metrics.current, 3)
        XCTAssertEqual(metrics.longest, 3)
    }
}
