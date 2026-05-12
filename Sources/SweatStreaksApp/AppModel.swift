import Foundation
import SwiftUI
import SweatStreaksCore
import SweatStreaksPersistence

struct ActivitySquare: Equatable, Identifiable {
    let source: ActivitySource
    let day: LocalDay
    let status: DayStatus
    let hasOverride: Bool

    var id: String {
        "\(source.rawValue)-\(day.isoDate)"
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

    @Published var githubUsername: String = ""
    @Published var leetCodeUsername: String = ""
    @Published var refreshIntervalMinutes: Int = 60
    @Published var notificationsEnabled: Bool = false
    @Published var reminderHour: Int = 20
    @Published var showGitHubStreakInMenuBar: Bool = true
    @Published var showLeetCodeStreakInMenuBar: Bool = true
    @Published var showCombinedStreakInMenuBar: Bool = true
    @Published var githubPATInput: String = ""
    @Published var patStatusMessage: String?

    let repository: SweatRepository
    let settingsStore: SQLiteSettingsStore
    let secretStore: SecretStore
    let notificationEngine: NotificationEngine

    private var refreshLoopTask: Task<Void, Never>?
    init() {
        do {
            let database = try DatabaseManager()
            repository = SweatRepository(dbQueue: database.dbQueue)
            settingsStore = SQLiteSettingsStore(repository: repository)
            secretStore = KeychainSecretStore()
            notificationEngine = NotificationEngine(settingsStore: settingsStore)
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }

        loadSettings()
        refreshViewStateFromStorage()
        startRefreshLoop()

        if hasAnyProviderConfiguration {
            Task { await refreshNow(trigger: .launch) }
        }
    }

    deinit {
        refreshLoopTask?.cancel()
    }

    var combinedCurrentStreak: Int {
        metrics[.combined]?.current ?? 0
    }

    var isGitHubConnected: Bool {
        !githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasSavedGitHubPAT
    }

    var isLeetCodeConnected: Bool {
        !leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isOnboardingNeeded: Bool {
        let githubBlank = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let leetCodeBlank = leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return githubBlank && leetCodeBlank
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

        let syncService = DefaultSyncService(repository: repository, providerFactories: providerFactories)
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
    }

    func setTodayOverride(source: ActivitySource, status: OverrideStatus) {
        guard source == .github || source == .leetcode else { return }

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
        guard source == .github || source == .leetcode else { return }

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
            try settingsStore.set(githubUsername, for: .githubUsername)
            try settingsStore.set(leetCodeUsername, for: .leetCodeUsername)
            try settingsStore.set(String(refreshIntervalMinutes), for: .refreshIntervalMinutes)
            try settingsStore.set(notificationsEnabled ? "true" : "false", for: .notificationsEnabled)
            try settingsStore.set(String(reminderHour), for: .reminderHour)
            try settingsStore.set(showGitHubStreakInMenuBar ? "true" : "false", for: .showGitHubStreakInMenuBar)
            try settingsStore.set(showLeetCodeStreakInMenuBar ? "true" : "false", for: .showLeetCodeStreakInMenuBar)
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

            showGitHubStreakInMenuBar = try boolSetting(.showGitHubStreakInMenuBar, default: true)
            showLeetCodeStreakInMenuBar = try boolSetting(.showLeetCodeStreakInMenuBar, default: true)
            showCombinedStreakInMenuBar = try boolSetting(.showCombinedStreakInMenuBar, default: true)

            githubPATInput = ""
            patStatusMessage = hasSavedGitHubPAT ? "GitHub PAT saved in Keychain." : "GitHub PAT not set."
            providerSyncState = try repository.fetchProviderSyncStates()
        } catch {
            lastSyncWarning = "Failed to load settings: \(error.localizedDescription)"
        }
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

    private func refreshViewStateFromStorage() {
        let today = LocalDay.from(date: Date(), in: .current)
        guard let fromDate = Calendar.current.date(byAdding: .day, value: -364, to: Date()) else {
            return
        }
        let from = LocalDay.from(date: fromDate, in: .current)

        do {
            try repository.deleteActivityDays(after: today)

            let githubDays = try repository.fetchActivityDays(source: .github, from: from, to: today)
            let leetCodeDays = try repository.fetchActivityDays(source: .leetcode, from: from, to: today)
            let overrides = try repository.fetchManualOverrides(from: from, to: today)
            todayOverrides = overrides[today] ?? [:]

            if githubDays.isEmpty && leetCodeDays.isEmpty {
                githubContributionDiagnostic = nil
                let seed = AppModel.seedDayMap(in: .current)
                let effectiveDays = effectiveDayMaps(
                    githubDays: seed.github,
                    leetCodeDays: seed.leetcode,
                    overrides: overrides,
                    from: from,
                    to: today
                )

                todayStatuses = [
                    .github: effectiveDays.github[today] ?? .unknown,
                    .leetcode: effectiveDays.leetcode[today] ?? .unknown,
                    .combined: effectiveDays.combined[today] ?? .unknown
                ]

                metrics = Self.makeMetrics(
                    effectiveDays: effectiveDays,
                    today: today,
                    todayStatuses: todayStatuses,
                    todayOverrides: todayOverrides
                )

                updateSquareTimelines(
                    githubDays: effectiveDays.github,
                    leetCodeDays: effectiveDays.leetcode,
                    combinedDays: effectiveDays.combined,
                    overrides: overrides,
                    from: from,
                    to: today
                )

                if lastSyncAt == nil {
                    lastSyncWarning = "Using local fallback data until provider sync completes."
                }

                return
            }

            let effectiveDays = effectiveDayMaps(
                githubDays: githubDays,
                leetCodeDays: leetCodeDays,
                overrides: overrides,
                from: from,
                to: today
            )

            todayStatuses = [
                .github: effectiveDays.github[today] ?? .unknown,
                .leetcode: effectiveDays.leetcode[today] ?? .unknown,
                .combined: effectiveDays.combined[today] ?? .unknown
            ]
            githubContributionDiagnostic = Self.githubContributionDiagnostic(from: githubDays)

            metrics = Self.makeMetrics(
                effectiveDays: effectiveDays,
                today: today,
                todayStatuses: todayStatuses,
                todayOverrides: todayOverrides
            )

            updateSquareTimelines(
                githubDays: effectiveDays.github,
                leetCodeDays: effectiveDays.leetcode,
                combinedDays: effectiveDays.combined,
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
        githubDays: [LocalDay: DayStatus],
        leetCodeDays: [LocalDay: DayStatus],
        overrides: [LocalDay: [ActivitySource: ManualOverride]],
        from: LocalDay,
        to: LocalDay
    ) -> (
        github: [LocalDay: DayStatus],
        leetcode: [LocalDay: DayStatus],
        combined: [LocalDay: DayStatus]
    ) {
        var effectiveGithubDays: [LocalDay: DayStatus] = [:]
        var effectiveLeetCodeDays: [LocalDay: DayStatus] = [:]
        var combinedDays: [LocalDay: DayStatus] = [:]

        for day in days(from: from, to: to) {
            let sourceStatuses: [ActivitySource: DayStatus] = [
                .github: githubDays[day] ?? .unknown,
                .leetcode: leetCodeDays[day] ?? .unknown
            ]
            let overrideStatuses = overrides[day]?.mapValues(\.status) ?? [:]
            let effective = StreakEngine.applyOverrides(sourceStatuses: sourceStatuses, overrides: overrideStatuses)

            effectiveGithubDays[day] = effective[.github] ?? .unknown
            effectiveLeetCodeDays[day] = effective[.leetcode] ?? .unknown
            combinedDays[day] = CombinedStatusResolver.derive(
                effectiveStatuses: effective,
                requiredSources: ProviderRegistry.combinedRequiredSources
            )
        }

        return (github: effectiveGithubDays, leetcode: effectiveLeetCodeDays, combined: combinedDays)
    }

    nonisolated static func makeMetrics(
        effectiveDays: (
            github: [LocalDay: DayStatus],
            leetcode: [LocalDay: DayStatus],
            combined: [LocalDay: DayStatus]
        ),
        today: LocalDay,
        todayStatuses: [ActivitySource: DayStatus],
        todayOverrides: [ActivitySource: ManualOverride]
    ) -> [ActivitySource: StreakMetrics] {
        [
            .github: StreakEngine.computeMetrics(
                source: .github,
                days: effectiveDays.github,
                asOf: today,
                currentStreakAsOf: CurrentStreakAnchorPolicy.anchorDay(
                    for: .github,
                    today: today,
                    todayStatuses: todayStatuses,
                    todayOverrides: todayOverrides
                )
            ),
            .leetcode: StreakEngine.computeMetrics(
                source: .leetcode,
                days: effectiveDays.leetcode,
                asOf: today,
                currentStreakAsOf: CurrentStreakAnchorPolicy.anchorDay(
                    for: .leetcode,
                    today: today,
                    todayStatuses: todayStatuses,
                    todayOverrides: todayOverrides
                )
            ),
            .combined: StreakEngine.computeMetrics(
                source: .combined,
                days: effectiveDays.combined,
                asOf: today,
                currentStreakAsOf: CurrentStreakAnchorPolicy.anchorDay(
                    for: .combined,
                    today: today,
                    todayStatuses: todayStatuses,
                    todayOverrides: todayOverrides
                )
            )
        ]
    }

    nonisolated static func githubContributionDiagnostic(from githubDays: [LocalDay: DayStatus]) -> String? {
        guard let latestDay = githubDays.keys.max(),
              let latestStatus = githubDays[latestDay] else {
            return nil
        }

        return "GitHub contribution calendar: \(latestDay.isoDate) \(latestStatus.rawValue). Commits only count when GitHub counts them as contributions."
    }

    private func updateSquareTimelines(
        githubDays: [LocalDay: DayStatus],
        leetCodeDays: [LocalDay: DayStatus],
        combinedDays: [LocalDay: DayStatus],
        overrides: [LocalDay: [ActivitySource: ManualOverride]],
        from: LocalDay,
        to: LocalDay
    ) {
        contributionSquares = [
            .github: makeSquares(source: .github, days: githubDays, overrides: overrides, from: from, to: to),
            .leetcode: makeSquares(source: .leetcode, days: leetCodeDays, overrides: overrides, from: from, to: to)
        ]
        activitySquares = makeSquares(source: .combined, days: combinedDays, overrides: overrides, from: from, to: to)
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
        let leetCodeConfigured = !leetCodeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return githubConfigured || leetCodeConfigured
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
            secretStore: secretStore,
            githubPATKey: Self.githubPATKey
        )
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

    private func updateLastSyncAt() {
        let lastSuccesses = providerSyncState.values.compactMap(\.lastSuccessAt)
        lastSyncAt = lastSuccesses.max()
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

    private static func seedDayMap(in timeZone: TimeZone) -> (
        github: [LocalDay: DayStatus],
        leetcode: [LocalDay: DayStatus],
        combined: [LocalDay: DayStatus]
    ) {
        var github: [LocalDay: DayStatus] = [:]
        var leetcode: [LocalDay: DayStatus] = [:]
        var combined: [LocalDay: DayStatus] = [:]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        for offset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let day = LocalDay.from(date: date, in: timeZone)

            let githubStatus: DayStatus = offset % 5 == 0 ? .inactive : .active
            let leetCodeStatus: DayStatus = offset % 7 == 0 ? .unknown : .active

            github[day] = githubStatus
            leetcode[day] = leetCodeStatus
            combined[day] = CombinedStatusResolver.derive(
                effectiveStatuses: [
                    .github: githubStatus,
                    .leetcode: leetCodeStatus
                ],
                requiredSources: ProviderRegistry.combinedRequiredSources
            )
        }

        return (github: github, leetcode: leetcode, combined: combined)
    }
}
