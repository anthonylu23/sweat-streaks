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
}
