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
            trackCursorProvider: false,
            secretStore: InMemorySecretStore(values: [AppModel.githubPATKey: "token"]),
            githubPATKey: AppModel.githubPATKey
        )

        XCTAssertNil(factories[.github])
        XCTAssertNotNil(factories[.leetcode])
        XCTAssertNil(factories[.codex])
        XCTAssertNil(factories[.claudeCode])
        XCTAssertNil(factories[.cursor])
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
            trackCursorProvider: false,
            secretStore: InMemorySecretStore(),
            githubPATKey: AppModel.githubPATKey
        )

        XCTAssertNil(factories[.leetcode])
    }

    @MainActor
    func testCursorTrackingToggleControlsProviderFactory() {
        let factories = ProviderRegistry.makeProviderFactories(
            githubUsername: "",
            leetCodeUsername: "",
            trackGitHubProvider: false,
            trackLeetCodeProvider: false,
            trackCodexProvider: false,
            trackClaudeCodeProvider: false,
            trackCursorProvider: true,
            secretStore: InMemorySecretStore(),
            githubPATKey: AppModel.githubPATKey
        )

        XCTAssertNotNil(factories[.cursor])
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
