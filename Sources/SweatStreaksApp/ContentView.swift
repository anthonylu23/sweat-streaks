import AppKit
import SwiftUI
import SweatStreaksCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSource: ActivitySource = .combined

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            if model.isOnboardingNeeded {
                emptyStateCard
            } else {
                heroCard
                sourcePicker
                heatmapCard
            }
            footerBar
        }
        .padding(DS.Spacing.m)
        .frame(width: 460)
    }

    // MARK: - Hero

    private var heroCard: some View {
        let combined = model.metrics[.combined]
        let current = combined?.current ?? 0
        let longest = combined?.longest ?? 0
        let combinedStatus = model.todayStatuses[.combined] ?? .unknown
        let atRisk = combinedStatus != .active

        return HStack(alignment: .center, spacing: DS.Spacing.m) {
            ZStack {
                Circle()
                    .fill(flameTint.opacity(0.18))
                    .frame(width: 64, height: 64)
                flameSymbol
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(flameTint)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(alignment: .lastTextBaseline, spacing: DS.Spacing.s) {
                    streakNumber(current)
                    Text(current == 1 ? "day" : "days")
                        .font(DS.Typography.title)
                        .foregroundStyle(.secondary)
                }

                Text(heroCaption(current: current, longest: longest, atRisk: atRisk))
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DS.Spacing.s) {
                todayRow(source: .github)
                todayRow(source: .leetcode)
                todayRow(source: .combined)
            }
        }
        .appCard()
    }

    @ViewBuilder
    private func streakNumber(_ current: Int) -> some View {
        let text = Text("\(current)")
            .font(DS.Typography.display)
            .foregroundStyle(.primary)
        if #available(macOS 14.0, *) {
            text
                .contentTransition(.numericText(value: Double(current)))
                .animation(.snappy, value: current)
        } else {
            text.animation(.snappy, value: current)
        }
    }

    private var flameSymbol: some View {
        let status = model.todayStatuses[.combined] ?? .unknown
        let symbol = Image(systemName: status == .active ? "flame.fill" : "flame")
        if #available(macOS 14.0, *) {
            return AnyView(
                symbol.symbolEffect(.pulse, options: .repeating, isActive: status == .active)
            )
        } else {
            return AnyView(symbol)
        }
    }

    private var flameTint: Color {
        let status = model.todayStatuses[.combined] ?? .unknown
        switch status {
        case .active:
            return DS.Palette.combined
        case .inactive:
            return DS.Palette.danger
        case .unknown:
            return DS.Palette.risk.opacity(0.7)
        }
    }

    private func heroCaption(current: Int, longest: Int, atRisk: Bool) -> String {
        if current == 0 && longest == 0 {
            return "Start your first streak today."
        }
        if current == 0 {
            return "Streak broken — best was \(longest)."
        }
        if atRisk {
            return "Keep the \(current)-day streak alive."
        }
        if current >= longest {
            return "New best — keep going."
        }
        return "Longest: \(longest) days."
    }

    private func todayRow(source: ActivitySource) -> some View {
        let status = model.todayStatuses[source] ?? .unknown
        let hasOverride = source != .combined && model.todayOverrides[source] != nil

        return HStack(spacing: 6) {
            Image(systemName: sourceIcon(source))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 12)

            StatusDot(status: status, source: source, size: 8)

            Image(systemName: "pencil")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(hasOverride ? 1 : 0)
                .frame(width: 8)
        }
        .help(todayRowHelp(source: source, hasOverride: hasOverride))
        .contentShape(Rectangle())
        .contextMenu {
            if source != .combined {
                overrideMenuItems(for: source)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sourceShortLabel(source)): \(status.rawValue.capitalized)\(hasOverride ? ", manual override" : "")")
        .accessibilityHint(todayRowHelp(source: source, hasOverride: hasOverride))
    }

    private func todayRowHelp(source: ActivitySource, hasOverride: Bool) -> String {
        var parts = [sourceShortLabel(source)]
        if hasOverride {
            parts.append("manual override")
        }
        if source == .github, let diagnostic = model.githubContributionDiagnostic {
            parts.append(diagnostic)
        }
        return parts.joined(separator: " - ")
    }

    private func sourceIcon(_ source: ActivitySource) -> String {
        switch source {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .leetcode: return "curlybraces"
        case .combined: return "flame.fill"
        }
    }

    @ViewBuilder
    private func overrideMenuItems(for source: ActivitySource) -> some View {
        Button("Mark as active") {
            model.setTodayOverride(source: source, status: .active)
        }
        Button("Mark as inactive") {
            model.setTodayOverride(source: source, status: .inactive)
        }
        if model.todayOverrides[source] != nil {
            Divider()
            Button("Clear override") {
                model.clearTodayOverride(source: source)
            }
        }
    }

    private func sourceShortLabel(_ source: ActivitySource) -> String {
        switch source {
        case .github: return "GitHub"
        case .leetcode: return "LeetCode"
        case .combined: return "Combined"
        }
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        HStack {
            Picker("", selection: $selectedSource) {
                ForEach([ActivitySource.combined, .github, .leetcode], id: \.self) { source in
                    Text(sourceShortLabel(source)).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        let squares = squares(for: selectedSource)
        let metrics = model.metrics[selectedSource]
        return ContributionHeatmapCard(
            source: selectedSource,
            squares: squares,
            metrics: metrics
        )
    }

    private func squares(for source: ActivitySource) -> [ActivitySquare] {
        switch source {
        case .combined:
            return model.activitySquares
        case .github, .leetcode:
            return model.contributionSquares[source] ?? []
        }
    }

    // MARK: - Empty state

    private var emptyStateCard: some View {
        VStack(spacing: DS.Spacing.m) {
            ZStack {
                Circle()
                    .fill(DS.Palette.combined.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "flame")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(DS.Palette.combined)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text("Start your streak")
                    .font(DS.Typography.title)
                Text("Connect a GitHub or LeetCode account to begin tracking daily activity.")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: DS.Spacing.s) {
                Button {
                    SettingsWindowPresenter.show(model: model)
                } label: {
                    Label("Connect GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    SettingsWindowPresenter.show(model: model)
                } label: {
                    Label("Connect LeetCode", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, DS.Spacing.xs)
        }
        .padding(.vertical, DS.Spacing.xl)
        .appCard()
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: DS.Spacing.s) {
            syncStatusView

            Spacer()

            if let authError = model.authErrorMessage {
                Label(authError, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                model.refreshNow()
            } label: {
                refreshIcon
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .disabled(model.isSyncing)
            .help("Refresh now")

            Button {
                SettingsWindowPresenter.show(model: model)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .help("Settings")

            Menu {
                Section("Override today") {
                    Menu("GitHub") {
                        overrideMenuItems(for: .github)
                    }
                    Menu("LeetCode") {
                        overrideMenuItems(for: .leetcode)
                    }
                }
                Divider()
                Button("Quit Sweat Streaks") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 14, height: 14)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
    }

    @ViewBuilder
    private var refreshIcon: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, options: .repeating, isActive: model.isSyncing)
        } else if #available(macOS 14.0, *) {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.pulse, options: .repeating, isActive: model.isSyncing)
        } else {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(model.isSyncing ? 360 : 0))
                .animation(model.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isSyncing)
        }
    }

    private var syncStatusView: some View {
        let staleProvider = model.providerSyncState.values.first(where: { $0.isStale })
        let cooldownProvider = model.providerSyncState.values.first(where: {
            ($0.cooldownUntil ?? .distantPast) > Date()
        })

        return HStack(spacing: DS.Spacing.xs) {
            if model.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Syncing…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            } else if let stale = staleProvider {
                Label("\(sourceShortLabel(stale.source)) is stale", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.risk)
            } else if let cooldown = cooldownProvider, let until = cooldown.cooldownUntil {
                Label("\(sourceShortLabel(cooldown.source)) cooling down · \(until.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            } else if let lastSync = model.lastSyncAt {
                Label("Synced \(lastSync.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Never synced", systemImage: "circle.dashed")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Heatmap card

private struct ContributionHeatmapCard: View {
    let source: ActivitySource
    let squares: [ActivitySquare]
    let metrics: StreakMetrics?

    private let squareSize: CGFloat = 13
    private let gap: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 22
    private let monthLabelHeight: CGFloat = 13
    private let visibleWeeks: Int = 12

    private var weekStride: CGFloat { squareSize + gap }
    private var graphWidth: CGFloat { CGFloat(max(weeks.count, 1)) * weekStride - gap }
    private var graphHeight: CGFloat { CGFloat(7) * weekStride - gap }
    private var activeDays: Int { sortedSquares.filter { $0.status == .active }.count }
    private var weeks: [HeatmapWeek] { buildWeeks() }
    private var monthLabels: [HeatmapMonthLabel] { buildMonthLabels() }

    private var activeColor: Color { DS.Palette.active(for: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            header

            HStack(alignment: .top, spacing: DS.Spacing.s) {
                Spacer()
                weekdayLabels
                    .padding(.top, monthLabelHeight)

                VStack(alignment: .leading, spacing: 6) {
                    monthHeader
                    heatmapGrid
                    legendRow
                }
                Spacer()
            }
        }
        .appCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sourceTitle(source)) heatmap, last \(visibleWeeks) weeks")
        .accessibilityValue("\(activeDays) active days. Current streak \(metrics?.current ?? 0). Longest streak \(metrics?.longest ?? 0).")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            SourceBadge(source: source)
            Spacer()
            stat(label: "Active days", value: "\(activeDays)")
            divider
            stat(label: "Current", value: "\(metrics?.current ?? 0)")
            divider
            stat(label: "Longest", value: "\(metrics?.longest ?? 0)")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(width: 1, height: 22)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var monthHeader: some View {
        ZStack(alignment: .leading) {
            ForEach(monthLabels) { label in
                Text(label.title)
                    .font(DS.Typography.captionStrong)
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(label.weekIndex) * weekStride)
            }
        }
        .frame(width: graphWidth, height: monthLabelHeight, alignment: .leading)
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(weeks) { week in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { weekdayIndex in
                        if let square = week.squaresByWeekday[weekdayIndex] {
                            heatmapSquare(square)
                        } else {
                            emptySquare
                        }
                    }
                }
            }
        }
        .frame(width: graphWidth, height: graphHeight, alignment: .topLeading)
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdayTitle(index))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: weekdayLabelWidth, height: squareSize, alignment: .trailing)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Less")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            ForEach(legendColors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: DS.Radius.square)
                    .fill(legendColors[index])
                    .frame(width: squareSize, height: squareSize)
            }
            Text("More")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: graphWidth, alignment: .trailing)
    }

    private var legendColors: [Color] {
        [
            DS.Palette.inactiveSquare,
            activeColor.opacity(0.30),
            activeColor.opacity(0.55),
            activeColor.opacity(0.80),
            activeColor
        ]
    }

    private var emptySquare: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: squareSize, height: squareSize)
    }

    private func heatmapSquare(_ square: ActivitySquare) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.square)
            .fill(squareColor(square))
            .overlay {
                if square.hasOverride {
                    RoundedRectangle(cornerRadius: DS.Radius.square)
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
            .frame(width: squareSize, height: squareSize)
            .help(squareHelp(square))
    }

    private func squareColor(_ square: ActivitySquare) -> Color {
        switch square.status {
        case .active:
            return activeColor
        case .inactive:
            return DS.Palette.inactiveSquare
        case .unknown:
            return DS.Palette.unknownSquare
        }
    }

    private func squareHelp(_ square: ActivitySquare) -> String {
        var parts = [
            sourceTitle(square.source),
            square.day.isoDate,
            square.status.rawValue.capitalized
        ]
        if square.hasOverride {
            parts.append("Manual override")
        }
        return parts.joined(separator: " · ")
    }

    private func sourceTitle(_ source: ActivitySource) -> String {
        switch source {
        case .github: return "GitHub"
        case .leetcode: return "LeetCode"
        case .combined: return "Combined"
        }
    }

    private func weekdayTitle(_ index: Int) -> String {
        switch index {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

    private func buildWeeks() -> [HeatmapWeek] {
        guard let firstDate = sortedSquares.first?.day.date(in: .current),
              let lastDate = sortedSquares.last?.day.date(in: .current),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start else {
            return []
        }

        var weeksByIndex: [Int: [Int: ActivitySquare]] = [:]
        for square in sortedSquares {
            guard let date = square.day.date(in: .current) else { continue }
            let dayOffset = calendar.dateComponents([.day], from: weekStart, to: date).day ?? 0
            let weekIndex = max(dayOffset / 7, 0)
            let weekdayIndex = calendar.component(.weekday, from: date) - 1
            weeksByIndex[weekIndex, default: [:]][weekdayIndex] = square
        }

        let finalOffset = calendar.dateComponents([.day], from: weekStart, to: lastDate).day ?? 0
        let finalWeek = max(finalOffset / 7, 0)
        return (0...finalWeek).map { index in
            HeatmapWeek(index: index, squaresByWeekday: weeksByIndex[index] ?? [:])
        }
    }

    private func buildMonthLabels() -> [HeatmapMonthLabel] {
        guard let firstDate = sortedSquares.first?.day.date(in: .current),
              let lastDate = sortedSquares.last?.day.date(in: .current),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start else {
            return []
        }

        var labels: [HeatmapMonthLabel] = []
        var currentMonthStart = firstDayOfMonth(containing: firstDate)
        let finalMonthStart = firstDayOfMonth(containing: lastDate)

        while currentMonthStart <= finalMonthStart {
            let visibleDate = max(currentMonthStart, firstDate)
            let weekIndex = max((calendar.dateComponents([.day], from: weekStart, to: visibleDate).day ?? 0) / 7, 0)
            labels.append(
                HeatmapMonthLabel(
                    id: "\(calendar.component(.year, from: currentMonthStart))-\(calendar.component(.month, from: currentMonthStart))",
                    title: monthFormatter.string(from: currentMonthStart),
                    weekIndex: weekIndex
                )
            )

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) else {
                break
            }
            currentMonthStart = nextMonth
        }

        return labels
    }

    private var sortedSquares: [ActivitySquare] {
        let allSorted = squares.sorted { $0.day < $1.day }
        guard let lastDate = allSorted.last?.day.date(in: .current),
              let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastDate)?.start,
              let firstWeekStart = calendar.date(
                byAdding: .day,
                value: -(visibleWeeks - 1) * 7,
                to: thisWeekStart
              ) else {
            return allSorted
        }
        let cutoffDay = LocalDay.from(date: firstWeekStart, in: .current)
        return allSorted.filter { $0.day >= cutoffDay }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }

    private func firstDayOfMonth(containing date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

private struct HeatmapWeek: Identifiable {
    let index: Int
    let squaresByWeekday: [Int: ActivitySquare]
    var id: Int { index }
}

private struct HeatmapMonthLabel: Identifiable {
    let id: String
    let title: String
    let weekIndex: Int
}

// MARK: - Settings window presenter

@MainActor
enum SettingsWindowPresenter {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        Task { @MainActor in
            if window == nil {
                let hostingController = NSHostingController(rootView: SettingsView(model: model, onDone: close))
                let settingsWindow = NSWindow(contentViewController: hostingController)
                settingsWindow.title = "Sweat Streaks Settings"
                settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
                settingsWindow.setContentSize(NSSize(width: 460, height: 500))
                settingsWindow.minSize = NSSize(width: 440, height: 460)
                settingsWindow.isReleasedWhenClosed = false
                settingsWindow.collectionBehavior.insert(.moveToActiveSpace)
                settingsWindow.center()
                window = settingsWindow
            } else if let hostingController = window?.contentViewController as? NSHostingController<SettingsView> {
                hostingController.rootView = SettingsView(model: model, onDone: close)
            }

            guard let window else { return }

            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }

            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    static func close() {
        window?.close()
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let onDone: () -> Void
    @FocusState private var focusedField: SettingsField?

    private enum SettingsField {
        case githubUsername
        case githubPAT
        case leetCodeUsername
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(
                        "Username",
                        text: $model.githubUsername,
                        prompt: Text("octocat")
                    )
                    .focused($focusedField, equals: .githubUsername)

                    LabeledContent("Token") {
                        HStack(spacing: DS.Spacing.s) {
                            SecureField(
                                "Token",
                                text: $model.githubPATInput,
                                prompt: Text("Paste to replace saved token")
                            )
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .focused($focusedField, equals: .githubPAT)

                            Button("Clear") {
                                model.clearGitHubPAT()
                            }
                            .controlSize(.small)
                        }
                    }

                    if let patStatus = model.patStatusMessage {
                        Text(patStatus)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    accountHeader(source: .github, connected: model.isGitHubConnected)
                }

                Section {
                    TextField(
                        "Username",
                        text: $model.leetCodeUsername,
                        prompt: Text("leetcode-user")
                    )
                    .focused($focusedField, equals: .leetCodeUsername)
                } header: {
                    accountHeader(source: .leetcode, connected: model.isLeetCodeConnected)
                }

                Section("Sync") {
                    LabeledContent("Refresh interval") {
                        Stepper("\(model.refreshIntervalMinutes) min", value: $model.refreshIntervalMinutes, in: 15...240, step: 15)
                    }
                }

                Section("Notifications") {
                    Toggle("Send daily reminder", isOn: $model.notificationsEnabled)
                    LabeledContent("Notify after") {
                        Stepper("\(String(format: "%02d", model.reminderHour)):00", value: $model.reminderHour, in: 0...23)
                    }
                }

                Section("Menu Bar") {
                    Toggle("Show GitHub streak", isOn: $model.showGitHubStreakInMenuBar)
                    Toggle("Show LeetCode streak", isOn: $model.showLeetCodeStreakInMenuBar)
                    Toggle("Show Combined streak", isOn: $model.showCombinedStreakInMenuBar)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    model.saveSettings()
                }
                Button("Done") {
                    model.saveSettings()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.m)
        }
        .frame(minWidth: 440, idealWidth: 460, minHeight: 460, idealHeight: 500)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedField = .githubUsername
            }
        }
    }

    private func accountHeader(source: ActivitySource, connected: Bool) -> some View {
        HStack(spacing: DS.Spacing.s) {
            SourceBadge(source: source)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(connected ? DS.Palette.github : Color.secondary)
                Text(connected ? "Connected" : "Not connected")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }
}
