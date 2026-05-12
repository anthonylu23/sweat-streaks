import Foundation
import GRDB

public final class DatabaseManager {
    public let dbQueue: DatabaseQueue

    public init(path: String? = nil, inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let databasePath = try path ?? Self.defaultDatabasePath()
            let parentDirectory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: databasePath)
            try Self.restrictDatabasePermissions(at: databasePath)
        }

        let migrator = Self.makeMigrator()
        try migrator.migrate(dbQueue)
    }

    public static func defaultDatabasePath() throws -> String {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("SweatStreaks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sweat_streaks.sqlite").path
    }

    private static func restrictDatabasePermissions(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: path
        )
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createBaseSchema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS activity_days (
                  date_local TEXT NOT NULL,
                  source TEXT NOT NULL,
                  status TEXT NOT NULL,
                  provenance TEXT NOT NULL,
                  updated_at DATETIME NOT NULL,
                  PRIMARY KEY(date_local, source),
                  CHECK (date_local GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                  CHECK (status IN ('active','inactive','unknown')),
                  CHECK (source IN ('github','leetcode','combined')),
                  CHECK (provenance IN ('api','fallback','derived','manual'))
                );
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS manual_overrides (
                  date_local TEXT NOT NULL,
                  source TEXT NOT NULL,
                  status TEXT NOT NULL,
                  note TEXT,
                  created_at DATETIME NOT NULL,
                  updated_at DATETIME NOT NULL,
                  PRIMARY KEY(date_local, source),
                  CHECK (date_local GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                  CHECK (source IN ('github','leetcode')),
                  CHECK (status IN ('active','inactive'))
                );
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS sync_runs (
                  id INTEGER PRIMARY KEY,
                  provider TEXT NOT NULL,
                  started_at DATETIME NOT NULL,
                  finished_at DATETIME,
                  status TEXT NOT NULL,
                  error_summary TEXT,
                  CHECK (status IN ('success','partial','failed','rate_limited','auth_error'))
                );
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS settings (
                  key TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_activity_days_source_date
                ON activity_days(source, date_local);
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_sync_runs_provider_started_at
                ON sync_runs(provider, started_at DESC);
            """)
        }

        migrator.registerMigration("createProviderStates") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS provider_states (
                  source TEXT PRIMARY KEY,
                  last_success_at DATETIME,
                  cooldown_until DATETIME,
                  last_error TEXT,
                  is_stale INTEGER NOT NULL DEFAULT 0,
                  updated_at DATETIME NOT NULL,
                  CHECK (source IN ('github','leetcode','combined')),
                  CHECK (is_stale IN (0, 1))
                );
            """)
        }

        return migrator
    }
}
