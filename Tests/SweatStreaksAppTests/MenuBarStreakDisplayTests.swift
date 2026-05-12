import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore

final class MenuBarStreakDisplayTests: XCTestCase {
    func testItemsRespectVisibilitySettingsAndOrder() {
        let metrics: [ActivitySource: StreakMetrics] = [
            .github: metrics(source: .github, current: 4),
            .leetcode: metrics(source: .leetcode, current: 6),
            .combined: metrics(source: .combined, current: 10)
        ]
        let statuses: [ActivitySource: DayStatus] = [
            .github: .active,
            .leetcode: .inactive,
            .combined: .unknown
        ]

        let items = MenuBarStreakDisplay.items(
            metrics: metrics,
            statuses: statuses,
            showGitHub: true,
            showLeetCode: false,
            showCombined: true
        )

        XCTAssertEqual(items.map(\.source), [.github, .combined])
        XCTAssertEqual(items.map(\.current), [4, 10])
        XCTAssertEqual(items.map(\.status), [.active, .unknown])
        XCTAssertEqual(
            MenuBarStreakDisplay.accessibilityLabel(for: items),
            "Sweat Streaks: GitHub 4-day streak, today active; Combined 10-day streak, today unknown"
        )
    }

    func testItemsAreEmittedForZeroStreaks() {
        let items = MenuBarStreakDisplay.items(
            metrics: [:],
            statuses: [:],
            showGitHub: true,
            showLeetCode: true,
            showCombined: true
        )

        XCTAssertEqual(items.map(\.source), [.github, .leetcode, .combined])
        XCTAssertEqual(items.map(\.current), [0, 0, 0])
    }

    func testAccessibilityLabelFallsBackWhenAllSourcesHidden() {
        let items = MenuBarStreakDisplay.items(
            metrics: [:],
            statuses: [:],
            showGitHub: false,
            showLeetCode: false,
            showCombined: false
        )

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(MenuBarStreakDisplay.accessibilityLabel(for: items), "Sweat Streaks")
    }

    private func metrics(source: ActivitySource, current: Int) -> StreakMetrics {
        StreakMetrics(
            source: source,
            current: current,
            longest: current,
            lastActiveDay: nil,
            completion7d: 0,
            completion30d: 0
        )
    }
}
