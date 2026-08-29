import SwiftUI

enum WhatsNewRelease {
    private enum Keys {
        static let lastSeenVersion = "FastScrobbler.WhatsNew.lastSeenVersion"
    }

    static let version = "7.0"

    static func currentAppVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func shouldPresent() -> Bool {
        let defaults = UserDefaults.standard
        guard let currentVersion = currentAppVersion(), !currentVersion.isEmpty else {
            return false
        }

        guard let lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) else {
            defaults.set(currentVersion, forKey: Keys.lastSeenVersion)
            return false
        }

        guard currentVersion == version else {
            if lastSeenVersion != currentVersion {
                defaults.set(currentVersion, forKey: Keys.lastSeenVersion)
            }
            return false
        }

        return lastSeenVersion != currentVersion
    }

    static func markSeen() {
        guard let currentVersion = currentAppVersion(), !currentVersion.isEmpty else { return }
        UserDefaults.standard.set(currentVersion, forKey: Keys.lastSeenVersion)
    }
}
