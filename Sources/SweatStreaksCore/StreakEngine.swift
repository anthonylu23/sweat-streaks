import Foundation

public enum CombinedStatusResolver {
    public static func derive(github: DayStatus, leetcode: DayStatus) -> DayStatus {
        derive(
            effectiveStatuses: [
                .github: github,
                .leetcode: leetcode
            ],
            requiredSources: ActivitySource.combinedRequiredSources
        )
    }

    public static func derive(effectiveStatuses: [ActivitySource: DayStatus]) -> DayStatus {
        derive(effectiveStatuses: effectiveStatuses, requiredSources: ActivitySource.combinedRequiredSources)
    }

    public static func derive(
        effectiveStatuses: [ActivitySource: DayStatus],
        requiredSources: [ActivitySource]
    ) -> DayStatus {
        guard !requiredSources.isEmpty else { return .unknown }

        let requiredStatuses = requiredSources.map { effectiveStatuses[$0] ?? .unknown }
        if requiredStatuses.contains(.inactive) {
            return .inactive
        }
        if requiredStatuses.allSatisfy({ $0 == .active }) {
            return .active
        }
        return .unknown
    }
}

public enum StreakEngine {
    public static func computeMetrics(
        source: ActivitySource,
        days: [LocalDay: DayStatus],
        asOf: LocalDay,
        currentStreakAsOf: LocalDay? = nil,
        in timeZone: TimeZone = .current
    ) -> StreakMetrics {
        let orderedDays = days.keys.sorted()
        let lastActiveDay = orderedDays.last(where: { days[$0] == .active })

        let current = currentStreak(days: days, asOf: currentStreakAsOf ?? asOf, in: timeZone)
        let longest = longestStreak(days: days, in: timeZone)

        return StreakMetrics(
            source: source,
            current: current,
            longest: longest,
            lastActiveDay: lastActiveDay,
            completion7d: completionRate(days: days, window: 7, asOf: asOf, in: timeZone),
            completion30d: completionRate(days: days, window: 30, asOf: asOf, in: timeZone)
        )
    }

    public static func applyOverrides(
        sourceStatuses: [ActivitySource: DayStatus],
        overrides: [ActivitySource: OverrideStatus]
    ) -> [ActivitySource: DayStatus] {
        var effective = sourceStatuses
        for (source, overrideStatus) in overrides {
            effective[source] = overrideStatus == .active ? .active : .inactive
        }
        return effective
    }

    private static func currentStreak(days: [LocalDay: DayStatus], asOf: LocalDay, in timeZone: TimeZone) -> Int {
        guard var cursorDate = asOf.date(in: timeZone) else { return 0 }
        let calendar = calendar(in: timeZone)
        var streak = 0

        while true {
            let cursorDay = LocalDay.from(date: cursorDate, in: timeZone)
            guard days[cursorDay] == .active else { break }
            streak += 1

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursorDate) else { break }
            cursorDate = previous
        }

        return streak
    }

    private static func longestStreak(days: [LocalDay: DayStatus], in timeZone: TimeZone) -> Int {
        let sorted = days.keys.sorted()
        guard !sorted.isEmpty else { return 0 }
        let calendar = calendar(in: timeZone)

        var longest = 0
        var running = 0
        var previousDate: Date?

        for day in sorted {
            guard days[day] == .active else {
                running = 0
                previousDate = nil
                continue
            }

            guard let dayDate = day.date(in: timeZone) else { continue }

            if let previousDate {
                let delta = calendar.dateComponents([.day], from: previousDate, to: dayDate).day
                if delta == 1 {
                    running += 1
                } else {
                    running = 1
                }
            } else {
                running = 1
            }

            previousDate = dayDate
            longest = max(longest, running)
        }

        return longest
    }

    private static func completionRate(days: [LocalDay: DayStatus], window: Int, asOf: LocalDay, in timeZone: TimeZone) -> Double {
        guard window > 0, let endDate = asOf.date(in: timeZone) else { return 0 }
        let calendar = calendar(in: timeZone)

        var activeCount = 0
        var total = 0

        for offset in 0..<window {
            guard let candidateDate = calendar.date(byAdding: .day, value: -offset, to: endDate) else {
                continue
            }
            let candidateDay = LocalDay.from(date: candidateDate, in: timeZone)
            if days[candidateDay] == .active {
                activeCount += 1
            }
            total += 1
        }

        guard total > 0 else { return 0 }
        return Double(activeCount) / Double(total)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
