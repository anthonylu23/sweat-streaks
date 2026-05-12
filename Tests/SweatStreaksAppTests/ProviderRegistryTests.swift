import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore
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

    @MainActor
    func testLocalProviderFactoriesUseConfiguredPaths() async throws {
        let root = try makeTemporaryDirectory()
        let codexDirectory = root.appendingPathComponent("custom-codex", isDirectory: true)
        let claudeDirectory = root.appendingPathComponent("custom-claude", isDirectory: true)
        let cursorDirectory = root.appendingPathComponent("custom-cursor", isDirectory: true)
        let cursorApplicationSupportDirectory = root.appendingPathComponent("custom-cursor-support", isDirectory: true)
        let activeDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-12T09:00:00Z"))
        let activeDay = LocalDay.from(date: activeDate, in: .current)

        try writeFile(
            at: codexDirectory.appendingPathComponent("sessions/session.jsonl"),
            contents: #"{"timestamp":"2026-05-12T09:00:00Z"}"#
        )
        try writeFile(
            at: claudeDirectory.appendingPathComponent("history.jsonl"),
            contents: #"{"timestamp":"2026-05-12T09:00:00Z"}"#
        )
        let cursorEvidence = cursorDirectory.appendingPathComponent("projects/demo/worker.log")
        try writeFile(at: cursorEvidence, contents: "metadata only")
        try FileManager.default.setAttributes([.modificationDate: activeDate], ofItemAtPath: cursorEvidence.path)

        let factories = ProviderRegistry.makeProviderFactories(
            githubUsername: "",
            leetCodeUsername: "",
            trackGitHubProvider: false,
            trackLeetCodeProvider: false,
            trackCodexProvider: true,
            trackClaudeCodeProvider: true,
            trackCursorProvider: true,
            localProviderPaths: LocalProviderPathSettings(
                codexPath: codexDirectory.path,
                claudeCodePath: claudeDirectory.path,
                cursorPath: cursorDirectory.path,
                cursorApplicationSupportPath: cursorApplicationSupportDirectory.path
            ),
            secretStore: InMemorySecretStore(),
            githubPATKey: AppModel.githubPATKey
        )

        let range = activeDate...activeDate.addingTimeInterval(1)
        for source in [ActivitySource.codex, .claudeCode, .cursor] {
            let provider = try XCTUnwrap(factories[source]?())
            let result = try await provider.fetchActivityDays(range: range)
            XCTAssertEqual(result.days[activeDay], .active, "\(source.displayName) should use the configured path")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
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
