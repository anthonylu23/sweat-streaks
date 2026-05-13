import Foundation
import SwiftUI
import SweatStreaksCore
import SweatStreaksPersistence
import SweatStreaksProviderLocalSupport

struct ActivitySquare: Equatable, Identifiable {
    let source: ActivitySource
    let day: LocalDay
    let status: DayStatus
    let hasOverride: Bool

    var id: String {
        "\(source.rawValue)-\(day.isoDate)"
    }
}

struct ProviderDiagnosticsSnapshot: Equatable, Identifiable {
    let source: ActivitySource
    let isTracked: Bool
    let syncState: ProviderSyncState?
    let recentSyncRuns: [SyncRunRecord]
    let localEvidenceItems: [LocalEvidenceDiagnosticItem]

    var id: ActivitySource { source }

    var totalEvidenceCount: Int {
        localEvidenceItems.reduce(0) { $0 + $1.evidenceCount }
    }

    var latestEvidenceDay: LocalDay? {
        localEvidenceItems.compactMap(\.latestEvidenceDay).max()
    }
}

struct LocalEvidenceDiagnosticItem: Equatable, Identifiable {
    let source: ActivitySource
    let rootLabel: String
    let evidenceType: String
    let rootPath: String
    let rootExists: Bool
    let evidenceCount: Int
    let latestEvidenceDay: LocalDay?

    var id: String {
        "\(source.rawValue)-\(rootLabel)-\(evidenceType)-\(rootPath)"
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let githubPATKey = "github_pat"

    @Published var todayStatuses: [ActivitySource: DayStatus] = [:]
    @Published var metrics: [ActivitySource: StreakMetrics] = [:]
    @Published var lastSyncAt: Date?
    @Published var lastSyncWarning: String?
    @Published var isSyncing = false
    @Published var providerSyncState: [ActivitySource: ProviderSyncState] = [:]
    @Published var authErrorMessage: String?
    @Published var todayOverrides: [ActivitySource: ManualOverride] = [:]
    @Published var contributionSquares: [ActivitySource: [ActivitySquare]] = [:]
    @Published var activitySquares: [ActivitySquare] = []
    @Published var githubContributionDiagnostic: String?
    @Published var providerDiagnostics: [ProviderDiagnosticsSnapshot] = []

    @Published var githubUsername: String = ""
    @Published var leetCodeUsername: String = ""
    @Published var refreshIntervalMinutes: Int = 60
    @Published var notificationsEnabled: Bool = false
    @Published var reminderHour: Int = 20
    @Published var startOnLogin: Bool = false
    @Published var trackGitHubProvider: Bool = true
    @Published var trackLeetCodeProvider: Bool = true
    @Published var trackCodexProvider: Bool = false
    @Published var trackClaudeCodeProvider: Bool = false
    @Published var trackCursorProvider: Bool = false
    @Published var codexPath: String = ProviderRegistry.defaultCodexPath
    @Published var claudeCodePath: String = ProviderRegistry.defaultClaudeCodePath
    @Published var cursorPath: String = ProviderRegistry.defaultCursorPath
    @Published var cursorApplicationSupportPath: String = ProviderRegistry.defaultCursorApplicationSupportPath
    @Published var showGitHubStreakInMenuBar: Bool = true
    @Published var showLeetCodeStreakInMenuBar: Bool = true
    @Published var showCodexStreakInMenuBar: Bool = true
    @Published var showClaudeCodeStreakInMenuBar: Bool = true
    @Published var showCursorStreakInMenuBar: Bool = true
    @Published var showCombinedStreakInMenuBar: Bool = true
    @Published var githubPATInput: String = ""
    @Published var patStatusMessage: String?

    let repository: SweatRepository
    let settingsStore: SQLiteSettingsStore
    let secretStore: SecretStore
    let notificationEngine: NotificationEngine
    let launchAtLoginManager: LaunchAtLoginManaging

    private var refreshLoopTask: Task<Void, Never>?

    init() {
        do {
            let database = try DatabaseManager()
            repository = SweatRepository(dbQueue: database.dbQueue)
            settingsStore = SQLiteSettingsStore(repository: repository)
            secretStore = KeychainSecretStore()
            notificationEngine = NotificationEngine(settingsStore: settingsStore)
            launchAtLoginManager = SystemLaunchAtLoginManager()
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }

        finishInitialization(startBackgroundWork: true)
    }

    init(
        repository: SweatRepository,
        settingsStore: SQLiteSettingsStore,
        secretStore: SecretStore,
        notificationEngine: NotificationEngine,
        launchAtLoginManager: LaunchAtLoginManaging,
        startBackgroundWork: Bool = false
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.notificationEngine = notificationEngine
        self.launchAtLoginManager = launchAtLoginManager

        finishInitialization(startBackgroundWork: startBackgroundWork)
    }

    deinit {
        refreshLoopTask?.cancel()
    }

    var combinedCurrentStreak: Int {
        metrics[.combined]?.current ?? 0
    }

    var isGitHubConnected: Bool {
        trackGitHubProvider && !githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasSavedGitHubPAT
    }

    var isLeetCodeConnected: Bool {
        trackLeetCodeProvider && !leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCodexConnected: Bool {
        trackCodexProvider && ProviderRegistry.hasLocalData(for: .codex, localProviderPaths: localProviderPaths)
    }

    var isClaudeCodeConnected: Bool {
        trackClaudeCodeProvider && ProviderRegistry.hasLocalData(for: .claudeCode, localProviderPaths: localProviderPaths)
    }

    var isCursorConnected: Bool {
        trackCursorProvider && ProviderRegistry.hasLocalData(for: .cursor, localProviderPaths: localProviderPaths)
    }

    var isOnboardingNeeded: Bool {
        let githubBlank = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let leetCodeBlank = leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (!trackGitHubProvider || githubBlank)
            && (!trackLeetCodeProvider || leetCodeBlank)
            && !trackCodexProvider
            && !trackClaudeCodeProvider
            && !trackCursorProvider
    }

    func refreshNow() {
        Task {
            await refreshNow(trigger: .manual)
        }
    }

    func refreshNow(trigger: SyncTrigger) async {
        isSyncing = true
        defer { isSyncing = false }

        authErrorMessage = nil

        let providerFactories = makeProviderFactories()
        guard !providerFactories.isEmpty else {
            authErrorMessage = "Set at least one provider in settings."
            lastSyncWarning = authErrorMessage
            return
        }

        let syncService = DefaultSyncService(
            repository: repository,
            providerFactories: providerFactories,
            combinedRequiredSources: trackedProviderSources
        )
        await syncService.refreshNow(trigger: trigger)

        do {
            providerSyncState = try repository.fetchProviderSyncStates()
        } catch {
            lastSyncWarning = "Failed to load sync state: \(error.localizedDescription)"
        }

        lastSyncWarning = providerSyncState.values.compactMap(\.lastError).first
        for state in providerSyncState.values {
            if let error = state.lastError?.lowercased(), error.contains("auth") {
                authErrorMessage = state.lastError
                break
            }
        }

        refreshViewStateFromStorage()
        refreshDiagnosticsFromStorage()
    }

    func setTodayOverride(source: ActivitySource, status: OverrideStatus) {
        guard ActivitySource.currentProviderSources.contains(source) else { return }

        let today = LocalDay.from(date: Date(), in: .current)
        do {
            try repository.setManualStatus(
                day: today,
                source: source,
                status: status,
                note: "Set from menu bar"
            )
            refreshViewStateFromStorage()
        } catch {
            lastSyncWarning = "Failed to save override: \(error.localizedDescription)"
        }
    }

    func clearTodayOverride(source: ActivitySource) {
        guard ActivitySource.currentProviderSources.contains(source) else { return }

        let today = LocalDay.from(date: Date(), in: .current)
        do {
            try repository.clearManualStatus(day: today, source: source)
            refreshViewStateFromStorage()
        } catch {
            lastSyncWarning = "Failed to clear override: \(error.localizedDescription)"
        }
    }

    func saveSettings() {
        do {
            enforceMenuBarVisibilityForTrackedProviders()
            try settingsStore.set(githubUsername, for: .githubUsername)
            try settingsStore.set(leetCodeUsername, for: .leetCodeUsername)
            try settingsStore.set(String(refreshIntervalMinutes), for: .refreshIntervalMinutes)
            try settingsStore.set(notificationsEnabled ? "true" : "false", for: .notificationsEnabled)
            try settingsStore.set(String(reminderHour), for: .reminderHour)
            try launchAtLoginManager.setEnabled(startOnLogin)
            try settingsStore.set(startOnLogin ? "true" : "false", for: .startOnLogin)
            try settingsStore.set(trackGitHubProvider ? "true" : "false", for: .trackGitHubProvider)
            try settingsStore.set(trackLeetCodeProvider ? "true" : "false", for: .trackLeetCodeProvider)
            try settingsStore.set(trackCodexProvider ? "true" : "false", for: .trackCodexProvider)
            try settingsStore.set(trackClaudeCodeProvider ? "true" : "false", for: .trackClaudeCodeProvider)
            try settingsStore.set(trackCursorProvider ? "true" : "false", for: .trackCursorProvider)
            normalizeLocalProviderPathFields()
            try settingsStore.set(codexPath, for: .codexPath)
            try settingsStore.set(claudeCodePath, for: .claudeCodePath)
            try settingsStore.set(cursorPath, for: .cursorPath)
            try settingsStore.set(cursorApplicationSupportPath, for: .cursorApplicationSupportPath)
            try settingsStore.set(showGitHubStreakInMenuBar ? "true" : "false", for: .showGitHubStreakInMenuBar)
            try settingsStore.set(showLeetCodeStreakInMenuBar ? "true" : "false", for: .showLeetCodeStreakInMenuBar)
            try settingsStore.set(showCodexStreakInMenuBar ? "true" : "false", for: .showCodexStreakInMenuBar)
            try settingsStore.set(showClaudeCodeStreakInMenuBar ? "true" : "false", for: .showClaudeCodeStreakInMenuBar)
            try settingsStore.set(showCursorStreakInMenuBar ? "true" : "false", for: .showCursorStreakInMenuBar)
            try settingsStore.set(showCombinedStreakInMenuBar ? "true" : "false", for: .showCombinedStreakInMenuBar)

            let pat = githubPATInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pat.isEmpty {
                try secretStore.setSecret(pat, for: Self.githubPATKey)
                patStatusMessage = "GitHub PAT saved in Keychain."
                githubPATInput = ""
            } else if hasSavedGitHubPAT {
                patStatusMessage = "Existing GitHub PAT kept in Keychain."
            } else {
                patStatusMessage = "GitHub PAT not set."
            }
            refreshViewStateFromStorage()
            refreshDiagnosticsFromStorage()
            startRefreshLoop()
        } catch {
            lastSyncWarning = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func clearGitHubPAT() {
        do {
            try secretStore.deleteSecret(for: Self.githubPATKey)
            githubPATInput = ""
            patStatusMessage = "GitHub PAT cleared from Keychain."
        } catch {
            lastSyncWarning = "Failed to clear GitHub PAT: \(error.localizedDescription)"
        }
    }

    private func loadSettings() {
        do {
            githubUsername = try settingsStore.get(.githubUsername) ?? ""
            leetCodeUsername = try settingsStore.get(.leetCodeUsername) ?? ""

            if let intervalString = try settingsStore.get(.refreshIntervalMinutes),
               let interval = Int(intervalString),
               interval > 0 {
                refreshIntervalMinutes = interval
            } else {
                refreshIntervalMinutes = 60
                try settingsStore.set("60", for: .refreshIntervalMinutes)
            }

            notificationsEnabled = try settingsStore.get(.notificationsEnabled) == "true"
            if let reminderHourString = try settingsStore.get(.reminderHour),
               let storedReminderHour = Int(reminderHourString),
               (0...23).contains(storedReminderHour) {
                reminderHour = storedReminderHour
            } else {
                reminderHour = 20
                try settingsStore.set("20", for: .reminderHour)
            }

            startOnLogin = try boolSetting(.startOnLogin, default: launchAtLoginManager.isEnabled)
            showGitHubStreakInMenuBar = try boolSetting(.showGitHubStreakInMenuBar, default: true)
            showLeetCodeStreakInMenuBar = try boolSetting(.showLeetCodeStreakInMenuBar, default: true)
            codexPath = try pathSetting(.codexPath, default: ProviderRegistry.defaultCodexPath)
            claudeCodePath = try pathSetting(.claudeCodePath, default: ProviderRegistry.defaultClaudeCodePath)
            cursorPath = try pathSetting(.cursorPath, default: ProviderRegistry.defaultCursorPath)
            cursorApplicationSupportPath = try pathSetting(
                .cursorApplicationSupportPath,
                default: ProviderRegistry.defaultCursorApplicationSupportPath
            )
            trackGitHubProvider = try boolSetting(.trackGitHubProvider, default: true)
            trackLeetCodeProvider = try boolSetting(.trackLeetCodeProvider, default: true)
            trackCodexProvider = try boolSetting(
                .trackCodexProvider,
                default: ProviderRegistry.hasLocalData(for: .codex, localProviderPaths: localProviderPaths)
            )
            trackClaudeCodeProvider = try boolSetting(
                .trackClaudeCodeProvider,
                default: ProviderRegistry.hasLocalData(for: .claudeCode, localProviderPaths: localProviderPaths)
            )
            trackCursorProvider = try boolSetting(
                .trackCursorProvider,
                default: ProviderRegistry.hasLocalData(for: .cursor, localProviderPaths: localProviderPaths)
            )
            showCodexStreakInMenuBar = try boolSetting(.showCodexStreakInMenuBar, default: true)
            showClaudeCodeStreakInMenuBar = try boolSetting(.showClaudeCodeStreakInMenuBar, default: true)
            showCursorStreakInMenuBar = try boolSetting(.showCursorStreakInMenuBar, default: true)
            showCombinedStreakInMenuBar = try boolSetting(.showCombinedStreakInMenuBar, default: true)
            enforceMenuBarVisibilityForTrackedProviders()

            githubPATInput = ""
            patStatusMessage = hasSavedGitHubPAT ? "GitHub PAT saved in Keychain." : "GitHub PAT not set."
            providerSyncState = try repository.fetchProviderSyncStates()
        } catch {
            lastSyncWarning = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    func refreshDiagnostics() {
        refreshDiagnosticsFromStorage()
    }

    private func boolSetting(_ key: SettingsKey, default defaultValue: Bool) throws -> Bool {
        guard let rawValue = try settingsStore.get(key) else {
            try settingsStore.set(defaultValue ? "true" : "false", for: key)
            return defaultValue
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            try settingsStore.set(defaultValue ? "true" : "false", for: key)
            return defaultValue
        }
    }

    private func pathSetting(_ key: SettingsKey, default defaultValue: String) throws -> String {
        guard let rawValue = try settingsStore.get(key) else {
            try settingsStore.set(defaultValue, for: key)
            return defaultValue
        }

        let normalizedValue = LocalProviderPathSettings.normalizedPath(rawValue, defaultPath: defaultValue)
        if normalizedValue != rawValue {
            try settingsStore.set(normalizedValue, for: key)
        }
        return normalizedValue
    }

    private func finishInitialization(startBackgroundWork: Bool) {
        loadSettings()
        refreshViewStateFromStorage()

        guard startBackgroundWork else { return }

        startRefreshLoop()

        if hasAnyProviderConfiguration {
            Task { await refreshNow(trigger: .launch) }
        }
    }

    private func refreshViewStateFromStorage() {
        let today = LocalDay.from(date: Date(), in: .current)
        guard let fromDate = Calendar.current.date(byAdding: .day, value: -364, to: Date()) else {
            return
        }
        let from = LocalDay.from(date: fromDate, in: .current)

        do {
            try repository.deleteActivityDays(after: today)

            var providerDays: [ActivitySource: [LocalDay: DayStatus]] = [:]
            for source in ActivitySource.currentProviderSources {
                providerDays[source] = try repository.fetchActivityDays(source: source, from: from, to: today)
            }
            let overrides = try repository.fetchManualOverrides(from: from, to: today)
            todayOverrides = overrides[today] ?? [:]

            if providerDays.values.allSatisfy(\.isEmpty) {
                githubContributionDiagnostic = nil
                providerDays = AppModel.emptyDayMap(in: .current)
                let effectiveDays = effectiveDayMaps(
                    providerDays: providerDays,
                    overrides: overrides,
                    from: from,
                    to: today
                )

                todayStatuses = todayStatuses(from: effectiveDays, today: today)

                metrics = Self.makeMetrics(
                    effectiveDays: effectiveDays,
                    today: today,
                    todayStatuses: todayStatuses,
                    todayOverrides: todayOverrides
                )

                updateSquareTimelines(
                    effectiveDays: effectiveDays,
                    overrides: overrides,
                    from: from,
                    to: today
                )

                if lastSyncAt == nil {
                    lastSyncWarning = "No provider activity data yet. Configure a provider or refresh sync."
                }

                return
            }

            let effectiveDays = effectiveDayMaps(
                providerDays: providerDays,
                overrides: overrides,
                from: from,
                to: today
            )

            todayStatuses = todayStatuses(from: effectiveDays, today: today)
            githubContributionDiagnostic = Self.githubContributionDiagnostic(from: providerDays[.github] ?? [:])

            metrics = Self.makeMetrics(
                effectiveDays: effectiveDays,
                today: today,
                todayStatuses: todayStatuses,
                todayOverrides: todayOverrides
            )

            updateSquareTimelines(
                effectiveDays: effectiveDays,
                overrides: overrides,
                from: from,
                to: today
            )

            updateLastSyncAt()
            evaluateNotifications(today: today)
        } catch {
            lastSyncWarning = "Failed to load activity from storage: \(error.localizedDescription)"
        }
    }

    private func effectiveDayMaps(
        providerDays: [ActivitySource: [LocalDay: DayStatus]],
        overrides: [LocalDay: [ActivitySource: ManualOverride]],
        from: LocalDay,
        to: LocalDay
    ) -> [ActivitySource: [LocalDay: DayStatus]] {
        var effectiveProviderDays = Dictionary(
            uniqueKeysWithValues: ActivitySource.currentProviderSources.map { ($0, [LocalDay: DayStatus]()) }
        )
        var combinedDays: [LocalDay: DayStatus] = [:]

        for day in days(from: from, to: to) {
            let sourceStatuses = Dictionary(
                uniqueKeysWithValues: ActivitySource.currentProviderSources.map { source in
                    (source, providerDays[source]?[day] ?? .unknown)
                }
            )
            let overrideStatuses = overrides[day]?.mapValues(\.status) ?? [:]
            let effective = StreakEngine.applyOverrides(sourceStatuses: sourceStatuses, overrides: overrideStatuses)

            for source in ActivitySource.currentProviderSources {
                effectiveProviderDays[source]?[day] = effective[source] ?? .unknown
            }
            combinedDays[day] = CombinedStatusResolver.derive(
                effectiveStatuses: effective,
                requiredSources: trackedProviderSources
            )
        }

        effectiveProviderDays[.combined] = combinedDays
        return effectiveProviderDays
    }

    nonisolated static func makeMetrics(
        effectiveDays: [ActivitySource: [LocalDay: DayStatus]],
        today: LocalDay,
        todayStatuses: [ActivitySource: DayStatus],
        todayOverrides: [ActivitySource: ManualOverride]
    ) -> [ActivitySource: StreakMetrics] {
        Dictionary(
            uniqueKeysWithValues: (ActivitySource.currentProviderSources + [.combined]).map { source in
                (
                    source,
                    StreakEngine.computeMetrics(
                        source: source,
                        days: effectiveDays[source] ?? [:],
                        asOf: today,
                        currentStreakAsOf: CurrentStreakAnchorPolicy.anchorDay(
                            for: source,
                            today: today,
                            todayStatuses: todayStatuses,
                            todayOverrides: todayOverrides
                        )
                    )
                )
            }
        )
    }

    private func todayStatuses(
        from effectiveDays: [ActivitySource: [LocalDay: DayStatus]],
        today: LocalDay
    ) -> [ActivitySource: DayStatus] {
        Dictionary(
            uniqueKeysWithValues: (ActivitySource.currentProviderSources + [.combined]).map { source in
                (source, effectiveDays[source]?[today] ?? .unknown)
            }
        )
    }

    nonisolated static func githubContributionDiagnostic(from githubDays: [LocalDay: DayStatus]) -> String? {
        guard let latestDay = githubDays.keys.max(),
              let latestStatus = githubDays[latestDay] else {
            return nil
        }

        return "GitHub contribution calendar: \(latestDay.isoDate) \(latestStatus.rawValue). Commits only count when GitHub counts them as contributions."
    }

    private func updateSquareTimelines(
        effectiveDays: [ActivitySource: [LocalDay: DayStatus]],
        overrides: [LocalDay: [ActivitySource: ManualOverride]],
        from: LocalDay,
        to: LocalDay
    ) {
        contributionSquares = Dictionary(
            uniqueKeysWithValues: ActivitySource.currentProviderSources.map { source in
                (source, makeSquares(source: source, days: effectiveDays[source] ?? [:], overrides: overrides, from: from, to: to))
            }
        )
        activitySquares = makeSquares(source: .combined, days: effectiveDays[.combined] ?? [:], overrides: overrides, from: from, to: to)
    }

    private func makeSquares(
        source: ActivitySource,
        days dayStatuses: [LocalDay: DayStatus],
        overrides: [LocalDay: [ActivitySource: ManualOverride]],
        from: LocalDay,
        to: LocalDay
    ) -> [ActivitySquare] {
        days(from: from, to: to).map { day in
            ActivitySquare(
                source: source,
                day: day,
                status: dayStatuses[day] ?? .unknown,
                hasOverride: source == .combined ? overrides[day]?.isEmpty == false : overrides[day]?[source] != nil
            )
        }
    }

    private func days(from start: LocalDay, to end: LocalDay) -> [LocalDay] {
        guard let startDate = start.date(in: .current),
              let endDate = end.date(in: .current) else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var cursorDate = startDate
        var days: [LocalDay] = []

        while cursorDate <= endDate {
            days.append(LocalDay.from(date: cursorDate, in: .current))
            cursorDate = calendar.date(byAdding: .day, value: 1, to: cursorDate) ?? endDate.addingTimeInterval(1)
        }

        return days
    }

    private var hasAnyProviderConfiguration: Bool {
        let githubConfigured = !githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasSavedGitHubPAT
            && trackGitHubProvider
        let leetCodeConfigured = !leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && trackLeetCodeProvider
        return githubConfigured || leetCodeConfigured || trackCodexProvider || trackClaudeCodeProvider || trackCursorProvider
    }

    var trackedProviderSources: [ActivitySource] {
        [
            (ActivitySource.github, trackGitHubProvider),
            (.leetcode, trackLeetCodeProvider),
            (.codex, trackCodexProvider),
            (.claudeCode, trackClaudeCodeProvider),
            (.cursor, trackCursorProvider)
        ].compactMap { source, isTracked in
            isTracked ? source : nil
        }
    }

    private var hasSavedGitHubPAT: Bool {
        do {
            let token = try secretStore.getSecret(for: Self.githubPATKey)
            return token?.isEmpty == false
        } catch {
            return false
        }
    }

    private func makeProviderFactories() -> [ActivitySource: DefaultSyncService.ProviderFactory] {
        ProviderRegistry.makeProviderFactories(
            githubUsername: githubUsername,
            leetCodeUsername: leetCodeUsername,
            trackGitHubProvider: trackGitHubProvider,
            trackLeetCodeProvider: trackLeetCodeProvider,
            trackCodexProvider: trackCodexProvider,
            trackClaudeCodeProvider: trackClaudeCodeProvider,
            trackCursorProvider: trackCursorProvider,
            localProviderPaths: localProviderPaths,
            secretStore: secretStore,
            githubPATKey: Self.githubPATKey
        )
    }

    func enforceMenuBarVisibilityForTrackedProviders() {
        if !trackGitHubProvider {
            showGitHubStreakInMenuBar = false
        }
        if !trackLeetCodeProvider {
            showLeetCodeStreakInMenuBar = false
        }
        if !trackCodexProvider {
            showCodexStreakInMenuBar = false
        }
        if !trackClaudeCodeProvider {
            showClaudeCodeStreakInMenuBar = false
        }
        if !trackCursorProvider {
            showCursorStreakInMenuBar = false
        }
    }

    private func startRefreshLoop() {
        refreshLoopTask?.cancel()
        let intervalMinutes = max(refreshIntervalMinutes, 1)

        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = UInt64(intervalMinutes * 60)
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.refreshNow(trigger: .timer)
            }
        }
    }

    private var localProviderPaths: LocalProviderPathSettings {
        LocalProviderPathSettings(
            codexPath: codexPath,
            claudeCodePath: claudeCodePath,
            cursorPath: cursorPath,
            cursorApplicationSupportPath: cursorApplicationSupportPath
        )
    }

    private func normalizeLocalProviderPathFields() {
        codexPath = LocalProviderPathSettings.normalizedPath(
            codexPath,
            defaultPath: ProviderRegistry.defaultCodexPath
        )
        claudeCodePath = LocalProviderPathSettings.normalizedPath(
            claudeCodePath,
            defaultPath: ProviderRegistry.defaultClaudeCodePath
        )
        cursorPath = LocalProviderPathSettings.normalizedPath(
            cursorPath,
            defaultPath: ProviderRegistry.defaultCursorPath
        )
        cursorApplicationSupportPath = LocalProviderPathSettings.normalizedPath(
            cursorApplicationSupportPath,
            defaultPath: ProviderRegistry.defaultCursorApplicationSupportPath
        )
    }

    private func updateLastSyncAt() {
        let lastSuccesses = providerSyncState.values.compactMap(\.lastSuccessAt)
        lastSyncAt = lastSuccesses.max()
    }

    private func refreshDiagnosticsFromStorage() {
        let localDiagnostics = ProviderRegistry.localEvidenceDiagnostics(
            for: trackedProviderSources,
            localProviderPaths: localProviderPaths
        )

        do {
            providerDiagnostics = try ActivitySource.currentProviderSources.map { source in
                let localEvidenceItems = (localDiagnostics[source]?.items ?? []).map { item in
                    LocalEvidenceDiagnosticItem(
                        source: source,
                        rootLabel: item.rootLabel,
                        evidenceType: item.evidenceType,
                        rootPath: item.rootPath,
                        rootExists: item.rootExists,
                        evidenceCount: item.evidenceCount,
                        latestEvidenceDay: item.latestEvidenceDay
                    )
                }

                return ProviderDiagnosticsSnapshot(
                    source: source,
                    isTracked: trackedProviderSources.contains(source),
                    syncState: providerSyncState[source],
                    recentSyncRuns: try repository.fetchRecentSyncRuns(provider: source.rawValue, limit: 5),
                    localEvidenceItems: localEvidenceItems
                )
            }
        } catch {
            lastSyncWarning = "Failed to load diagnostics: \(error.localizedDescription)"
        }
    }

    private func evaluateNotifications(today: LocalDay) {
        let combinedStatus = todayStatuses[.combined] ?? .unknown
        Task {
            await notificationEngine.evaluate(
                today: today,
                combinedStatus: combinedStatus,
                reminderHour: reminderHour,
                notificationsEnabled: notificationsEnabled
            )
        }
    }

    private static func emptyDayMap(in timeZone: TimeZone) -> [ActivitySource: [LocalDay: DayStatus]] {
        var providerDays = Dictionary(
            uniqueKeysWithValues: ActivitySource.currentProviderSources.map { ($0, [LocalDay: DayStatus]()) }
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let day = LocalDay.from(date: date, in: timeZone)

            for source in ActivitySource.currentProviderSources {
                providerDays[source]?[day] = .unknown
            }
        }

        return providerDays
    }
}
