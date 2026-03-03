import CryptoKit
import Foundation

struct LastFMClient {
    enum ClientError: Error, LocalizedError {
        case missingApiKey
        case missingApiSecret
        case missingSessionKey
        case invalidBaseURL
        case invalidRequestURL
        case invalidResponse
        case apiError(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingApiKey: return "Missing Last.fm API key."
            case .missingApiSecret: return "Missing Last.fm API secret."
            case .missingSessionKey: return "Not connected to Last.fm (missing session key)."
            case .invalidBaseURL: return "Invalid Last.fm base URL."
            case .invalidRequestURL: return "Invalid Last.fm request URL."
            case .invalidResponse: return "Invalid response from Last.fm."
            case .apiError(_, let message): return message
            }
        }
    }

    private let apiKey: String
    private let apiSecret: String
    private let baseURL: URL

    init(apiKey: String = LastFMSecrets.apiKey, apiSecret: String = LastFMSecrets.apiSecret) throws {
        guard !apiKey.isEmpty else { throw ClientError.missingApiKey }
        guard !apiSecret.isEmpty else { throw ClientError.missingApiSecret }
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        guard let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/") else {
            throw ClientError.invalidBaseURL
        }
        self.baseURL = baseURL
    }

    func getToken() async throws -> String {
        let json = try await signedCall(
            method: "auth.getToken",
            sessionKey: nil,
            params: [:],
            httpMethod: "GET"
        )
        if let token = json["token"] as? String { return token }
        throw ClientError.invalidResponse
    }

    func getSession(token: String) async throws -> String {
        let json = try await signedCall(
            method: "auth.getSession",
            sessionKey: nil,
            params: ["token": token],
            httpMethod: "GET"
        )
        if
            let session = json["session"] as? [String: Any],
            let key = session["key"] as? String
        {
            return key
        }
        throw ClientError.invalidResponse
    }

    func getUsername(sessionKey: String) async throws -> String {
        let json = try await signedCall(
            method: "user.getInfo",
            sessionKey: sessionKey,
            params: [:],
            httpMethod: "GET"
        )
        if
            let user = json["user"] as? [String: Any],
            let name = user["name"] as? String,
            !name.isEmpty
        {
            return name
        }
        throw ClientError.invalidResponse
    }

    func updateNowPlaying(track: Track, sessionKey: String) async throws {
        var params: [String: String] = [
            "artist": track.artist,
            "track": track.title,
        ]
        if let album = track.album, !album.isEmpty { params["album"] = album }
        if let d = track.durationSeconds, d > 0 { params["duration"] = String(Int(d.rounded())) }
        _ = try await signedCall(
            method: "track.updateNowPlaying",
            sessionKey: sessionKey,
            params: params,
            httpMethod: "POST"
        )
    }

    func scrobble(track: Track, sessionKey: String, startTimestamp: Int) async throws {
        var params: [String: String] = [
            "artist": track.artist,
            "track": track.title,
            "timestamp": String(startTimestamp),
        ]
        if let album = track.album, !album.isEmpty { params["album"] = album }
        if let d = track.durationSeconds, d > 0 { params["duration"] = String(Int(d.rounded())) }
        _ = try await signedCall(
            method: "track.scrobble",
            sessionKey: sessionKey,
            params: params,
            httpMethod: "POST"
        )
    }

    func love(track: Track, sessionKey: String) async throws {
        let params: [String: String] = [
            "artist": track.artist,
            "track": track.title,
        ]
        _ = try await signedCall(
            method: "track.love",
            sessionKey: sessionKey,
            params: params,
            httpMethod: "POST"
        )
    }

    private func signedCall(
        method: String,
        sessionKey: String?,
        params: [String: String],
        httpMethod: String
    ) async throws -> [String: Any] {
        var allParams = params
        allParams["method"] = method
        allParams["api_key"] = apiKey
        if let sessionKey { allParams["sk"] = sessionKey }
        allParams["format"] = "json"

        let signature = apiSignature(params: allParams)
        allParams["api_sig"] = signature

        var request: URLRequest
        switch httpMethod.uppercased() {
        case "GET":
            guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw ClientError.invalidBaseURL
            }
            comps.queryItems = allParams
                .sorted(by: { $0.key < $1.key })
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = comps.url else { throw ClientError.invalidRequestURL }
            request = URLRequest(url: url)
            request.httpMethod = "GET"
        default:
            request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = formURLEncoded(allParams)
        }

        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #elseif os(watchOS)
        let platform = "watchOS"
        #elseif os(tvOS)
        let platform = "tvOS"
        #else
        let platform = "Apple"
        #endif
        request.setValue("FastScrobbler/1.0 (\(platform))", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let json = obj as? [String: Any] else { throw ClientError.invalidResponse }
        if let code = json["error"] as? Int, let message = json["message"] as? String {
            throw ClientError.apiError(code: code, message: message)
        }
        return json
    }

    private func apiSignature(params: [String: String]) -> String {
        // Per Last.fm: concatenate key+value pairs in alphabetical key order (excluding `format`),
        // append shared secret, then MD5.
        let filtered = params.filter { $0.key != "format" }
        let base = filtered
            .sorted(by: { $0.key < $1.key })
            .map { $0.key + $0.value }
            .joined() + apiSecret

        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func formURLEncoded(_ params: [String: String]) -> Data {
        let pairs = params
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        return Data(pairs.utf8)
    }

    private func urlEncode(_ s: String) -> String {
        // application/x-www-form-urlencoded (RFC 3986-ish): space becomes '+'
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = s
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return encoded.replacingOccurrences(of: " ", with: "+")
    }
}
