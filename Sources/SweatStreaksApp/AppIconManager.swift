import AppKit

@MainActor
final class AppIconManager: NSObject {
    static let shared = AppIconManager()

    private let appearanceChangedName = Notification.Name("AppleInterfaceThemeChangedNotification")

    func start() {
        applyIcon()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: appearanceChangedName,
            object: nil
        )
    }

    @objc private func systemAppearanceDidChange() {
        Task { @MainActor in
            applyIcon()
        }
    }

    private func applyIcon() {
        let resourceName = usesDarkAppearance ? "app-icon-dark" : "app-icon-light"
        guard
            let url = Bundle.module.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: "AppIcon"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return
        }

        NSApp.applicationIconImage = image
    }

    private var usesDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
