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

    static func makeProviderFactories(
        githubUsername: String,
        leetCodeUsername: String,
        trackGitHubProvider: Bool,
        trackLeetCodeProvider: Bool,
        trackCodexProvider: Bool,
        trackClaudeCodeProvider: Bool,
        trackCursorProvider: Bool,
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
            factories[.codex] = {
                CodexProvider()
            }
        }

        if trackClaudeCodeProvider {
            factories[.claudeCode] = {
                ClaudeCodeProvider()
            }
        }

        if trackCursorProvider {
            factories[.cursor] = {
                CursorProvider()
            }
        }

        return factories
    }

    static func hasLocalData(for source: ActivitySource) -> Bool {
        switch source {
        case .codex:
            return CodexProvider.hasLocalActivityLogs()
        case .claudeCode:
            return ClaudeCodeProvider.hasLocalActivityLogs()
        case .cursor:
            return CursorProvider.hasLocalActivityEvidence()
        case .github, .leetcode, .combined:
            return false
        }
    }
}
