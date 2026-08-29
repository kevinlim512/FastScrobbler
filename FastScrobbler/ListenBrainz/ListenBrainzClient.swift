import Foundation

final class ListenBrainzClient: Sendable {
    enum ClientError: Error, LocalizedError {
        case invalidToken
        case apiError(statusCode: Int, message: String)
        case invalidResponse
        case urlError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidToken:
                return NSLocalizedString("Invalid or unaccepted ListenBrainz token.", comment: "")
            case .apiError(let statusCode, let message):
                return String.localizedStringWithFormat(
                    NSLocalizedString("ListenBrainz API error (%ld): %@", comment: ""),
                    statusCode,
                    message
                )
            case .invalidResponse:
                return NSLocalizedString("Invalid response from ListenBrainz.", comment: "")
            case .urlError(let error):
                return error.localizedDescription
            }
        }

        var shouldRetryScrobble: Bool {
            switch self {
            case .invalidToken:
                return false
            case .apiError(let statusCode, _):
                if statusCode == 400 || statusCode == 401 || statusCode == 403 { return false }
                return true
            case .invalidResponse, .urlError:
                return true
            }
        }
    }

    private let baseURL = URL(string: "https://api.listenbrainz.org/1/")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - API Calls

    /// Validates the token and returns the associated ListenBrainz username.
    func validateToken(userToken: String) async throws -> String {
        let token = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ClientError.invalidToken }

        var request = URLRequest(url: baseURL.appendingPathComponent("validate-token"))
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClientError.invalidToken
        }

        struct ValidateResponse: Decodable {
            let code: Int?
            let message: String?
            let error: String?
            let userName: String?
            let valid: Bool?

            enum CodingKeys: String, CodingKey {
                case code
                case message
                case error
                case userName = "user_name"
                case valid
            }
        }

        if httpResponse.statusCode == 200,
           let json = try? JSONDecoder().decode(ValidateResponse.self, from: data),
           json.valid == true,
           let userName = json.userName, !userName.isEmpty {
            return userName
        } else if let json = try? JSONDecoder().decode(ValidateResponse.self, from: data),
                  let errMessage = json.error ?? json.message {
            throw ClientError.apiError(statusCode: httpResponse.statusCode, message: errMessage)
        } else {
            throw ClientError.apiError(statusCode: httpResponse.statusCode, message: "Failed to validate ListenBrainz token.")
        }
    }

    /// Submits a Now Playing update (`listen_type: "playing_now"`).
    func sendNowPlaying(track: Track, userToken: String) async throws {
        let payloadItem: [String: Any] = [
            "track_metadata": makeTrackMetadata(track: track)
        ]
        try await submitPayload(listenType: "playing_now", payload: [payloadItem], userToken: userToken)
    }

    /// Submits a single scrobble (`listen_type: "single"`).
    func submitScrobble(track: Track, timestamp: Date, userToken: String) async throws {
        let listenedAt = Int(timestamp.timeIntervalSince1970)
        let payloadItem: [String: Any] = [
            "listened_at": listenedAt,
            "track_metadata": makeTrackMetadata(track: track)
        ]
        try await submitPayload(listenType: "single", payload: [payloadItem], userToken: userToken)
    }

    /// Submits a batch of scrobbles (`listen_type: "import"`). Max 1000 per call.
    func submitBatch(listens: [(track: Track, timestamp: Date)], userToken: String) async throws {
        guard !listens.isEmpty else { return }

        // Chunk into max 1000 per request as required by ListenBrainz API
        let chunkSize = 1000
        for i in stride(from: 0, to: listens.count, by: chunkSize) {
            let chunk = Array(listens[i..<min(i + chunkSize, listens.count)])
            let payload: [[String: Any]] = chunk.map { item in
                [
                    "listened_at": Int(item.timestamp.timeIntervalSince1970),
                    "track_metadata": makeTrackMetadata(track: item.track)
                ]
            }
            try await submitPayload(listenType: "import", payload: payload, userToken: userToken)
        }
    }

    // MARK: - Private Helpers

    private func makeTrackMetadata(track: Track) -> [String: Any] {
        var meta: [String: Any] = [
            "artist_name": track.artist,
            "track_name": track.title
        ]
        if let album = track.album, !album.isEmpty {
            meta["release_name"] = album
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        var additionalInfo: [String: Any] = [
            "submission_client": "FastScrobbler",
            "submission_client_version": appVersion
        ]
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            additionalInfo["release_artist_name"] = albumArtist
        }
        if let duration = track.durationSeconds, duration > 0 {
            additionalInfo["duration_ms"] = Int(duration * 1000)
        }
        meta["additional_info"] = additionalInfo
        return meta
    }

    private func submitPayload(listenType: String, payload: [[String: Any]], userToken: String) async throws {
        let token = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ClientError.invalidToken }

        var request = URLRequest(url: baseURL.appendingPathComponent("submit-listens"))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any] = [
            "listen_type": listenType,
            "payload": payload
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict, options: [])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ClientError.invalidToken
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["error"] as? String ?? json["message"] as? String {
                throw ClientError.apiError(statusCode: httpResponse.statusCode, message: errorMsg)
            }
            throw ClientError.apiError(statusCode: httpResponse.statusCode, message: "Server returned status code \(httpResponse.statusCode)")
        }
    }
}
