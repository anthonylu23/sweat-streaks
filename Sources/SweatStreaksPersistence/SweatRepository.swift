import Foundation
import GRDB
import SweatStreaksCore

public enum SyncRunStatus: String, Sendable {
    case success
    case partial
    case failed
    case rateLimited = "rate_limited"
    case authError = "auth_error"
}

public struct SyncRunRecord: Equatable, Sendable {
    public let provider: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: SyncRunStatus
    public let errorSummary: String?

    public init(provider: String, startedAt: Date, finishedAt: Date?, status: SyncRunStatus, errorSummary: String?) {
        self.provider = provider
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.errorSummary = errorSummary
    }
}

public final class SweatRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func upsertActivityDayRecord(_ record: ActivityDayRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activity_days (date_local, source, status, provenance, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(date_local, source)
                    DO UPDATE SET
                      status = excluded.status,
                      provenance = excluded.provenance,
                      updated_at = excluded.updated_at;
                """,
                arguments: [
                    record.day.isoDate,
                    record.source.rawValue,
                    record.status.rawValue,
                    record.provenance.rawValue,
                    record.updatedAt
                ]
            )
        }
    }

    public func upsertActivityDays(_ records: [ActivityDayRecord]) throws {
        guard !records.isEmpty else { return }
        try dbQueue.write { db in
            for record in records {
                try db.execute(
                    sql: """
                        INSERT INTO activity_days (date_local, source, status, provenance, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(date_local, source)
                        DO UPDATE SET
                          status = excluded.status,
                          provenance = excluded.provenance,
                          updated_at = excluded.updated_at;
                    """,
                    arguments: [
                        record.day.isoDate,
                        record.source.rawValue,
                        record.status.rawValue,
                        record.provenance.rawValue,
                        record.updatedAt
                    ]
                )
            }
        }
    }

    public func fetchActivityDayRecord(day: LocalDay, source: ActivitySource) throws -> ActivityDayRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT date_local, source, status, provenance, updated_at
                    FROM activity_days
                    WHERE date_local = ? AND source = ?
                """,
                arguments: [day.isoDate, source.rawValue]
            ) else {
                return nil
            }

            guard let sourceValue = ActivitySource(rawValue: row["source"]),
                  let statusValue = DayStatus(rawValue: row["status"]),
                  let provenanceValue = Provenance(rawValue: row["provenance"]),
                  let storedDay = LocalDay(isoDate: row["date_local"]) else {
                return nil
            }

            return ActivityDayRecord(
                day: storedDay,
                source: sourceValue,
                status: statusValue,
                updatedAt: row["updated_at"],
                provenance: provenanceValue
            )
        }
    }

    public func deleteActivityDayRecord(day: LocalDay, source: ActivitySource) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM activity_days WHERE date_local = ? AND source = ?",
                arguments: [day.isoDate, source.rawValue]
            )
        }
    }

    public func deleteActivityDays(after day: LocalDay) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM activity_days WHERE date_local > ?",
                arguments: [day.isoDate]
            )
        }
    }

    public func fetchActivityDays(source: ActivitySource, from: LocalDay, to: LocalDay) throws -> [LocalDay: DayStatus] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date_local, status
                    FROM activity_days
                    WHERE source = ? AND date_local >= ? AND date_local <= ?
                    ORDER BY date_local ASC
                """,
                arguments: [source.rawValue, from.isoDate, to.isoDate]
            )

            var dayMap: [LocalDay: DayStatus] = [:]
            for row in rows {
                guard let day = LocalDay(isoDate: row["date_local"]),
                      let status = DayStatus(rawValue: row["status"]) else {
                    continue
                }
                dayMap[day] = status
            }
            return dayMap
        }
    }

    public func fetchMostRecentActivityDay(source: ActivitySource) throws -> LocalDay? {
        try dbQueue.read { db in
            guard let date: String = try String.fetchOne(
                db,
                sql: """
                    SELECT date_local
                    FROM activity_days
                    WHERE source = ?
                    ORDER BY date_local DESC
                    LIMIT 1
                """,
                arguments: [source.rawValue]
            ) else {
                return nil
            }
            return LocalDay(isoDate: date)
        }
    }

    public func setManualStatus(day: LocalDay, source: ActivitySource, status: OverrideStatus, note: String?) throws {
        guard ActivitySource.currentProviderSources.contains(source) else {
            throw RepositoryError.invalidOverrideSource
        }

        let now = Date()

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO manual_overrides (date_local, source, status, note, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(date_local, source)
                    DO UPDATE SET
                      status = excluded.status,
                      note = excluded.note,
                      updated_at = excluded.updated_at;
                """,
                arguments: [
                    day.isoDate,
                    source.rawValue,
                    status.rawValue,
                    note,
                    now,
                    now
                ]
            )
        }
    }

    public func clearManualStatus(day: LocalDay, source: ActivitySource) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM manual_overrides WHERE date_local = ? AND source = ?",
                arguments: [day.isoDate, source.rawValue]
            )
        }
    }

    public func fetchManualOverride(day: LocalDay, source: ActivitySource) throws -> ManualOverride? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT date_local, source, status, note, created_at, updated_at
                    FROM manual_overrides
                    WHERE date_local = ? AND source = ?
                """,
                arguments: [day.isoDate, source.rawValue]
            ) else {
                return nil
            }

            guard let parsedDay = LocalDay(isoDate: row["date_local"]),
                  let parsedSource = ActivitySource(rawValue: row["source"]),
                  let parsedStatus = OverrideStatus(rawValue: row["status"]) else {
                return nil
            }

            return ManualOverride(
                day: parsedDay,
                source: parsedSource,
                status: parsedStatus,
                note: row["note"],
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    public func fetchManualOverrides(from: LocalDay, to: LocalDay) throws -> [LocalDay: [ActivitySource: ManualOverride]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date_local, source, status, note, created_at, updated_at
                    FROM manual_overrides
                    WHERE date_local >= ? AND date_local <= ?
                    ORDER BY date_local ASC
                """,
                arguments: [from.isoDate, to.isoDate]
            )

            var overrides: [LocalDay: [ActivitySource: ManualOverride]] = [:]
            for row in rows {
                guard let parsedDay = LocalDay(isoDate: row["date_local"]),
                      let parsedSource = ActivitySource(rawValue: row["source"]),
                      let parsedStatus = OverrideStatus(rawValue: row["status"]) else {
                    continue
                }

                let override = ManualOverride(
                    day: parsedDay,
                    source: parsedSource,
                    status: parsedStatus,
                    note: row["note"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
                overrides[parsedDay, default: [:]][parsedSource] = override
            }
            return overrides
        }
    }

    public func upsertProviderSyncState(_ state: ProviderSyncState, updatedAt: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO provider_states (source, last_success_at, cooldown_until, last_error, is_stale, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(source)
                    DO UPDATE SET
                      last_success_at = excluded.last_success_at,
                      cooldown_until = excluded.cooldown_until,
                      last_error = excluded.last_error,
                      is_stale = excluded.is_stale,
                      updated_at = excluded.updated_at;
                """,
                arguments: [
                    state.source.rawValue,
                    state.lastSuccessAt,
                    state.cooldownUntil,
                    state.lastError,
                    state.isStale ? 1 : 0,
                    updatedAt
                ]
            )
        }
    }

    public func fetchProviderSyncState(source: ActivitySource) throws -> ProviderSyncState? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT source, last_success_at, cooldown_until, last_error, is_stale
                    FROM provider_states
                    WHERE source = ?
                """,
                arguments: [source.rawValue]
            ) else {
                return nil
            }

            guard let parsedSource = ActivitySource(rawValue: row["source"]) else {
                return nil
            }

            let isStaleValue: Int = row["is_stale"]
            return ProviderSyncState(
                source: parsedSource,
                lastSuccessAt: row["last_success_at"],
                cooldownUntil: row["cooldown_until"],
                lastError: row["last_error"],
                isStale: isStaleValue == 1
            )
        }
    }

    public func fetchProviderSyncStates() throws -> [ActivitySource: ProviderSyncState] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT source, last_success_at, cooldown_until, last_error, is_stale
                    FROM provider_states
                """
            )

            var states: [ActivitySource: ProviderSyncState] = [:]
            for row in rows {
                guard let parsedSource = ActivitySource(rawValue: row["source"]) else {
                    continue
                }
                let isStaleValue: Int = row["is_stale"]
                states[parsedSource] = ProviderSyncState(
                    source: parsedSource,
                    lastSuccessAt: row["last_success_at"],
                    cooldownUntil: row["cooldown_until"],
                    lastError: row["last_error"],
                    isStale: isStaleValue == 1
                )
            }
            return states
        }
    }

    public func setSetting(key: String, value: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value)
                    VALUES (?, ?)
                    ON CONFLICT(key)
                    DO UPDATE SET value = excluded.value;
                """,
                arguments: [key, value]
            )
        }
    }

    public func getSetting(key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func logSyncRun(_ run: SyncRunRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO sync_runs (provider, started_at, finished_at, status, error_summary)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    run.provider,
                    run.startedAt,
                    run.finishedAt,
                    run.status.rawValue,
                    run.errorSummary
                ]
            )
        }
    }

    public func fetchLatestSyncRun(provider: String) throws -> SyncRunRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT provider, started_at, finished_at, status, error_summary
                    FROM sync_runs
                    WHERE provider = ?
                    ORDER BY started_at DESC
                    LIMIT 1
                """,
                arguments: [provider]
            ) else {
                return nil
            }

            guard let status = SyncRunStatus(rawValue: row["status"]) else {
                return nil
            }

            return SyncRunRecord(
                provider: row["provider"],
                startedAt: row["started_at"],
                finishedAt: row["finished_at"],
                status: status,
                errorSummary: row["error_summary"]
            )
        }
    }

    public func fetchRecentSyncRuns(provider: String, limit: Int) throws -> [SyncRunRecord] {
        guard limit > 0 else { return [] }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT provider, started_at, finished_at, status, error_summary
                    FROM sync_runs
                    WHERE provider = ?
                    ORDER BY started_at DESC
                    LIMIT ?
                """,
                arguments: [provider, limit]
            )

            return rows.compactMap { row in
                guard let status = SyncRunStatus(rawValue: row["status"]) else {
                    return nil
                }

                return SyncRunRecord(
                    provider: row["provider"],
                    startedAt: row["started_at"],
                    finishedAt: row["finished_at"],
                    status: status,
                    errorSummary: row["error_summary"]
                )
            }
        }
    }

    public func fetchLatestSuccessfulSyncRun(provider: String) throws -> SyncRunRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT provider, started_at, finished_at, status, error_summary
                    FROM sync_runs
                    WHERE provider = ? AND status IN ('success', 'partial')
                    ORDER BY started_at DESC
                    LIMIT 1
                """,
                arguments: [provider]
            ) else {
                return nil
            }

            guard let status = SyncRunStatus(rawValue: row["status"]) else {
                return nil
            }

            return SyncRunRecord(
                provider: row["provider"],
                startedAt: row["started_at"],
                finishedAt: row["finished_at"],
                status: status,
                errorSummary: row["error_summary"]
            )
        }
    }
}

public enum RepositoryError: Error, Equatable {
    case invalidOverrideSource
}

public protocol SettingsStore {
    func get(_ key: SettingsKey) throws -> String?
    func set(_ value: String, for key: SettingsKey) throws
}

public enum SettingsKey: String {
    case githubUsername
    case leetCodeUsername
    case refreshIntervalMinutes
    case notificationsEnabled
    case reminderHour
    case startOnLogin
    case lastRiskNotificationDay
    case trackGitHubProvider
    case trackLeetCodeProvider
    case showGitHubStreakInMenuBar
    case showLeetCodeStreakInMenuBar
    case trackCodexProvider
    case trackClaudeCodeProvider
    case trackCursorProvider
    case codexPath
    case claudeCodePath
    case cursorPath
    case cursorApplicationSupportPath
    case showCodexStreakInMenuBar
    case showClaudeCodeStreakInMenuBar
    case showCursorStreakInMenuBar
    case showCombinedStreakInMenuBar
}

public final class SQLiteSettingsStore: SettingsStore {
    private let repository: SweatRepository

    public init(repository: SweatRepository) {
        self.repository = repository
    }

    public func get(_ key: SettingsKey) throws -> String? {
        try repository.getSetting(key: key.rawValue)
    }

    public func set(_ value: String, for key: SettingsKey) throws {
        try repository.setSetting(key: key.rawValue, value: value)
    }
}
