import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class LastFMAuthManager: NSObject, ObservableObject {
    enum AuthError: Error, LocalizedError {
        case missingCallbackScheme
        case webAuthCanceled
        case invalidCallbackURL
        case missingTokenInCallback

        var errorDescription: String? {
            switch self {
            case .missingCallbackScheme: return "Missing callback URL scheme."
            case .webAuthCanceled: return "Last.fm sign-in was canceled."
            case .invalidCallbackURL: return "Invalid sign-in callback URL."
            case .missingTokenInCallback: return "Last.fm callback did not include an auth token."
            }
        }
    }

    @Published private(set) var sessionKey: String?
    @Published private(set) var username: String?

    private let keychainService = "FastScrobbler"
    private let keychainAccount = "lastfm.sessionKey"
    private let usernameDefaultsKey = "FastScrobbler.lastfm.username"
    private var webAuth: ASWebAuthenticationSession?

    override init() {
        super.init()
        sessionKey = KeychainStore.readString(service: keychainService, account: keychainAccount)
        username = UserDefaults.standard.string(forKey: usernameDefaultsKey)
    }

    func connect() async throws {
        let client = try LastFMClient()
        guard !LastFMSecrets.callbackScheme.isEmpty else { throw AuthError.missingCallbackScheme }
        let callback = "\(LastFMSecrets.callbackScheme)://\(LastFMSecrets.callbackPath)"
        var comps = URLComponents(string: "https://www.last.fm/api/auth/")!
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: LastFMSecrets.apiKey),
            URLQueryItem(name: "cb", value: callback),
        ]
        guard let url = comps.url else { throw AuthError.invalidCallbackURL }

        let callbackURL: URL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: LastFMSecrets.callbackScheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin
                {
                    cont.resume(throwing: AuthError.webAuthCanceled)
                    return
                }
                if let error { cont.resume(throwing: error); return }
                guard let callbackURL else {
                    cont.resume(throwing: AuthError.invalidCallbackURL)
                    return
                }
                cont.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.webAuth = session
            _ = session.start()
        }

        let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let token = callbackComps?.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            throw AuthError.missingTokenInCallback
        }

        let key = try await client.getSession(token: token)
        try KeychainStore.writeString(key, service: keychainService, account: keychainAccount)
        sessionKey = key
        do {
            try await refreshUserInfo()
        } catch {
            // Non-fatal: we can still scrobble without a cached username.
        }
    }

    func disconnect() {
        KeychainStore.delete(service: keychainService, account: keychainAccount)
        sessionKey = nil
        UserDefaults.standard.removeObject(forKey: usernameDefaultsKey)
        username = nil
    }

    func refreshUserInfoIfNeeded() async {
        guard sessionKey != nil else { return }
        guard username == nil else { return }
        do {
            try await refreshUserInfo()
        } catch {
            // Non-fatal.
        }
    }

    func refreshUserInfo() async throws {
        guard let sessionKey else { return }
        let client = try LastFMClient()
        let name = try await client.getUsername(sessionKey: sessionKey)
        UserDefaults.standard.set(name, forKey: usernameDefaultsKey)
        username = name
    }

    var profileURL: URL? {
        guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { return nil }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "https://www.last.fm/user/\(encoded)")
    }
}

extension LastFMAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}
