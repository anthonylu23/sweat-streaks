import Foundation
import SweatStreaksCore
import SweatStreaksProviderLocalSupport

public struct CodexProvider: ActivityProvider {
    public let source: ActivitySource = .codex

    private let codexDirectory: URL

    public init(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    ) {
        self.codexDirectory = codexDirectory
    }

    public func fetchActivityDays(range: ClosedRange<Date>) async throws -> ProviderFetchResult {
        let files = Self.activityLogFiles(codexDirectory: codexDirectory)
        let activeDays = try LocalActivityLogScanner.scanActivityDays(files: files, range: range)
        let days = LocalActivityLogScanner.dayStatusMap(activeDays: activeDays, range: range)

        return ProviderFetchResult(
            source: .codex,
            days: days,
            fetchedRange: range,
            rateLimitedUntil: nil,
            authError: false,
            warning: files.isEmpty ? "No Codex activity logs found." : nil
        )
    }

    public static func activityLogFiles(codexDirectory: URL) -> [URL] {
        LocalActivityLogScanner.jsonlFiles(
            under: [
                codexDirectory.appendingPathComponent("sessions", isDirectory: true),
                codexDirectory.appendingPathComponent("archived_sessions", isDirectory: true)
            ]
        )
    }

    public static func hasLocalActivityLogs(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) -> Bool {
        !activityLogFiles(codexDirectory: codexDirectory).isEmpty
    }
}
