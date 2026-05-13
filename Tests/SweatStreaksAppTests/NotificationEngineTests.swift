import Foundation
import XCTest
@testable import SweatStreaksApp
@testable import SweatStreaksCore
@testable import SweatStreaksPersistence

@MainActor
final class NotificationEngineTests: XCTestCase {
    func testRiskNotificationSendsOncePerDay() async throws {
        let settings = InMemorySettingsStore()
        let scheduler = RecordingNotificationScheduler()
        let now = Self.date(year: 2026, month: 2, day: 18, hour: 21)
        let engine = NotificationEngine(settingsStore: settings, scheduler: scheduler, now: { now })
        let today = LocalDay(year: 2026, month: 2, day: 18)

        await engine.evaluate(today: today, combinedStatus: .inactive, reminderHour: 20, notificationsEnabled: true)
        await engine.evaluate(today: today, combinedStatus: .inactive, reminderHour: 20, notificationsEnabled: true)

        let sends = await scheduler.sendCount
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(try settings.get(.lastRiskNotificationDay), today.isoDate)
    }

    func testRiskNotificationDoesNotSendForActiveCombinedStatus() async {
        let settings = InMemorySettingsStore()
        let scheduler = RecordingNotificationScheduler()
        let now = Self.date(year: 2026, month: 2, day: 18, hour: 21)
        let engine = NotificationEngine(settingsStore: settings, scheduler: scheduler, now: { now })

        await engine.evaluate(
            today: LocalDay(year: 2026, month: 2, day: 18),
            combinedStatus: .active,
            reminderHour: 20,
            notificationsEnabled: true
        )

        let sends = await scheduler.sendCount
        XCTAssertEqual(sends, 0)
    }

    func testUserNotificationSchedulerNoOpsOutsideAppBundle() async throws {
        let scheduler = UserNotificationScheduler(isRunningFromAppBundle: { false })

        let authorized = try await scheduler.requestAuthorizationIfNeeded()
        try await scheduler.sendRiskNotification(title: "Ignored", body: "Ignored")

        XCTAssertFalse(authorized)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }
}

private final class InMemorySettingsStore: SettingsStore {
    private var values: [SettingsKey: String] = [:]

    func get(_ key: SettingsKey) throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: SettingsKey) throws {
        values[key] = value
    }
}

private actor RecordingNotificationScheduler: NotificationScheduling {
    private(set) var sendCount = 0

    func requestAuthorizationIfNeeded() async throws -> Bool {
        true
    }

    func sendRiskNotification(title _: String, body _: String) async throws {
        sendCount += 1
    }
}
