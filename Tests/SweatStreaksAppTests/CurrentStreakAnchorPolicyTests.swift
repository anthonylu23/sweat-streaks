import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore

final class CurrentStreakAnchorPolicyTests: XCTestCase {
    private let timeZone = TimeZone(secondsFromGMT: 0)!
    private let today = LocalDay(year: 2026, month: 2, day: 18)
    private let yesterday = LocalDay(year: 2026, month: 2, day: 17)
    private let dayBefore = LocalDay(year: 2026, month: 2, day: 16)

    func testInactiveProviderStatusTodayAnchorsToYesterday() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .github,
            today: today,
            todayStatuses: [.github: .inactive],
            todayOverrides: [:],
            in: timeZone
        )

        XCTAssertEqual(anchor, yesterday)
    }

    func testAppMetricsReturnOneForSnapchatStyleYesterdayOnlyGitHubStreak() {
        let metrics = AppModel.makeMetrics(
            effectiveDays: (
                github: [
                    today: .inactive,
                    yesterday: .active,
                    dayBefore: .inactive
                ],
                leetcode: [:],
                combined: [:]
            ),
            today: today,
            todayStatuses: [.github: .inactive],
            todayOverrides: [:]
        )

        XCTAssertEqual(metrics[.github]?.current, 1)
        XCTAssertEqual(metrics[.github]?.longest, 1)
    }

    func testAppMetricsReturnOneForUnknownTodayAndActiveYesterday() {
        let metrics = AppModel.makeMetrics(
            effectiveDays: (
                github: [
                    today: .unknown,
                    yesterday: .active,
                    dayBefore: .inactive
                ],
                leetcode: [:],
                combined: [:]
            ),
            today: today,
            todayStatuses: [.github: .unknown],
            todayOverrides: [:]
        )

        XCTAssertEqual(metrics[.github]?.current, 1)
    }

    func testUnknownProviderStatusTodayAnchorsToYesterday() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .leetcode,
            today: today,
            todayStatuses: [.leetcode: .unknown],
            todayOverrides: [:],
            in: timeZone
        )

        XCTAssertEqual(anchor, yesterday)
    }

    func testActiveProviderStatusTodayAnchorsToToday() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .github,
            today: today,
            todayStatuses: [.github: .active],
            todayOverrides: [:],
            in: timeZone
        )

        XCTAssertEqual(anchor, today)
    }

    func testAppMetricsIncludeTodayWhenTodayIsActive() {
        let metrics = AppModel.makeMetrics(
            effectiveDays: (
                github: [
                    today: .active,
                    yesterday: .active,
                    dayBefore: .inactive
                ],
                leetcode: [:],
                combined: [:]
            ),
            today: today,
            todayStatuses: [.github: .active],
            todayOverrides: [:]
        )

        XCTAssertEqual(metrics[.github]?.current, 2)
    }

    func testManualInactiveTodayAnchorsToTodayAndResets() {
        let statuses: [ActivitySource: DayStatus] = [
            .github: .inactive
        ]
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .github,
            today: today,
            todayStatuses: statuses,
            todayOverrides: [.github: override(source: .github, status: .inactive)],
            in: timeZone
        )
        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                today: .inactive,
                yesterday: .active,
                dayBefore: .active
            ],
            asOf: today,
            currentStreakAsOf: anchor,
            in: timeZone
        )

        XCTAssertEqual(anchor, today)
        XCTAssertEqual(metrics.current, 0)
    }

    func testAppMetricsManualInactiveTodayResetsToZero() {
        let metrics = AppModel.makeMetrics(
            effectiveDays: (
                github: [
                    today: .inactive,
                    yesterday: .active,
                    dayBefore: .inactive
                ],
                leetcode: [:],
                combined: [:]
            ),
            today: today,
            todayStatuses: [.github: .inactive],
            todayOverrides: [.github: override(source: .github, status: .inactive)]
        )

        XCTAssertEqual(metrics[.github]?.current, 0)
    }

    func testManualActiveTodayAnchorsToToday() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .leetcode,
            today: today,
            todayStatuses: [.leetcode: .active],
            todayOverrides: [.leetcode: override(source: .leetcode, status: .active)],
            in: timeZone
        )

        XCTAssertEqual(anchor, today)
    }

    func testCombinedManualInactiveOverrideAnchorsToToday() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .combined,
            today: today,
            todayStatuses: [.combined: .inactive],
            todayOverrides: [.leetcode: override(source: .leetcode, status: .inactive)],
            in: timeZone
        )

        XCTAssertEqual(anchor, today)
    }

    func testAfterMidnightYesterdayInactiveResetsEvenWithGraceAnchor() {
        let anchor = CurrentStreakAnchorPolicy.anchorDay(
            for: .github,
            today: today,
            todayStatuses: [.github: .unknown],
            todayOverrides: [:],
            in: timeZone
        )
        let metrics = StreakEngine.computeMetrics(
            source: .github,
            days: [
                today: .unknown,
                yesterday: .inactive,
                dayBefore: .active
            ],
            asOf: today,
            currentStreakAsOf: anchor,
            in: timeZone
        )

        XCTAssertEqual(anchor, yesterday)
        XCTAssertEqual(metrics.current, 0)
    }

    private func override(source: ActivitySource, status: OverrideStatus) -> ManualOverride {
        ManualOverride(
            day: today,
            source: source,
            status: status,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
