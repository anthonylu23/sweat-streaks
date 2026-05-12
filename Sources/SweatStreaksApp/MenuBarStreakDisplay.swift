import Foundation
import SweatStreaksCore

struct MenuBarStreakItem: Equatable, Identifiable {
    let source: ActivitySource
    let current: Int
    let status: DayStatus

    var id: ActivitySource { source }
}

enum MenuBarStreakDisplay {
    static func items(
        metrics: [ActivitySource: StreakMetrics],
        statuses: [ActivitySource: DayStatus],
        trackGitHub: Bool = true,
        trackLeetCode: Bool = true,
        trackCodex: Bool = true,
        trackClaudeCode: Bool = true,
        showGitHub: Bool,
        showLeetCode: Bool,
        showCodex: Bool,
        showClaudeCode: Bool,
        showCombined: Bool
    ) -> [MenuBarStreakItem] {
        [
            (ActivitySource.github, trackGitHub && showGitHub),
            (.leetcode, trackLeetCode && showLeetCode),
            (.codex, trackCodex && showCodex),
            (.claudeCode, trackClaudeCode && showClaudeCode),
            (.combined, showCombined)
        ].compactMap { source, isVisible in
            guard isVisible else { return nil }
            return MenuBarStreakItem(
                source: source,
                current: metrics[source]?.current ?? 0,
                status: statuses[source] ?? .unknown
            )
        }
    }

    static func accessibilityLabel(for items: [MenuBarStreakItem]) -> String {
        guard !items.isEmpty else {
            return "Sweat Streaks"
        }

        let summaries = items.map { item in
            "\(name(for: item.source)) \(item.current)-day streak, today \(item.status.rawValue)"
        }
        return "Sweat Streaks: \(summaries.joined(separator: "; "))"
    }

    private static func name(for source: ActivitySource) -> String {
        source.displayName
    }
}
