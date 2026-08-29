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
        case httpStatus(code: Int, message: String?)
        case apiError(code: Int, message: String)
        case scrobbleIgnored(code: Int?, message: String)

        var errorDescription: String? {
            switch self {
            case .missingApiKey: return NSLocalizedString("Missing Last.fm API key.", comment: "")
            case .missingApiSecret: return NSLocalizedString("Missing Last.fm API secret.", comment: "")
            case .missingSessionKey: return NSLocalizedString("Not connected to Last.fm (missing session key).", comment: "")
            case .invalidBaseURL: return NSLocalizedString("Invalid Last.fm base URL.", comment: "")
            case .invalidRequestURL: return NSLocalizedString("Invalid Last.fm request URL.", comment: "")
            case .invalidResponse: return NSLocalizedString("Invalid response from Last.fm.", comment: "")
            case .httpStatus(let code, let message):
                if let message, !message.isEmpty { return message }
                return String(format: NSLocalizedString("Last.fm returned HTTP %d.", comment: ""), code)
            case .apiError(_, let message): return message
            case .scrobbleIgnored(_, let message): return message
            }
        }

        var shouldRetryScrobble: Bool {
            switch self {
            case .scrobbleIgnored(let code, _):
                // Last.fm ignore code 5 is the daily scrobble limit; keep it retryable.
                return code == 5
            case .httpStatus(let code, _):
                return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
            case .apiError(let code, _):
                // Retryable Last.fm API errors:
                // 8: Operation failed - Most errors; try again.
                // 11: Service Offline - This service is temporarily offline.
                // 16: Service Unavailable - Try again later.
                // 29: Rate limit exceeded.
                return code == 8 || code == 11 || code == 16 || code == 29
            case .missingApiKey, .missingApiSecret, .missingSessionKey, .invalidBaseURL, .invalidRequestURL, .invalidResponse:
                return false
            }
        }
    }

    private let apiKey: String
    private let apiSecret: String
    private let baseURL: URL
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

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
        applyOptionalTrackMetadata(from: track, to: &params)
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
        applyOptionalTrackMetadata(from: track, to: &params)
        let json = try await signedCall(
            method: "track.scrobble",
            sessionKey: sessionKey,
            params: params,
            httpMethod: "POST"
        )
        try validateScrobbleAccepted(json)
    }

    func scrobbleBatch(items: [(track: Track, startTimestamp: Int)], sessionKey: String) async throws {
        guard !items.isEmpty else { return }
        for chunk in stride(from: 0, to: items.count, by: 50).map({ Array(items[$0..<min($0 + 50, items.count)]) }) {
            var params: [String: String] = [:]
            for (index, item) in chunk.enumerated() {
                let i = "[\(index)]"
                params["artist\(i)"] = item.track.artist
                params["track\(i)"] = item.track.title
                params["timestamp\(i)"] = String(item.startTimestamp)
                applyOptionalTrackMetadata(from: item.track, to: &params, indexSuffix: i)
            }
            let json = try await signedCall(
                method: "track.scrobble",
                sessionKey: sessionKey,
                params: params,
                httpMethod: "POST"
            )
            try validateScrobbleAccepted(json)
        }
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

    private func applyOptionalTrackMetadata(from track: Track, to params: inout [String: String], indexSuffix: String = "") {
        if let album = normalized(track.album) {
            params["album\(indexSuffix)"] = album
        }
        if let albumArtist = Track.albumArtistForScrobbleMetadata(track.albumArtist) {
            params["albumArtist\(indexSuffix)"] = albumArtist
        }
        if let durationSeconds = track.durationSeconds, durationSeconds > 0 {
            params["duration\(indexSuffix)"] = String(Int(durationSeconds.rounded()))
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func validateScrobbleAccepted(_ json: [String: Any]) throws {
        guard let scrobbles = json["scrobbles"] as? [String: Any] else {
            throw ClientError.invalidResponse
        }

        let attrs = scrobbles["@attr"] as? [String: Any]
        let accepted = intValue(attrs?["accepted"])
        let ignored = intValue(attrs?["ignored"])

        if let accepted, accepted > 0 { return }
        if let ignored, ignored == 0 { return }

        let ignoredMessage = firstIgnoredMessage(in: scrobbles)
        let code = intValue(ignoredMessage?["code"])
        let message = stringValue(ignoredMessage?["#text"]) ??
            stringValue(ignoredMessage?["text"]) ??
            NSLocalizedString("Last.fm ignored this scrobble.", comment: "")

        throw ClientError.scrobbleIgnored(code: code, message: message)
    }

    private func firstIgnoredMessage(in scrobbles: [String: Any]) -> [String: Any]? {
        if let scrobble = scrobbles["scrobble"] as? [String: Any] {
            return scrobble["ignoredMessage"] as? [String: Any]
        }

        if let scrobbles = scrobbles["scrobble"] as? [[String: Any]] {
            for scrobble in scrobbles {
                guard let ignoredMessage = scrobble["ignoredMessage"] as? [String: Any] else { continue }
                let code = intValue(ignoredMessage["code"])
                let message = stringValue(ignoredMessage["#text"]) ?? stringValue(ignoredMessage["text"])
                if code != 0 || !(message ?? "").isEmpty { return ignoredMessage }
            }
        }

        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw ClientError.httpStatus(code: http.statusCode, message: responseMessage(from: data))
        }
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

    private func responseMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let obj = try? JSONSerialization.jsonObject(with: data),
           let json = obj as? [String: Any],
           let message = json["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let string = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}
