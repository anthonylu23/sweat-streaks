import Foundation
import SweatStreaksCore
import SweatStreaksPersistence
import SweatStreaksProviderClaudeCode
import SweatStreaksProviderCodex
import SweatStreaksProviderCursor
import SweatStreaksProviderGitHub
import SweatStreaksProviderLeetCode

@MainActor
enum ProviderRegistry {
    static let currentProviderSources = ActivitySource.currentProviderSources
    static let combinedRequiredSources = ActivitySource.combinedRequiredSources
    static let defaultCodexPath = LocalProviderPathSettings.defaultCodexPath
    static let defaultClaudeCodePath = LocalProviderPathSettings.defaultClaudeCodePath
    static let defaultCursorPath = LocalProviderPathSettings.defaultCursorPath
    static let defaultCursorApplicationSupportPath = LocalProviderPathSettings.defaultCursorApplicationSupportPath

    static func makeProviderFactories(
        githubUsername: String,
        leetCodeUsername: String,
        trackGitHubProvider: Bool,
        trackLeetCodeProvider: Bool,
        trackCodexProvider: Bool,
        trackClaudeCodeProvider: Bool,
        trackCursorProvider: Bool,
        localProviderPaths: LocalProviderPathSettings = .defaults,
        secretStore: SecretStore,
        githubPATKey: String
    ) -> [ActivitySource: DefaultSyncService.ProviderFactory] {
        var factories: [ActivitySource: DefaultSyncService.ProviderFactory] = [:]

        let githubUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if trackGitHubProvider && !githubUsername.isEmpty {
            factories[.github] = { [secretStore] in
                let token = try secretStore.getSecret(for: githubPATKey) ?? ""
                guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderError.auth
                }
                return GitHubProvider(username: githubUsername, token: token)
            }
        }

        let leetCodeUsername = leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if trackLeetCodeProvider && !leetCodeUsername.isEmpty {
            factories[.leetcode] = {
                LeetCodeProvider(username: leetCodeUsername)
            }
        }

        if trackCodexProvider {
            let codexDirectory = localProviderPaths.codexDirectory
            factories[.codex] = {
                CodexProvider(codexDirectory: codexDirectory)
            }
        }

        if trackClaudeCodeProvider {
            let claudeDirectory = localProviderPaths.claudeCodeDirectory
            factories[.claudeCode] = {
                ClaudeCodeProvider(claudeDirectory: claudeDirectory)
            }
        }

        if trackCursorProvider {
            let cursorDirectory = localProviderPaths.cursorDirectory
            let applicationSupportDirectory = localProviderPaths.cursorApplicationSupportDirectory
            factories[.cursor] = {
                CursorProvider(
                    cursorDirectory: cursorDirectory,
                    applicationSupportDirectory: applicationSupportDirectory
                )
            }
        }

        return factories
    }

    static func hasLocalData(for source: ActivitySource, localProviderPaths: LocalProviderPathSettings = .defaults) -> Bool {
        switch source {
        case .codex:
            return CodexProvider.hasLocalActivityLogs(codexDirectory: localProviderPaths.codexDirectory)
        case .claudeCode:
            return ClaudeCodeProvider.hasLocalActivityLogs(claudeDirectory: localProviderPaths.claudeCodeDirectory)
        case .cursor:
            return CursorProvider.hasLocalActivityEvidence(
                cursorDirectory: localProviderPaths.cursorDirectory,
                applicationSupportDirectory: localProviderPaths.cursorApplicationSupportDirectory
            )
        case .github, .leetcode, .combined:
            return false
        }
    }
}

struct LocalProviderPathSettings: Equatable {
    static let defaultCodexPath = "~/.codex"
    static let defaultClaudeCodePath = "~/.claude"
    static let defaultCursorPath = "~/.cursor"
    static let defaultCursorApplicationSupportPath = "~/Library/Application Support/Cursor"

    var codexPath: String
    var claudeCodePath: String
    var cursorPath: String
    var cursorApplicationSupportPath: String

    static let defaults = LocalProviderPathSettings(
        codexPath: Self.defaultCodexPath,
        claudeCodePath: Self.defaultClaudeCodePath,
        cursorPath: Self.defaultCursorPath,
        cursorApplicationSupportPath: Self.defaultCursorApplicationSupportPath
    )

    var codexDirectory: URL {
        Self.directoryURL(path: codexPath, defaultPath: Self.defaultCodexPath)
    }

    var claudeCodeDirectory: URL {
        Self.directoryURL(path: claudeCodePath, defaultPath: Self.defaultClaudeCodePath)
    }

    var cursorDirectory: URL {
        Self.directoryURL(path: cursorPath, defaultPath: Self.defaultCursorPath)
    }

    var cursorApplicationSupportDirectory: URL {
        Self.directoryURL(
            path: cursorApplicationSupportPath,
            defaultPath: Self.defaultCursorApplicationSupportPath
        )
    }

    private static func directoryURL(path: String, defaultPath: String) -> URL {
        let trimmedPath = normalizedPath(path, defaultPath: defaultPath)
        return URL(fileURLWithPath: (trimmedPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func normalizedPath(_ path: String, defaultPath: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? defaultPath : trimmedPath
    }
}
