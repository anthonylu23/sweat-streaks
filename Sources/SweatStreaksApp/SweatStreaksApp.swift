import AppKit
import SwiftUI
import SweatStreaksCore

@main
struct SweatStreaksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let items = MenuBarStreakDisplay.items(
            metrics: model.metrics,
            statuses: model.todayStatuses,
            showGitHub: model.showGitHubStreakInMenuBar,
            showLeetCode: model.showLeetCodeStreakInMenuBar,
            showCombined: model.showCombinedStreakInMenuBar
        )

        Group {
            if items.isEmpty {
                Image(systemName: "flame")
            } else if items.count == 1, let item = items.first {
                Label(
                    "\(item.current)",
                    systemImage: MenuBarStreakDisplay.iconName(for: item.source, status: item.status)
                )
            } else {
                let combinedStatus = items.first(where: { $0.source == .combined })?.status ?? .unknown
                Label(
                    MenuBarStreakDisplay.compactTitle(for: items),
                    systemImage: combinedStatus == .active ? "flame.fill" : "flame"
                )
            }
        }
        .accessibilityLabel(MenuBarStreakDisplay.accessibilityLabel(for: items))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
