import Foundation
import SweatStreaksCore
import SweatStreaksPersistence
import SweatStreaksProviderGitHub
import SweatStreaksProviderLeetCode

@MainActor
enum ProviderRegistry {
    static let currentProviderSources = ActivitySource.currentProviderSources
    static let combinedRequiredSources = ActivitySource.combinedRequiredSources

    static func makeProviderFactories(
        githubUsername: String,
        leetCodeUsername: String,
        secretStore: SecretStore,
        githubPATKey: String
    ) -> [ActivitySource: DefaultSyncService.ProviderFactory] {
        var factories: [ActivitySource: DefaultSyncService.ProviderFactory] = [:]

        let githubUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !githubUsername.isEmpty {
            factories[.github] = { [secretStore] in
                let token = try secretStore.getSecret(for: githubPATKey) ?? ""
                guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ProviderError.auth
                }
                return GitHubProvider(username: githubUsername, token: token)
            }
        }

        let leetCodeUsername = leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leetCodeUsername.isEmpty {
            factories[.leetcode] = {
                LeetCodeProvider(username: leetCodeUsername)
            }
        }

        return factories
    }
}
