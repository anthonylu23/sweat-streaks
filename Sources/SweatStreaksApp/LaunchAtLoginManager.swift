import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ isEnabled: Bool) throws
}

enum LaunchAtLoginError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Start on login requires macOS 13 or later."
        }
    }
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchAtLoginError.unsupported
        }

        let service = SMAppService.mainApp
        if isEnabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
