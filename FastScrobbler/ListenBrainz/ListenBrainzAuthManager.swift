import Foundation

@MainActor
final class ListenBrainzAuthManager: ObservableObject {
    enum AuthError: Error, LocalizedError {
        case emptyToken
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .emptyToken:
                return NSLocalizedString("Please enter a ListenBrainz API token.", comment: "")
            case .invalidToken:
                return NSLocalizedString("Invalid ListenBrainz API token.", comment: "")
            }
        }
    }

    @Published private(set) var userToken: String?
    @Published private(set) var username: String?
    @Published var isConnecting: Bool = false

    private let usernameDefaultsKey = "FastScrobbler.listenbrainz.username"
    private let client = ListenBrainzClient()

    let tokenPageURL = URL(string: "https://listenbrainz.org/profile/")!

    init() {
        userToken = ListenBrainzSessionStore.readUserToken()
        if let stored = AppGroup.userDefaults.string(forKey: usernameDefaultsKey) {
            username = stored
        } else if let legacy = UserDefaults.standard.string(forKey: usernameDefaultsKey) {
            username = legacy
            AppGroup.userDefaults.set(legacy, forKey: usernameDefaultsKey)
            UserDefaults.standard.removeObject(forKey: usernameDefaultsKey)
        } else {
            username = nil
        }
    }

    var isConnected: Bool {
        guard let token = userToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return false
        }
        return true
    }

    func connect(token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.emptyToken
        }

        isConnecting = true
        defer { isConnecting = false }

        let fetchedUsername = try await client.validateToken(userToken: trimmed)
        ListenBrainzSessionStore.writeUserToken(trimmed)
        AppGroup.userDefaults.set(fetchedUsername, forKey: usernameDefaultsKey)

        self.userToken = trimmed
        self.username = fetchedUsername
    }

    func disconnect() {
        ListenBrainzSessionStore.deleteUserToken()
        userToken = nil
        AppGroup.userDefaults.removeObject(forKey: usernameDefaultsKey)
        username = nil
    }

    func refreshUserInfoIfNeeded() async {
        guard let userToken, !userToken.isEmpty else { return }
        guard username == nil else { return }
        do {
            let name = try await client.validateToken(userToken: userToken)
            AppGroup.userDefaults.set(name, forKey: usernameDefaultsKey)
            username = name
        } catch {
            // Non-fatal fallback
        }
    }

    var profileURL: URL? {
        guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { return nil }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "https://listenbrainz.org/user/\(encoded)")
    }

    func freshProfileURL() -> URL? {
        guard let profileURL else { return nil }
        guard var components = URLComponents(url: profileURL, resolvingAgainstBaseURL: false) else {
            return profileURL
        }

        var items = components.queryItems ?? []
        items.removeAll(where: { $0.name == "fs_refresh" })
        items.append(URLQueryItem(name: "fs_refresh", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url ?? profileURL
    }
}
