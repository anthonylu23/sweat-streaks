import SwiftUI
import SweatStreaksCore

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 12
        static let chip: CGFloat = 8
        static let square: CGFloat = 2
    }

    enum Typography {
        static let display = Font.system(size: 40, weight: .bold, design: .rounded)
        static let title = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 12, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 10, weight: .regular)
        static let captionStrong = Font.system(size: 10, weight: .medium)
        static let mono = Font.system(size: 10, weight: .regular, design: .monospaced)
    }

    enum Palette {
        static let github = Color(red: 0.22, green: 0.78, blue: 0.39)
        static let leetcode = Color(red: 0.98, green: 0.62, blue: 0.07)
        static let codex = Color(red: 0.18, green: 0.55, blue: 0.95)
        static let claudeCode = Color(red: 0.58, green: 0.39, blue: 0.96)
        static let cursor = Color(red: 0.15, green: 0.72, blue: 0.68)
        static let combined = Color(red: 1.0, green: 0.42, blue: 0.21)

        static let inactiveSquare = Color(nsColor: .tertiaryLabelColor).opacity(0.18)
        static let unknownSquare = Color(nsColor: .tertiaryLabelColor).opacity(0.08)

        static let risk = Color(red: 0.95, green: 0.45, blue: 0.20)
        static let danger = Color(red: 0.91, green: 0.30, blue: 0.34)

        static func active(for source: ActivitySource) -> Color {
            switch source {
            case .github: return github
            case .leetcode: return leetcode
            case .codex: return codex
            case .claudeCode: return claudeCode
            case .cursor: return cursor
            case .combined: return combined
            }
        }
    }
}

extension View {
    func appCard(padding: CGFloat = DS.Spacing.m) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(.separator.opacity(0.4), lineWidth: 1)
            }
    }
}

struct StatusDot: View {
    let status: DayStatus
    let source: ActivitySource
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(fillColor)
            .overlay {
                Circle()
                    .stroke(strokeColor, lineWidth: status == .unknown ? 1 : 0)
            }
            .frame(width: size, height: size)
            .animation(.smooth(duration: 0.25), value: status)
            .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch status {
        case .active:
            return DS.Palette.active(for: source)
        case .inactive:
            return DS.Palette.danger.opacity(0.85)
        case .unknown:
            return Color.clear
        }
    }

    private var strokeColor: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
}

struct SourceIcon: View {
    let source: ActivitySource
    var size: CGFloat = 14

    var body: some View {
        icon
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        switch source {
        case .github:
            Image(nsImage: BrandIcon.github)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(DS.Palette.github)
        case .leetcode:
            Image(nsImage: BrandIcon.leetcode)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(DS.Palette.leetcode)
        case .codex:
            Image(nsImage: BrandIcon.codex)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(DS.Palette.codex)
        case .claudeCode:
            Image(nsImage: BrandIcon.claudeCode)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(DS.Palette.claudeCode)
        case .cursor:
            Image(nsImage: BrandIcon.cursor)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(DS.Palette.cursor)
        case .combined:
            Image(systemName: "flame.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(DS.Palette.combined)
        }
    }
}

struct SourceBadge: View {
    let source: ActivitySource

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            SourceIcon(source: source, size: 12)
            Text(label)
                .font(DS.Typography.captionStrong)
        }
        .foregroundStyle(DS.Palette.active(for: source))
    }

    private var label: String {
        source.displayName
    }
}
