import Foundation
import GRDB
import SweatStreaksCore
import SweatStreaksProviderLocalSupport

public struct CursorProvider: ActivityProvider {
    public let source: ActivitySource = .cursor

    private let cursorDirectory: URL
    private let applicationSupportDirectory: URL

    public init(
        cursorDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true),
        applicationSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
    ) {
        self.cursorDirectory = cursorDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult {
        let activeDays = Self.scanActivityDays(
            cursorDirectory: cursorDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            range: range
        )
        let days = LocalActivityLogScanner.dayStatusMap(activeDays: activeDays, range: range)
        let hasEvidence = Self.hasLocalActivityEvidence(
            cursorDirectory: cursorDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )

        return ProviderFetchResult(
            source: .cursor,
            days: days,
            fetchedRange: range,
            rateLimitedUntil: nil,
            authError: false,
            warning: hasEvidence ? nil : "No Cursor AI activity found."
        )
    }

    public static func hasLocalActivityEvidence(
        cursorDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor", isDirectory: true),
        applicationSupportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor", isDirectory: true),
        fileManager: FileManager = .default
    ) -> Bool {
        if !aiMetadataEvidenceDates(
            cursorDirectory: cursorDirectory,
            fileManager: fileManager
        ).isEmpty {
            return true
        }

        return aiTrackingDatabaseHasRows(cursorDirectory: cursorDirectory)
            || globalStateDatabaseHasDailyStats(applicationSupportDirectory: applicationSupportDirectory)
    }

    public static func scanActivityDays(
        cursorDirectory: URL,
        applicationSupportDirectory: URL,
        range: ClosedRange<Date>,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> Set<LocalDay> {
        var activeDays: Set<LocalDay> = []

        for date in aiMetadataEvidenceDates(
            cursorDirectory: cursorDirectory,
            fileManager: fileManager
        ) where range.contains(date) {
            activeDays.insert(LocalDay.from(date: date, in: timeZone))
        }

        let localRange = localDayRange(for: range, in: timeZone)
        activeDays.formUnion(
            aiTrackingActivityDays(
                cursorDirectory: cursorDirectory,
                localRange: localRange,
                timeZone: timeZone
            )
        )
        activeDays.formUnion(
            globalStateActivityDays(
                applicationSupportDirectory: applicationSupportDirectory,
                localRange: localRange
            )
        )

        return activeDays.filter { $0 >= localRange.lowerBound && $0 <= localRange.upperBound }
    }

    private static func aiMetadataEvidenceDates(
        cursorDirectory: URL,
        fileManager: FileManager
    ) -> [Date] {
        aiMetadataFiles(
            cursorDirectory: cursorDirectory,
            fileManager: fileManager
        ).compactMap { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    private static func aiMetadataFiles(
        cursorDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        let projectFiles = regularFiles(
            under: cursorDirectory.appendingPathComponent("projects", isDirectory: true),
            fileManager: fileManager
        ).filter { isProjectAIEvidenceFile($0) }

        let chatFiles = regularFiles(
            under: cursorDirectory.appendingPathComponent("chats", isDirectory: true),
            fileManager: fileManager
        ).filter { $0.lastPathComponent == "store.db" }

        return projectFiles + chatFiles
    }

    private static func regularFiles(under root: URL, fileManager: FileManager) -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return [] }

        if !isDirectory.boolValue {
            return [root]
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            files.append(url)
        }
        return files
    }

    private static func isProjectAIEvidenceFile(_ url: URL) -> Bool {
        if url.lastPathComponent == "worker.log" {
            return true
        }
        return url.path.contains("/agent-transcripts/") && url.pathExtension == "jsonl"
    }

    private static func aiTrackingActivityDays(
        cursorDirectory: URL,
        localRange: ClosedRange<LocalDay>,
        timeZone: TimeZone
    ) -> Set<LocalDay> {
        let dbURL = cursorDirectory.appendingPathComponent("ai-tracking/ai-code-tracking.db", isDirectory: false)
        return readSQLiteDatabase(at: dbURL) { db in
            var days: Set<LocalDay> = []

            for column in ["createdAt", "timestamp"] {
                let timestamps = try Int64.fetchAll(
                    db,
                    sql: "SELECT \(column) FROM ai_code_hashes WHERE \(column) IS NOT NULL"
                )
                for timestamp in timestamps {
                    let day = LocalDay.from(date: date(fromEpochMilliseconds: timestamp), in: timeZone)
                    if localRange.contains(day) {
                        days.insert(day)
                    }
                }
            }

            let deletedAtValues = try Int64.fetchAll(db, sql: "SELECT deletedAt FROM ai_deleted_files")
            for timestamp in deletedAtValues {
                let day = LocalDay.from(date: date(fromEpochMilliseconds: timestamp), in: timeZone)
                if localRange.contains(day) {
                    days.insert(day)
                }
            }

            return days
        } ?? []
    }

    private static func globalStateActivityDays(
        applicationSupportDirectory: URL,
        localRange: ClosedRange<LocalDay>
    ) -> Set<LocalDay> {
        let dbURL = applicationSupportDirectory.appendingPathComponent("User/globalStorage/state.vscdb", isDirectory: false)
        return readSQLiteDatabase(at: dbURL) { db in
            let keys = try String.fetchAll(
                db,
                sql: "SELECT key FROM ItemTable WHERE key LIKE 'aiCodeTracking.dailyStats.%'"
            )
            return Set(keys.compactMap { dayFromDailyStatsKey($0) }.filter { localRange.contains($0) })
        } ?? []
    }

    private static func aiTrackingDatabaseHasRows(cursorDirectory: URL) -> Bool {
        let dbURL = cursorDirectory.appendingPathComponent("ai-tracking/ai-code-tracking.db", isDirectory: false)
        return readSQLiteDatabase(at: dbURL) { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_code_hashes") ?? 0) > 0
        } ?? false
    }

    private static func globalStateDatabaseHasDailyStats(applicationSupportDirectory: URL) -> Bool {
        let dbURL = applicationSupportDirectory.appendingPathComponent("User/globalStorage/state.vscdb", isDirectory: false)
        return readSQLiteDatabase(at: dbURL) { db in
            (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ItemTable WHERE key LIKE 'aiCodeTracking.dailyStats.%'"
            ) ?? 0) > 0
        } ?? false
    }

    private static func readSQLiteDatabase<T>(at url: URL, block: (Database) throws -> T) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            var configuration = Configuration()
            configuration.readonly = true
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            return try queue.read(block)
        } catch {
            return nil
        }
    }

    private static func dayFromDailyStatsKey(_ key: String) -> LocalDay? {
        guard let range = key.range(of: #"(\d{4}-\d{2}-\d{2})$"#, options: .regularExpression) else {
            return nil
        }
        return LocalDay(isoDate: String(key[range]))
    }

    private static func date(fromEpochMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private static func localDayRange(for range: ClosedRange<Date>, in timeZone: TimeZone) -> ClosedRange<LocalDay> {
        LocalDay.from(date: range.lowerBound, in: timeZone)...LocalDay.from(date: range.upperBound, in: timeZone)
    }
}
