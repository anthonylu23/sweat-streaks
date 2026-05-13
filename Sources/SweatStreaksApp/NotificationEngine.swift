import Foundation
import UserNotifications
import SweatStreaksCore
import SweatStreaksPersistence

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async throws -> Bool
    func sendRiskNotification(title: String, body: String) async throws
}

struct UserNotificationScheduler: NotificationScheduling {
    private let isRunningFromAppBundle: @Sendable () -> Bool

    init(isRunningFromAppBundle: @escaping @Sendable () -> Bool = UserNotificationScheduler.defaultIsRunningFromAppBundle) {
        self.isRunningFromAppBundle = isRunningFromAppBundle
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        guard isRunningFromAppBundle() else { return false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        @unknown default:
            return false
        }
    }

    func sendRiskNotification(title: String, body: String) async throws {
        guard isRunningFromAppBundle() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sweat-streaks-risk-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private static func defaultIsRunningFromAppBundle() -> Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

@MainActor
struct NotificationEngine {
    private let settingsStore: SettingsStore
    private let scheduler: NotificationScheduling
    private let now: @Sendable () -> Date

    init(
        settingsStore: SettingsStore,
        scheduler: NotificationScheduling = UserNotificationScheduler(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.scheduler = scheduler
        self.now = now
    }

    func evaluate(today: LocalDay, combinedStatus: DayStatus, reminderHour: Int, notificationsEnabled: Bool) async {
        guard notificationsEnabled, combinedStatus != .active else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let currentHour = calendar.component(.hour, from: now())
        guard currentHour >= reminderHour else { return }

        do {
            let lastNotificationDay = try settingsStore.get(.lastRiskNotificationDay)
            guard lastNotificationDay != today.isoDate else { return }
            guard try await scheduler.requestAuthorizationIfNeeded() else { return }

            try await scheduler.sendRiskNotification(
                title: "Sweat Streak at risk",
                body: "Your combined streak is not active for today."
            )
            try settingsStore.set(today.isoDate, for: .lastRiskNotificationDay)
        } catch {
            // Notifications should not block app refresh or local state updates.
        }
    }
}
