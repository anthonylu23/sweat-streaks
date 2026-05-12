import Foundation

public enum ActivitySource: String, Codable, CaseIterable, Sendable {
    case github
    case leetcode
    case combined

    public static let currentProviderSources: [ActivitySource] = [.github, .leetcode]
    public static let combinedRequiredSources: [ActivitySource] = currentProviderSources
}

public enum DayStatus: String, Codable, Sendable {
    case active
    case inactive
    case unknown
}

public enum OverrideStatus: String, Codable, Sendable {
    case active
    case inactive
}

public enum Provenance: String, Codable, Sendable {
    case api
    case fallback
    case derived
    case manual
}

public enum SyncTrigger: String, Codable, Sendable {
    case launch
    case timer
    case manual
}

public enum ProviderError: Error, Sendable {
    case network
    case rateLimited(retryAfter: Date?)
    case auth
    case decoding
    case unknown(message: String)
}

public struct ProviderSyncState: Equatable, Sendable {
    public let source: ActivitySource
    public let lastSuccessAt: Date?
    public let cooldownUntil: Date?
    public let lastError: String?
    public let isStale: Bool

    public init(source: ActivitySource, lastSuccessAt: Date?, cooldownUntil: Date?, lastError: String?, isStale: Bool) {
        self.source = source
        self.lastSuccessAt = lastSuccessAt
        self.cooldownUntil = cooldownUntil
        self.lastError = lastError
        self.isStale = isStale
    }
}

public enum SyncDefaults {
    public static let initialBackfillDays = 90
    public static let incrementalBackfillDays = 14
    public static let staleThresholdHours = 24
    public static let rateLimitCooldownMinutes = 30
    public static let maxAttempts = 3
}

public protocol SyncClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: SyncClock {
    public init() {}
    public var now: Date { Date() }
}

public struct LocalDay: Hashable, Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var isoDate: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(isoDate: String) {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        guard (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        let candidate = LocalDay(year: year, month: month, day: day)
        guard candidate.isValidDate(in: .current) else {
            return nil
        }

        self = candidate
    }

    public func date(in timeZone: TimeZone) -> Date? {
        guard isValidDate(in: timeZone) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(timeZone: timeZone, year: year, month: month, day: day)
        return calendar.date(from: components)
    }

    private func isValidDate(in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(timeZone: timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return false
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    public static func from(date: Date, in timeZone: TimeZone) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public struct ManualOverride: Equatable, Sendable {
    public let day: LocalDay
    public let source: ActivitySource
    public let status: OverrideStatus
    public let note: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(day: LocalDay, source: ActivitySource, status: OverrideStatus, note: String?, createdAt: Date, updatedAt: Date) {
        self.day = day
        self.source = source
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ActivityDayRecord: Equatable, Sendable {
    public let day: LocalDay
    public let source: ActivitySource
    public let status: DayStatus
    public let updatedAt: Date
    public let provenance: Provenance

    public init(day: LocalDay, source: ActivitySource, status: DayStatus, updatedAt: Date, provenance: Provenance) {
        self.day = day
        self.source = source
        self.status = status
        self.updatedAt = updatedAt
        self.provenance = provenance
    }
}

public struct ProviderFetchResult: Sendable {
    public let source: ActivitySource
    public let days: [LocalDay: DayStatus]
    public let fetchedRange: ClosedRange<Date>
    public let rateLimitedUntil: Date?
    public let authError: Bool
    public let warning: String?

    public init(source: ActivitySource, days: [LocalDay: DayStatus], fetchedRange: ClosedRange<Date>, rateLimitedUntil: Date?, authError: Bool, warning: String?) {
        self.source = source
        self.days = days
        self.fetchedRange = fetchedRange
        self.rateLimitedUntil = rateLimitedUntil
        self.authError = authError
        self.warning = warning
    }
}

public struct StreakMetrics: Equatable, Sendable {
    public let source: ActivitySource
    public let current: Int
    public let longest: Int
    public let lastActiveDay: LocalDay?
    public let completion7d: Double
    public let completion30d: Double

    public init(source: ActivitySource, current: Int, longest: Int, lastActiveDay: LocalDay?, completion7d: Double, completion30d: Double) {
        self.source = source
        self.current = current
        self.longest = longest
        self.lastActiveDay = lastActiveDay
        self.completion7d = completion7d
        self.completion30d = completion30d
    }
}

public protocol ActivityProvider: Sendable {
    var source: ActivitySource { get }
    func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult
}

public protocol SyncService: Sendable {
    func refreshNow(trigger: SyncTrigger) async
}
