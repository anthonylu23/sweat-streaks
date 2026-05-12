import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore

final class MenuBarStreakDisplayTests: XCTestCase {
    func testItemsRespectVisibilitySettingsAndOrder() {
        let metrics: [ActivitySource: StreakMetrics] = [
            .github: metrics(source: .github, current: 4),
            .leetcode: metrics(source: .leetcode, current: 6),
            .codex: metrics(source: .codex, current: 3),
            .claudeCode: metrics(source: .claudeCode, current: 2),
            .cursor: metrics(source: .cursor, current: 5),
            .combined: metrics(source: .combined, current: 10)
        ]
        let statuses: [ActivitySource: DayStatus] = [
            .github: .active,
            .leetcode: .inactive,
            .codex: .active,
            .claudeCode: .unknown,
            .cursor: .active,
            .combined: .unknown
        ]

        let items = MenuBarStreakDisplay.items(
            metrics: metrics,
            statuses: statuses,
            showGitHub: true,
            showLeetCode: false,
            showCodex: true,
            showClaudeCode: false,
            showCursor: true,
            showCombined: true
        )

        XCTAssertEqual(items.map(\.source), [.github, .codex, .cursor, .combined])
        XCTAssertEqual(items.map(\.current), [4, 3, 5, 10])
        XCTAssertEqual(items.map(\.status), [.active, .active, .active, .unknown])
        XCTAssertEqual(
            MenuBarStreakDisplay.accessibilityLabel(for: items),
            "Sweat Streaks: GitHub 4-day streak, today active; Codex 3-day streak, today active; Cursor 5-day streak, today active; Combined 10-day streak, today unknown"
        )
    }

    func testItemsAreEmittedForZeroStreaks() {
        let items = MenuBarStreakDisplay.items(
            metrics: [:],
            statuses: [:],
            showGitHub: true,
            showLeetCode: true,
            showCodex: true,
            showClaudeCode: true,
            showCursor: true,
            showCombined: true
        )

        XCTAssertEqual(items.map(\.source), [.github, .leetcode, .codex, .claudeCode, .cursor, .combined])
        XCTAssertEqual(items.map(\.current), [0, 0, 0, 0, 0, 0])
    }

    func testAccessibilityLabelFallsBackWhenAllSourcesHidden() {
        let items = MenuBarStreakDisplay.items(
            metrics: [:],
            statuses: [:],
            showGitHub: false,
            showLeetCode: false,
            showCodex: false,
            showClaudeCode: false,
            showCursor: false,
            showCombined: false
        )

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(MenuBarStreakDisplay.accessibilityLabel(for: items), "Sweat Streaks")
    }

    func testItemsIgnoreProviderWhenTrackingIsDisabled() {
        let items = MenuBarStreakDisplay.items(
            metrics: [
                .github: metrics(source: .github, current: 4),
                .leetcode: metrics(source: .leetcode, current: 6),
                .cursor: metrics(source: .cursor, current: 3),
                .combined: metrics(source: .combined, current: 8)
            ],
            statuses: [
                .github: .active,
                .leetcode: .active,
                .cursor: .active,
                .combined: .active
            ],
            trackGitHub: false,
            trackLeetCode: true,
            trackCursor: false,
            showGitHub: true,
            showLeetCode: true,
            showCodex: false,
            showClaudeCode: false,
            showCursor: true,
            showCombined: true
        )

        XCTAssertEqual(items.map(\.source), [.leetcode, .combined])
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
