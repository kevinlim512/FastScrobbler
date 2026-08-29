import Foundation

enum ListenBrainzSessionStore {
    private static let userTokenKey = "FastScrobbler.listenbrainz.userToken"

    static func readUserToken() -> String? {
        let value = AppGroup.userDefaults.string(forKey: userTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func writeUserToken(_ userToken: String) {
        AppGroup.userDefaults.set(userToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userTokenKey)
    }

    static func deleteUserToken() {
        AppGroup.userDefaults.removeObject(forKey: userTokenKey)
    }
}
