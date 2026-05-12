import Foundation
import XCTest
@testable import SweatStreaksCore
@testable import SweatStreaksProviderClaudeCode

final class ClaudeCodeProviderTests: XCTestCase {
    func testMapsHistoryTimestampsToActiveDaysAndFillsInactiveDays() async throws {
        let root = try makeTemporaryDirectory()
        try writeJSONL(
            at: root.appendingPathComponent("history.jsonl"),
            lines: [
                #"{"timestamp":"2026-05-12T10:00:00.000Z","sessionId":"one","project":"demo"}"#
            ]
        )

        let provider = ClaudeCodeProvider(claudeDirectory: root)
        let result = try await provider.fetchActivityDays(
            range: Self.date(year: 2026, month: 5, day: 12)...Self.date(year: 2026, month: 5, day: 13, hour: 23)
        )

        XCTAssertNil(result.warning)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .active)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 13)], .inactive)
    }

    func testScansProjectLogsAndSkipsMalformedLines() async throws {
        let root = try makeTemporaryDirectory()
        try writeJSONL(
            at: root.appendingPathComponent("projects/-Users-anthony/session.jsonl"),
            lines: [
                "not json",
                #"{"timestamp":"2026-05-13T09:00:00Z","type":"user","sessionId":"two"}"#
            ]
        )

        let provider = ClaudeCodeProvider(claudeDirectory: root)
        let result = try await provider.fetchActivityDays(
            range: Self.date(year: 2026, month: 5, day: 12)...Self.date(year: 2026, month: 5, day: 13, hour: 23)
        )

        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .inactive)
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 13)], .active)
    }

    func testMissingLogDirectoryReturnsSanitizedWarning() async throws {
        let provider = ClaudeCodeProvider(claudeDirectory: try makeTemporaryDirectory().appendingPathComponent("missing"))
        let start = Self.date(year: 2026, month: 5, day: 12, hour: 12)
        let result = try await provider.fetchActivityDays(range: start...start)

        XCTAssertEqual(result.warning, "No Claude Code activity logs found.")
        XCTAssertEqual(result.days[LocalDay(year: 2026, month: 5, day: 12)], .inactive)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeJSONL(at url: URL, lines: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }
}
