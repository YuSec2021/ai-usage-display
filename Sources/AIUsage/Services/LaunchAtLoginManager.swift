import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    private static let registeredBundlePathKey = "launchAtLogin.registeredBundlePath"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(Bundle.main.bundlePath, forKey: registeredBundlePathKey)
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
            UserDefaults.standard.removeObject(forKey: registeredBundlePathKey)
        }
    }

    /// SMAppService matches the login item by bundle identifier only, so a
    /// registration made from another copy (such as an Xcode build folder)
    /// still reports `.enabled` while macOS keeps launching that old copy at
    /// login. Re-register once whenever the release app runs from a new path.
    /// Debug builds never take over the installed app's login item.
    static func refreshRegistrationIfMoved() {
        #if !DEBUG
        let bundlePath = Bundle.main.bundlePath
        guard SMAppService.mainApp.status == .enabled,
              UserDefaults.standard.string(forKey: registeredBundlePathKey) != bundlePath else {
            return
        }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(bundlePath, forKey: registeredBundlePathKey)
        } catch {
            // Settings reads the live status, so a failed registration remains
            // visible there and can be retried by the user.
        }
        #endif
    }
}
