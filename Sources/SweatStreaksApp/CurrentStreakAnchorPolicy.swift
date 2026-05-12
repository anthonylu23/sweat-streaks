import Foundation
import SweatStreaksCore

enum CurrentStreakAnchorPolicy {
    static func anchorDay(
        for source: ActivitySource,
        today: LocalDay,
        todayStatuses: [ActivitySource: DayStatus],
        todayOverrides: [ActivitySource: ManualOverride],
        in timeZone: TimeZone = .current
    ) -> LocalDay {
        if shouldAnchorToToday(
            source: source,
            todayStatuses: todayStatuses,
            todayOverrides: todayOverrides
        ) {
            return today
        }

        return previousDay(before: today, in: timeZone) ?? today
    }

    private static func shouldAnchorToToday(
        source: ActivitySource,
        todayStatuses: [ActivitySource: DayStatus],
        todayOverrides: [ActivitySource: ManualOverride]
    ) -> Bool {
        switch source {
        case .github, .leetcode:
            if todayOverrides[source] != nil {
                return true
            }
            return todayStatuses[source] == .active
        case .combined:
            if todayOverrides.values.contains(where: { $0.status == .inactive }) {
                return true
            }
            return todayStatuses[.combined] == .active
        }
    }

    private static func previousDay(before day: LocalDay, in timeZone: TimeZone) -> LocalDay? {
        guard let date = day.date(in: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let previousDate = calendar.date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        return LocalDay.from(date: previousDate, in: timeZone)
    }
}
