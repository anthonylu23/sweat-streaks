import AppKit
import SwiftUI
import SweatStreaksCore

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            todayStatusSection
            streakSection
            syncSection
            actionSection
        }
        .padding(14)
        .frame(width: 360)
    }

    private var todayStatusSection: some View {
        GroupBox("Today") {
            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "GitHub", value: model.todayStatuses[.github] ?? .unknown)
                statusRow(title: "LeetCode", value: model.todayStatuses[.leetcode] ?? .unknown)
                statusRow(title: "Combined", value: model.todayStatuses[.combined] ?? .unknown)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var streakSection: some View {
        GroupBox("Streaks") {
            VStack(alignment: .leading, spacing: 8) {
                metricRow(title: "GitHub", metrics: model.metrics[.github])
                metricRow(title: "LeetCode", metrics: model.metrics[.leetcode])
                metricRow(title: "Combined", metrics: model.metrics[.combined])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var syncSection: some View {
        GroupBox("Sync") {
            VStack(alignment: .leading, spacing: 6) {
                if let lastSyncAt = model.lastSyncAt {
                    Text("Last sync: \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Last sync: never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.isSyncing {
                    Text("Sync in progress...")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                if let state = model.providerSyncState[.github], state.isStale {
                    Text("GitHub data is stale (>24h since last successful sync).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let authError = model.authErrorMessage {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let warning = model.lastSyncWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var actionSection: some View {
        HStack {
            Button("Refresh Now") {
                model.refreshNow()
            }
            .disabled(model.isSyncing)

            Button("Edit Today") {
                model.editTodayToggleGithub()
            }

            Spacer()

            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .buttonStyle(.bordered)
    }

    private func statusRow(title: String, value: DayStatus) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.rawValue.capitalized)
                .foregroundStyle(statusColor(value))
        }
        .font(.subheadline)
    }

    private func metricRow(title: String, metrics: StreakMetrics?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let metrics {
                Text("\(metrics.current) current / \(metrics.longest) longest")
            } else {
                Text("--")
            }
        }
        .font(.subheadline)
    }

    private func statusColor(_ status: DayStatus) -> Color {
        switch status {
        case .active:
            return .green
        case .inactive:
            return .red
        case .unknown:
            return .orange
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Accounts") {
                TextField("GitHub Username", text: $model.githubUsername)
                SecureField("GitHub PAT (Keychain)", text: $model.githubPATInput)
                TextField("LeetCode Username", text: $model.leetCodeUsername)
            }

            Section("Sync") {
                Stepper("Refresh interval: \(model.refreshIntervalMinutes) min", value: $model.refreshIntervalMinutes, in: 15...240, step: 15)
            }

            if let patStatus = model.patStatusMessage {
                Text(patStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Save") {
                model.saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 440)
    }
}
