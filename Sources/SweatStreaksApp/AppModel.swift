import Foundation
import SwiftUI
import SweatStreaksCore
import SweatStreaksPersistence

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

    @Published var githubUsername: String = ""
    @Published var leetCodeUsername: String = ""
    @Published var refreshIntervalMinutes: Int = 60
    @Published var githubPATInput: String = ""
    @Published var patStatusMessage: String?

    let repository: SweatRepository
    let settingsStore: SQLiteSettingsStore
    let secretStore: SecretStore

    private lazy var syncService: DefaultSyncService = {
        DefaultSyncService(
            repository: repository,
            providerFactory: { [weak self] in
                guard let self else {
                    throw ProviderError.unknown(message: "App model unavailable")
                }

                let username = self.githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !username.isEmpty else {
                    throw ProviderError.auth
                }

                let token = try self.secretStore.getSecret(for: Self.githubPATKey) ?? ""
                guard !token.isEmpty else {
                    throw ProviderError.auth
                }

                return GitHubProvider(username: username, token: token)
            }
        )
    }()

    init() {
        do {
            let database = try DatabaseManager()
            repository = SweatRepository(dbQueue: database.dbQueue)
            settingsStore = SQLiteSettingsStore(repository: repository)
            secretStore = KeychainSecretStore()
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }

        loadSettings()
        refreshViewStateFromStorage()

        if !githubUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !githubPATInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await refreshNow(trigger: .launch) }
        }
    }

    var combinedCurrentStreak: Int {
        metrics[.combined]?.current ?? 0
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

        let trimmedUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            authErrorMessage = "Set GitHub username in settings."
            lastSyncWarning = authErrorMessage
            return
        }

        do {
            let token = try secretStore.getSecret(for: Self.githubPATKey) ?? ""
            guard !token.isEmpty else {
                authErrorMessage = "Set GitHub PAT in settings."
                lastSyncWarning = authErrorMessage
                return
            }
        } catch {
            authErrorMessage = "Could not read GitHub PAT from Keychain."
            lastSyncWarning = authErrorMessage
            return
        }

        await syncService.refreshNow(trigger: trigger)
        providerSyncState[.github] = syncService.providerSyncState(for: .github)

        if let syncState = providerSyncState[.github] {
            lastSyncWarning = syncState.lastError
            if let error = syncState.lastError?.lowercased(), error.contains("auth") {
                authErrorMessage = syncState.lastError
            }
        }

        lastSyncAt = Date()
        refreshViewStateFromStorage()
    }

    func editTodayToggleGithub() {
        let current = todayStatuses[.github] ?? .unknown
        todayStatuses[.github] = current == .active ? .inactive : .active
        todayStatuses[.combined] = CombinedStatusResolver.derive(
            github: todayStatuses[.github] ?? .unknown,
            leetcode: todayStatuses[.leetcode] ?? .unknown
        )
    }

    func saveSettings() {
        do {
            try settingsStore.set(githubUsername, for: .githubUsername)
            try settingsStore.set(leetCodeUsername, for: .leetCodeUsername)
            try settingsStore.set(String(refreshIntervalMinutes), for: .refreshIntervalMinutes)

            let pat = githubPATInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if pat.isEmpty {
                try secretStore.deleteSecret(for: Self.githubPATKey)
                patStatusMessage = "GitHub PAT cleared from Keychain."
            } else {
                try secretStore.setSecret(pat, for: Self.githubPATKey)
                patStatusMessage = "GitHub PAT saved in Keychain."
            }
        } catch {
            lastSyncWarning = "Failed to save settings: \(error.localizedDescription)"
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

            githubPATInput = try secretStore.getSecret(for: Self.githubPATKey) ?? ""
            patStatusMessage = githubPATInput.isEmpty ? "GitHub PAT not set." : "GitHub PAT loaded from Keychain."
        } catch {
            lastSyncWarning = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    private func refreshViewStateFromStorage() {
        let today = LocalDay.from(date: Date(), in: .current)
        guard let fromDate = Calendar.current.date(byAdding: .day, value: -29, to: Date()) else {
            return
        }
        let from = LocalDay.from(date: fromDate, in: .current)

        do {
            let githubDays = try repository.fetchActivityDays(source: .github, from: from, to: today)
            let leetCodeDays = try repository.fetchActivityDays(source: .leetcode, from: from, to: today)
            let combinedDaysFromDB = try repository.fetchActivityDays(source: .combined, from: from, to: today)

            if githubDays.isEmpty && leetCodeDays.isEmpty && combinedDaysFromDB.isEmpty {
                let seed = AppModel.seedDayMap(in: .current)
                todayStatuses = [
                    .github: seed.github[today] ?? .unknown,
                    .leetcode: seed.leetcode[today] ?? .unknown,
                    .combined: seed.combined[today] ?? .unknown
                ]

                metrics = [
                    .github: StreakEngine.computeMetrics(source: .github, days: seed.github, asOf: today),
                    .leetcode: StreakEngine.computeMetrics(source: .leetcode, days: seed.leetcode, asOf: today),
                    .combined: StreakEngine.computeMetrics(source: .combined, days: seed.combined, asOf: today)
                ]

                if lastSyncAt == nil {
                    lastSyncWarning = "Using local fallback data until provider sync completes."
                }

                return
            }

            var combinedDays: [LocalDay: DayStatus] = [:]
            var cursorDate = from.date(in: .current) ?? Date()
            let endDate = today.date(in: .current) ?? Date()

            while cursorDate <= endDate {
                let day = LocalDay.from(date: cursorDate, in: .current)
                let githubStatus = githubDays[day] ?? .unknown
                let leetCodeStatus = leetCodeDays[day] ?? .unknown
                combinedDays[day] = combinedDaysFromDB[day] ?? CombinedStatusResolver.derive(github: githubStatus, leetcode: leetCodeStatus)
                cursorDate = Calendar.current.date(byAdding: .day, value: 1, to: cursorDate) ?? endDate.addingTimeInterval(1)
            }

            todayStatuses = [
                .github: githubDays[today] ?? .unknown,
                .leetcode: leetCodeDays[today] ?? .unknown,
                .combined: combinedDays[today] ?? .unknown
            ]

            metrics = [
                .github: StreakEngine.computeMetrics(source: .github, days: githubDays, asOf: today),
                .leetcode: StreakEngine.computeMetrics(source: .leetcode, days: leetCodeDays, asOf: today),
                .combined: StreakEngine.computeMetrics(source: .combined, days: combinedDays, asOf: today)
            ]
        } catch {
            lastSyncWarning = "Failed to load activity from storage: \(error.localizedDescription)"
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

        let now = Date()
        for offset in 0..<30 {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) else { continue }
            let day = LocalDay.from(date: date, in: timeZone)

            let githubStatus: DayStatus = offset % 5 == 0 ? .inactive : .active
            let leetCodeStatus: DayStatus = offset % 7 == 0 ? .unknown : .active

            github[day] = githubStatus
            leetcode[day] = leetCodeStatus
            combined[day] = CombinedStatusResolver.derive(github: githubStatus, leetcode: leetCodeStatus)
        }

        return (github: github, leetcode: leetcode, combined: combined)
    }
}
