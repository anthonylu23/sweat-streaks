import SwiftUI

@main
struct SweatStreaksApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Label("B:\(model.combinedCurrentStreak)", systemImage: "flame.fill")
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
