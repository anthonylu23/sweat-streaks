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

        // `MenuBarExtra` does not reliably render multi-subview SwiftUI labels —
        // the live HStack with mixed Image(nsImage:) + Image(systemName:) ended
        // up showing only the first icon. Pre-rendering the whole label into a
        // single NSImage sidesteps that and is also what macOS status-bar items
        // historically expect.
        MenuBarLabelImage(items: items)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MenuBarStreakDisplay.accessibilityLabel(for: items))
    }
}

private struct MenuBarLabelImage: View {
    let items: [MenuBarStreakItem]

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
                .renderingMode(.template)
        } else {
            // Renderer briefly returns nil on the very first layout pass;
            // fall back to the live view so something always appears.
            MenuBarStreakLabel(items: items)
        }
    }

    @MainActor
    private var renderedImage: NSImage? {
        // Render the label as black-on-clear so the resulting NSImage's alpha
        // channel describes the silhouette. Marking it as a template lets the
        // menu bar tint icons + digits with the system label color so they stay
        // legible across any desktop wallpaper / appearance.
        let renderer = ImageRenderer(
            content: MenuBarStreakLabel(items: items)
                .foregroundStyle(.black)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = renderer.cgImage else { return nil }
        let size = NSSize(
            width: CGFloat(cgImage.width) / renderer.scale,
            height: CGFloat(cgImage.height) / renderer.scale
        )
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }
}

// Internal (not private) so that `MenuBarLabelImage`'s ImageRenderer can
// reference this same view; also used by the rendering smoke test below.
struct MenuBarStreakLabel: View {
    let items: [MenuBarStreakItem]

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 4) {
                SourceIcon(source: .combined, size: 15)
                Text("Sweat")
                    .font(.system(size: 13, weight: .medium))
            }
            .fixedSize()
        } else {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 3) {
                        SourceIcon(source: item.source, size: 15)
                        Text("\(item.current)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppIconManager.shared.start()
    }
}
