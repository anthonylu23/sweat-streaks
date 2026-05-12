import Foundation
import GRDB
import XCTest
@testable import SweatStreaksCore
@testable import SweatStreaksProviderCursor

final class CursorProviderTests: XCTestCase {
    func testIgnoresNonAIApplicationAndProcessMonitorLogs() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.applicationSupport.appendingPathComponent("logs/20260512T090000", isDirectory: true),
            withIntermediateDirectories: true
        )
        let processMonitorDate = Self.date(year: 2026, month: 5, day: 14, hour: 16)
        let processMonitorName = "\(Int64(processMonitorDate.timeIntervalSince1970 * 1_000)).log"
        try writeFile(at: fixture.applicationSupport.appendingPathComponent("process-monitor/\(processMonitorName)"))

        let provider = CursorProvider(
            cursorDirectory: fixture.cursor,
            applicationSupportDirectory: fixture.applicationSupport
        )
        let result = try await provider.fetchActivityDays(
            range: Self.date(year: 2026, month: 5, day: 12)...Self.date(year: 2026, month: 5, day: 14, hour: 23)
        )

        XCTAssertEqual(result.warning, "No Cursor AI activity found.")
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 13)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 14)], .inactive)
    }

    func testUsesCursorAIMetadataModificationDatesWithoutReadingContent() async throws {
        let fixture = try makeFixture()
        let workerLog = fixture.cursor.appendingPathComponent("projects/demo/worker.log")
        try writeFile(at: workerLog)
        try setModificationDate(Self.date(year: 2026, month: 5, day: 13, hour: 10), for: workerLog)
        let transcript = fixture.cursor.appendingPathComponent("projects/demo/agent-transcripts/session/session.jsonl")
        try writeFile(at: transcript)
        try setModificationDate(Self.date(year: 2026, month: 5, day: 14, hour: 10), for: transcript)
        let chatStore = fixture.cursor.appendingPathComponent("chats/project/session/store.db")
        try writeFile(at: chatStore)
        try setModificationDate(Self.date(year: 2026, month: 5, day: 15, hour: 10), for: chatStore)
        let editHistory = fixture.applicationSupport.appendingPathComponent("User/History/project/file.swift")
        try writeFile(at: editHistory)
        try setModificationDate(Self.date(year: 2026, month: 5, day: 12, hour: 10), for: editHistory)

        let provider = CursorProvider(
            cursorDirectory: fixture.cursor,
            applicationSupportDirectory: fixture.applicationSupport
        )
        let result = try await provider.fetchActivityDays(
            range: Self.date(year: 2026, month: 5, day: 12)...Self.date(year: 2026, month: 5, day: 15, hour: 23)
        )

        XCTAssertNil(result.warning)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 13)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 14)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 15)], .active)
    }

    func testUsesCursorSQLiteTrackingEvidence() async throws {
        let fixture = try makeFixture()
        try createAITrackingDatabase(
            at: fixture.cursor.appendingPathComponent("ai-tracking/ai-code-tracking.db"),
            timestamp: Self.date(year: 2026, month: 5, day: 12, hour: 18)
        )
        try createGlobalStateDatabase(
            at: fixture.applicationSupport.appendingPathComponent("User/globalStorage/state.vscdb"),
            dailyStatsDay: "2026-05-14"
        )

        let provider = CursorProvider(
            cursorDirectory: fixture.cursor,
            applicationSupportDirectory: fixture.applicationSupport
        )
        let result = try await provider.fetchActivityDays(
            range: Self.date(year: 2026, month: 5, day: 12)...Self.date(year: 2026, month: 5, day: 14, hour: 23)
        )

        XCTAssertNil(result.warning)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 13)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 14)], .active)
    }

    func testMissingCursorEvidenceReturnsSanitizedWarning() async throws {
        let fixture = try makeFixture()
        let start = Self.date(year: 2026, month: 5, day: 12, hour: 12)
        let provider = CursorProvider(
            cursorDirectory: fixture.cursor.appendingPathComponent("missing"),
            applicationSupportDirectory: fixture.applicationSupport.appendingPathComponent("missing")
        )
        let result = try await provider.fetchActivityDays(range: start...start)

        XCTAssertEqual(result.warning, "No Cursor AI activity found.")
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .inactive)
    }

    private func makeFixture() throws -> (root: URL, cursor: URL, applicationSupport: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cursor = root.appendingPathComponent(".cursor", isDirectory: true)
        let applicationSupport = root.appendingPathComponent("Application Support/Cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (root, cursor, applicationSupport)
    }

    private func writeFile(at url: URL, contents: String = "metadata only") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func createAITrackingDatabase(at url: URL, timestamp: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        let milliseconds = Int64(timestamp.timeIntervalSince1970 * 1_000)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE ai_code_hashes (
                  hash TEXT PRIMARY KEY,
                  source TEXT NOT NULL,
                  fileExtension TEXT,
                  fileName TEXT,
                  requestId TEXT,
                  conversationId TEXT,
                  timestamp INTEGER,
                  createdAt INTEGER NOT NULL,
                  model TEXT
                );
            """)
            try db.execute(sql: """
                CREATE TABLE ai_deleted_files (
                  gitPath TEXT NOT NULL,
                  composerId TEXT,
                  conversationId TEXT,
                  model TEXT,
                  deletedAt INTEGER NOT NULL,
                  PRIMARY KEY (gitPath, deletedAt)
                );
            """)
            try db.execute(
                sql: "INSERT INTO ai_code_hashes (hash, source, timestamp, createdAt) VALUES ('hash', 'composer', ?, ?)",
                arguments: [milliseconds, milliseconds]
            )
        }
    }

    private func createGlobalStateDatabase(at url: URL, dailyStatsDay: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE ItemTable (key TEXT, value BLOB);")
            try db.execute(
                sql: "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                arguments: ["aiCodeTracking.dailyStats.v1.5.\(dailyStatsDay)", "{}"]
            )
        }
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }
}
