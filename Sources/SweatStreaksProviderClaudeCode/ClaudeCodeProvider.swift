import Foundation
import SweatStreaksCore
import SweatStreaksProviderLocalSupport

public struct ClaudeCodeProvider: ActivityProvider {
    public let source: ActivitySource = .claudeCode

    private let claudeDirectory: URL

    public init(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    ) {
        self.claudeDirectory = claudeDirectory
    }

    public func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult {
        let files = Self.activityLogFiles(claudeDirectory: claudeDirectory)
        let activeDays = try LocalActivityLogScanner.scanActivityDays(files: files, range: range)
        let days = LocalActivityLogScanner.dayStatusMap(activeDays: activeDays, range: range)

        return ProviderFetchResult(
            source: .claudeCode,
            days: days,
            fetchedRange: range,
            rateLimitedUntil: nil,
            authError: false,
            warning: files.isEmpty ? "No Claude Code activity logs found." : nil
        )
    }

    public static func activityLogFiles(claudeDirectory: URL) -> [URL] {
        LocalActivityLogScanner.jsonlFiles(
            under: [
                claudeDirectory.appendingPathComponent("history.jsonl", isDirectory: false),
                claudeDirectory.appendingPathComponent("projects", isDirectory: true)
            ]
        )
    }

    public static func evidenceDiagnostic(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    ) -> ProviderEvidenceDiagnostic {
        LocalActivityLogScanner.jsonlEvidenceDiagnostic(
            source: .claudeCode,
            roots: [
                (
                    label: "Claude Code history",
                    evidenceType: "JSONL timestamps",
                    url: claudeDirectory.appendingPathComponent("history.jsonl", isDirectory: false)
                ),
                (
                    label: "Claude Code projects",
                    evidenceType: "JSONL timestamps",
                    url: claudeDirectory.appendingPathComponent("projects", isDirectory: true)
                )
            ]
        )
    }

    public static func hasLocalActivityLogs(claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)) -> Bool {
        !activityLogFiles(claudeDirectory: claudeDirectory).isEmpty
    }
}
