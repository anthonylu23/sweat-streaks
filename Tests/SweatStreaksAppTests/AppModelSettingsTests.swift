import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore
@testable import SweatStreaksPersistence

@MainActor
final class AppModelSettingsTests: XCTestCase {
    func testSavingStartOnLoginRegistersLoginItem() throws {
        let fixture = try makeFixture(launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: false))
        fixture.model.startOnLogin = true

        fixture.model.saveSettings()

        XCTAssertEqual(fixture.launchAtLoginManager.enabledRequests, [true])
        XCTAssertEqual(try fixture.settingsStore.get(.startOnLogin), "true")
    }

    func testSavingStartOnLoginDisabledUnregistersLoginItem() throws {
        let fixture = try makeFixture(launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: true))
        fixture.model.startOnLogin = false

        fixture.model.saveSettings()

        XCTAssertEqual(fixture.launchAtLoginManager.enabledRequests, [false])
        XCTAssertEqual(try fixture.settingsStore.get(.startOnLogin), "false")
    }

    func testLaunchAtLoginFailureSurfacesAsSettingsWarning() throws {
        let fixture = try makeFixture(
            launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: false, error: LaunchAtLoginTestError.expected)
        )
        fixture.model.startOnLogin = true

        fixture.model.saveSettings()

        XCTAssertEqual(fixture.launchAtLoginManager.enabledRequests, [true])
        XCTAssertTrue(fixture.model.lastSyncWarning?.contains("Failed to save settings") == true)
        XCTAssertTrue(fixture.model.lastSyncWarning?.contains("expected") == true)
    }

    func testSavingLocalProviderPathsPersistsConfiguredValues() throws {
        let fixture = try makeFixture(launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: false))
        fixture.model.codexPath = "/tmp/sweat-codex"
        fixture.model.claudeCodePath = "/tmp/sweat-claude"
        fixture.model.cursorPath = "/tmp/sweat-cursor"
        fixture.model.cursorApplicationSupportPath = "/tmp/sweat-cursor-support"

        fixture.model.saveSettings()

        XCTAssertEqual(try fixture.settingsStore.get(.codexPath), "/tmp/sweat-codex")
        XCTAssertEqual(try fixture.settingsStore.get(.claudeCodePath), "/tmp/sweat-claude")
        XCTAssertEqual(try fixture.settingsStore.get(.cursorPath), "/tmp/sweat-cursor")
        XCTAssertEqual(try fixture.settingsStore.get(.cursorApplicationSupportPath), "/tmp/sweat-cursor-support")
    }

    func testBlankLocalProviderPathsResetToDocumentedDefaults() throws {
        let fixture = try makeFixture(launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: false))
        fixture.model.codexPath = "  "
        fixture.model.claudeCodePath = ""
        fixture.model.cursorPath = "\n"
        fixture.model.cursorApplicationSupportPath = "\t"

        fixture.model.saveSettings()

        XCTAssertEqual(fixture.model.codexPath, ProviderRegistry.defaultCodexPath)
        XCTAssertEqual(fixture.model.claudeCodePath, ProviderRegistry.defaultClaudeCodePath)
        XCTAssertEqual(fixture.model.cursorPath, ProviderRegistry.defaultCursorPath)
        XCTAssertEqual(fixture.model.cursorApplicationSupportPath, ProviderRegistry.defaultCursorApplicationSupportPath)
    }

    func testEmptyStorageStartsWithUnknownActivityInsteadOfSampleData() throws {
        let fixture = try makeFixture(launchAtLoginManager: RecordingLaunchAtLoginManager(isEnabled: false))

        XCTAssertEqual(fixture.model.todayStatuses[.github], .unknown)
        XCTAssertEqual(fixture.model.todayStatuses[.leetcode], .unknown)
        XCTAssertEqual(fixture.model.todayStatuses[.codex], .unknown)
        XCTAssertEqual(fixture.model.todayStatuses[.claudeCode], .unknown)
        XCTAssertEqual(fixture.model.todayStatuses[.cursor], .unknown)
        XCTAssertEqual(fixture.model.todayStatuses[.combined], .unknown)
        XCTAssertEqual(fixture.model.combinedCurrentStreak, 0)
        XCTAssertEqual(fixture.model.lastSyncWarning, "No provider activity data yet. Configure a provider or refresh sync.")
    }

    private func makeFixture(
        launchAtLoginManager: RecordingLaunchAtLoginManager
    ) throws -> (
        model: AppModel,
        settingsStore: SQLiteSettingsStore,
        launchAtLoginManager: RecordingLaunchAtLoginManager
    ) {
        let database = try DatabaseManager(inMemory: true)
        let repository = SweatRepository(dbQueue: database.dbQueue)
        let settingsStore = SQLiteSettingsStore(repository: repository)
        let model = AppModel(
            repository: repository,
            settingsStore: settingsStore,
            secretStore: InMemorySecretStore(),
            notificationEngine: NotificationEngine(settingsStore: settingsStore),
            launchAtLoginManager: launchAtLoginManager
        )
        return (model, settingsStore, launchAtLoginManager)
    }
}

private final class RecordingLaunchAtLoginManager: LaunchAtLoginManaging {
    let isEnabled: Bool
    let error: Error?
    private(set) var enabledRequests: [Bool] = []

    init(isEnabled: Bool, error: Error? = nil) {
        self.isEnabled = isEnabled
        self.error = error
    }

    func setEnabled(_ isEnabled: Bool) throws {
        enabledRequests.append(isEnabled)
        if let error {
            throw error
        }
    }
}

private enum LaunchAtLoginTestError: LocalizedError {
    case expected

    var errorDescription: String? {
        "expected launch-at-login failure"
    }
}

private final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]

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
