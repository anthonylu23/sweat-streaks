import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksPersistence

final class ProviderRegistryTests: XCTestCase {
    @MainActor
    func testRemoteTrackingTogglesControlProviderFactories() {
        let factories = ProviderRegistry.makeProviderFactories(
            githubUsername: "octocat",
            leetCodeUsername: "leetcode-user",
            trackGitHubProvider: false,
            trackLeetCodeProvider: true,
            trackCodexProvider: false,
            trackClaudeCodeProvider: false,
            secretStore: InMemorySecretStore(values: [AppModel.githubPATKey: "token"]),
            githubPATKey: AppModel.githubPATKey
        )

        XCTAssertNil(factories[.github])
        XCTAssertNotNil(factories[.leetcode])
        XCTAssertNil(factories[.codex])
        XCTAssertNil(factories[.claudeCode])
    }

    @MainActor
    func testLeetCodeTrackingToggleDisablesConfiguredProvider() {
        let factories = ProviderRegistry.makeProviderFactories(
            githubUsername: "",
            leetCodeUsername: "leetcode-user",
            trackGitHubProvider: true,
            trackLeetCodeProvider: false,
            trackCodexProvider: false,
            trackClaudeCodeProvider: false,
            secretStore: InMemorySecretStore(),
            githubPATKey: AppModel.githubPATKey
        )

        XCTAssertNil(factories[.leetcode])
    }
}

private final class InMemorySecretStore: SecretStore {
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func setSecret(_ value: String, for key: String) throws {
        values[key] = value
    }

    func getSecret(for key: String) throws -> String? {
        values[key]
    }

    func deleteSecret(for key: String) throws {
        values[key] = nil
    }
}
