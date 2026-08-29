import Foundation

// MARK: - Mock URL Protocol for Network Testing

private final class ListenBrainzMockURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)
    
    private static let lock = NSLock()
    private static var _requestHandler: RequestHandler?
    private static var _capturedRequests: [URLRequest] = []

    static var requestHandler: RequestHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }

    static var capturedRequests: [URLRequest] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _capturedRequests
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _capturedRequests = newValue
        }
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _requestHandler = nil
        _capturedRequests.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        ListenBrainzMockURLProtocol.lock.lock()
        ListenBrainzMockURLProtocol._capturedRequests.append(request)
        let handler = ListenBrainzMockURLProtocol._requestHandler
        ListenBrainzMockURLProtocol.lock.unlock()

        guard let handler else {
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://api.listenbrainz.org")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ListenBrainzMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func getRequestBodyData(_ request: URLRequest) -> Data? {
    if let data = request.httpBody {
        return data
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read > 0 { data.append(buffer, count: read) } else { break }
    }
    return data
}

// MARK: - Main Test Entry Point

@MainActor
func runListenBrainzTests() async {
    // Save existing environment to restore after tests finish
    let savedToken = ListenBrainzSessionStore.readUserToken()
    let savedAppGroupUsername = AppGroup.userDefaults.string(forKey: "FastScrobbler.listenbrainz.username")
    let savedStandardUsername = UserDefaults.standard.string(forKey: "FastScrobbler.listenbrainz.username")

    defer {
        if let savedToken {
            ListenBrainzSessionStore.writeUserToken(savedToken)
        } else {
            ListenBrainzSessionStore.deleteUserToken()
        }
        if let savedAppGroupUsername {
            AppGroup.userDefaults.set(savedAppGroupUsername, forKey: "FastScrobbler.listenbrainz.username")
        } else {
            AppGroup.userDefaults.removeObject(forKey: "FastScrobbler.listenbrainz.username")
        }
        if let savedStandardUsername {
            UserDefaults.standard.set(savedStandardUsername, forKey: "FastScrobbler.listenbrainz.username")
        } else {
            UserDefaults.standard.removeObject(forKey: "FastScrobbler.listenbrainz.username")
        }
        URLProtocol.unregisterClass(ListenBrainzMockURLProtocol.self)
    }

    // Register mock protocol for URLSession.shared calls as well
    URLProtocol.registerClass(ListenBrainzMockURLProtocol.self)

    section("ListenBrainz · ScrobbleService Enum")


    expectEqual("ScrobbleService.listenbrainz rawValue", ScrobbleService.listenbrainz.rawValue, "listenbrainz")
    expectEqual("ScrobbleService.listenbrainz displayName", ScrobbleService.listenbrainz.displayName, "ListenBrainz")
    expectEqual("ScrobbleService.lastfm displayName", ScrobbleService.lastfm.displayName, "Last.fm")
    expect("ScrobbleService.allCases contains .listenbrainz", ScrobbleService.allCases.contains(.listenbrainz))
    expect("ScrobbleService.allCases contains .lastfm", ScrobbleService.allCases.contains(.lastfm))

    if let encoded = try? JSONEncoder().encode(ScrobbleService.listenbrainz),
       let decoded = try? JSONDecoder().decode(ScrobbleService.self, from: encoded) {
        expectEqual("ScrobbleService JSON Codable roundtrip", decoded, .listenbrainz)
    } else {
        expect("ScrobbleService JSON Codable roundtrip", false, detail: "Encoding/decoding failed")
    }

    section("ListenBrainz · Session Store")

    // Clean initial state
    ListenBrainzSessionStore.deleteUserToken()
    expect("readUserToken returns nil when empty", ListenBrainzSessionStore.readUserToken() == nil)

    ListenBrainzSessionStore.writeUserToken("  test-token-123  \n")
    expectEqual("writeUserToken trims whitespace", ListenBrainzSessionStore.readUserToken(), "test-token-123")

    ListenBrainzSessionStore.writeUserToken("   ")
    expect("writeUserToken with empty/whitespace string removes token", ListenBrainzSessionStore.readUserToken() == nil)

    ListenBrainzSessionStore.writeUserToken("valid-token")
    ListenBrainzSessionStore.deleteUserToken()
    expect("deleteUserToken removes stored token", ListenBrainzSessionStore.readUserToken() == nil)

    section("ListenBrainz · Client Errors")

    expectEqual(
        "ClientError.invalidToken localized description",
        ListenBrainzClient.ClientError.invalidToken.localizedDescription,
        "Invalid or unaccepted ListenBrainz token."
    )
    expectEqual(
        "ClientError.apiError localized description",
        ListenBrainzClient.ClientError.apiError(statusCode: 401, message: "Unauthorized").localizedDescription,
        "ListenBrainz API error (401): Unauthorized"
    )
    expectEqual(
        "ClientError.invalidResponse localized description",
        ListenBrainzClient.ClientError.invalidResponse.localizedDescription,
        "Invalid response from ListenBrainz."
    )
    let sampleURLError = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
    expectEqual(
        "ClientError.urlError localized description",
        ListenBrainzClient.ClientError.urlError(sampleURLError).localizedDescription,
        "The Internet connection appears to be offline."
    )

    section("ListenBrainz Client · validateToken")

    let session = makeMockSession()
    let client = ListenBrainzClient(session: session)

    // 1. Empty token throws invalidToken
    do {
        _ = try await client.validateToken(userToken: "   ")
        expect("Empty token validation throws invalidToken", false, detail: "Expected error but succeeded")
    } catch let err as ListenBrainzClient.ClientError {
        if case .invalidToken = err {
            expect("Empty token validation throws invalidToken", true)
        } else {
            expect("Empty token validation throws invalidToken", false, detail: "Got \(err)")
        }
    } catch {
        expect("Empty token validation throws invalidToken", false, detail: "Unexpected error type: \(error)")
    }

    // 2. Successful token validation
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        expectEqual("validateToken HTTP method is GET", request.httpMethod, "GET")
        expectEqual("validateToken request URL", request.url?.absoluteString, "https://api.listenbrainz.org/1/validate-token")
        expectEqual("validateToken Authorization header", request.value(forHTTPHeaderField: "Authorization"), "Token sample-user-token")

        let json = #"{"code": 200, "message": "Token valid", "user_name": "test_user_lb", "valid": true}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    do {
        let validatedName = try await client.validateToken(userToken: "sample-user-token")
        expectEqual("validateToken returns valid username", validatedName, "test_user_lb")
    } catch {
        expect("validateToken succeeds for valid token", false, detail: "Error: \(error)")
    }

    // 3. API error response when valid is false
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let json = #"{"code": 200, "message": "Invalid token provided", "valid": false}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    do {
        _ = try await client.validateToken(userToken: "invalid-token")
        expect("validateToken throws apiError when valid=false", false, detail: "Expected error")
    } catch let err as ListenBrainzClient.ClientError {
        if case .apiError(let statusCode, let message) = err {
            expectEqual("apiError statusCode", statusCode, 200)
            expectEqual("apiError message", message, "Invalid token provided")
        } else {
            expect("validateToken throws apiError when valid=false", false, detail: "Got \(err)")
        }
    } catch {
        expect("validateToken throws apiError when valid=false", false, detail: "Unexpected error: \(error)")
    }

    // 4. API error response with 401 HTTP status
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let json = #"{"error": "Unauthorized token"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    do {
        _ = try await client.validateToken(userToken: "bad-token")
        expect("validateToken throws invalidToken for 401", false, detail: "Expected error")
    } catch let err as ListenBrainzClient.ClientError {
        if case .invalidToken = err {
            expect("validateToken throws invalidToken for 401", true)
        } else {
            expect("validateToken throws invalidToken for 401", false, detail: "Got \(err)")
        }
    } catch {
        expect("validateToken throws invalidToken for 401", false, detail: "Unexpected error: \(error)")
    }

    // 5. 403 status code in shouldRetryScrobble is false
    expect("apiError(403) shouldRetryScrobble is false", !ListenBrainzClient.ClientError.apiError(statusCode: 403, message: "Forbidden").shouldRetryScrobble)

    section("ListenBrainz Client · sendNowPlaying")

    // 1. Empty token check
    do {
        let track = Track(artist: "Radiohead", title: "Karma Police", album: "OK Computer", durationSeconds: 264)
        try await client.sendNowPlaying(track: track, userToken: "")
        expect("sendNowPlaying empty token throws invalidToken", false)
    } catch let err as ListenBrainzClient.ClientError {
        if case .invalidToken = err {
            expect("sendNowPlaying empty token throws invalidToken", true)
        } else {
            expect("sendNowPlaying empty token throws invalidToken", false, detail: "Got \(err)")
        }
    } catch {
        expect("sendNowPlaying empty token throws invalidToken", false, detail: "Unexpected error: \(error)")
    }

    // 2. Full now playing submission
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        expectEqual("sendNowPlaying method is POST", request.httpMethod, "POST")
        expectEqual("sendNowPlaying URL", request.url?.absoluteString, "https://api.listenbrainz.org/1/submit-listens")
        expectEqual("sendNowPlaying Authorization header", request.value(forHTTPHeaderField: "Authorization"), "Token my-lb-token")
        expectEqual("sendNowPlaying Content-Type header", request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        if let bodyData = getRequestBodyData(request),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            expectEqual("listen_type is playing_now", json["listen_type"] as? String, "playing_now")
            if let payload = json["payload"] as? [[String: Any]], let first = payload.first {
                if let meta = first["track_metadata"] as? [String: Any] {
                    expectEqual("artist_name in payload", meta["artist_name"] as? String, "Radiohead")
                    expectEqual("track_name in payload", meta["track_name"] as? String, "Karma Police")
                    expectEqual("release_name in payload", meta["release_name"] as? String, "OK Computer")
                    if let info = meta["additional_info"] as? [String: Any] {
                        expectEqual("submission_client", info["submission_client"] as? String, "FastScrobbler")
                        expect("submission_client_version present in payload", info["submission_client_version"] != nil)
                        expectEqual("release_artist_name in payload", info["release_artist_name"] as? String, "Radiohead Band")
                        expectEqual("duration_ms in payload", info["duration_ms"] as? Int, 264000)
                    } else {
                        expect("additional_info present in payload", false)
                    }
                } else {
                    expect("track_metadata present in payload", false)
                }
            } else {
                expect("payload array present", false)
            }
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }

    do {
        let fullTrack = Track(artist: "Radiohead", title: "Karma Police", album: "OK Computer", albumArtist: "Radiohead Band", durationSeconds: 264)
        try await client.sendNowPlaying(track: fullTrack, userToken: "my-lb-token")
        expect("sendNowPlaying succeeds with complete metadata", true)
    } catch {
        expect("sendNowPlaying succeeds with complete metadata", false, detail: "Error: \(error)")
    }

    // 3. Now playing submission with nil album & zero duration
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        if let bodyData = getRequestBodyData(request),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let payload = json["payload"] as? [[String: Any]],
           let first = payload.first,
           let meta = first["track_metadata"] as? [String: Any] {
            expect("release_name omitted when album is nil", meta["release_name"] == nil)
            if let info = meta["additional_info"] as? [String: Any] {
                expect("duration_ms omitted when duration is zero", info["duration_ms"] == nil)
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }

    do {
        let minimalTrack = Track(artist: "Daft Punk", title: "One More Time", album: nil, durationSeconds: 0)
        try await client.sendNowPlaying(track: minimalTrack, userToken: "my-lb-token")
        expect("sendNowPlaying succeeds with minimal metadata", true)
    } catch {
        expect("sendNowPlaying succeeds with minimal metadata", false, detail: "Error: \(error)")
    }

    section("ListenBrainz Client · submitScrobble")

    ListenBrainzMockURLProtocol.reset()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    ListenBrainzMockURLProtocol.requestHandler = { request in
        expectEqual("submitScrobble method is POST", request.httpMethod, "POST")
        expectEqual("submitScrobble URL", request.url?.absoluteString, "https://api.listenbrainz.org/1/submit-listens")
        expectEqual("submitScrobble Authorization header", request.value(forHTTPHeaderField: "Authorization"), "Token scrobble-token")

        if let bodyData = getRequestBodyData(request),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            expectEqual("listen_type is single", json["listen_type"] as? String, "single")
            if let payload = json["payload"] as? [[String: Any]], let first = payload.first {
                expectEqual("listened_at timestamp match", first["listened_at"] as? Int, 1_700_000_000)
                if let meta = first["track_metadata"] as? [String: Any] {
                    expectEqual("artist_name match", meta["artist_name"] as? String, "Portishead")
                    expectEqual("track_name match", meta["track_name"] as? String, "Glory Box")
                }
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }

    let track = Track(artist: "Portishead", title: "Glory Box", album: "Dummy", durationSeconds: 300)
    do {
        try await client.submitScrobble(track: track, timestamp: now, userToken: "scrobble-token")
        expect("submitScrobble completes successfully", true)
    } catch {
        expect("submitScrobble completes successfully", false, detail: "Error: \(error)")
    }

    // API error handling - 429 Rate Limit
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let errorJson = #"{"error": "Rate limit exceeded"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
        return (response, Data(errorJson.utf8))
    }

    do {
        try await client.submitScrobble(track: track, timestamp: now, userToken: "scrobble-token")
        expect("submitScrobble throws apiError on 429", false)
    } catch let err as ListenBrainzClient.ClientError {
        if case .apiError(let statusCode, let message) = err {
            expectEqual("submitScrobble 429 status code", statusCode, 429)
            expectEqual("submitScrobble 429 error message", message, "Rate limit exceeded")
            expectTrue("429 rate limit error should retry", err.shouldRetryScrobble)
        } else {
            expect("submitScrobble throws apiError on 429", false, detail: "Got \(err)")
        }
    } catch {
        expect("submitScrobble throws apiError on 429", false, detail: "Unexpected error: \(error)")
    }

    // API error handling - HTTP 500 Server Error
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let errorJson = #"{"error": "Internal Server Error"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (response, Data(errorJson.utf8))
    }

    do {
        try await client.submitScrobble(track: track, timestamp: now, userToken: "scrobble-token")
        expect("submitScrobble throws apiError on 500", false)
    } catch let err as ListenBrainzClient.ClientError {
        if case .apiError(let statusCode, let message) = err {
            expectEqual("submitScrobble 500 status code", statusCode, 500)
            expectEqual("submitScrobble 500 error message", message, "Internal Server Error")
            expectTrue("HTTP 500 server error should retry", err.shouldRetryScrobble)
        } else {
            expect("submitScrobble throws apiError on 500", false, detail: "Got \(err)")
        }
    } catch {
        expect("submitScrobble throws apiError on 500", false, detail: "Unexpected error: \(error)")
    }

    // API error handling - Malformed JSON body
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let malformedData = Data("Invalid Non-JSON Content".utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
        return (response, malformedData)
    }

    do {
        try await client.submitScrobble(track: track, timestamp: now, userToken: "scrobble-token")
        expect("submitScrobble throws apiError on 502 with malformed body", false)
    } catch let err as ListenBrainzClient.ClientError {
        if case .apiError(let statusCode, _) = err {
            expectEqual("submitScrobble 502 status code", statusCode, 502)
            expectTrue("HTTP 502 gateway error should retry", err.shouldRetryScrobble)
        } else {
            expect("submitScrobble throws apiError on 502", false, detail: "Got \(err)")
        }
    } catch {
        expect("submitScrobble throws apiError on 502", false, detail: "Unexpected error: \(error)")
    }

    section("ListenBrainz Client · submitBatch & Chunking Boundaries")

    // 1. Empty batch does 0 network requests
    ListenBrainzMockURLProtocol.reset()
    do {
        try await client.submitBatch(listens: [], userToken: "token")
        expectEqual("empty batch makes 0 HTTP requests", ListenBrainzMockURLProtocol.capturedRequests.count, 0)
    } catch {
        expect("empty batch completes without error", false, detail: "Error: \(error)")
    }

    // 2. Exact boundary tests: 999 items (1 request)
    ListenBrainzMockURLProtocol.reset()
    var boundaryReqCount = 0
    ListenBrainzMockURLProtocol.requestHandler = { request in
        boundaryReqCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }

    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    let sampleTrack = Track(artist: "Massive Attack", title: "Teardrop", album: "Mezzanine", durationSeconds: 330)

    let batch999 = (0..<999).map { i in (track: sampleTrack, timestamp: baseDate.addingTimeInterval(Double(i))) }
    do {
        try await client.submitBatch(listens: batch999, userToken: "token")
        expectEqual("999 items sends exactly 1 request", boundaryReqCount, 1)
    } catch {
        expect("submitBatch 999 items succeeds", false, detail: "Error: \(error)")
    }

    // 3. Exact boundary test: 1000 items (1 request)
    ListenBrainzMockURLProtocol.reset()
    boundaryReqCount = 0
    ListenBrainzMockURLProtocol.requestHandler = { request in
        boundaryReqCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }
    let batch1000 = (0..<1000).map { i in (track: sampleTrack, timestamp: baseDate.addingTimeInterval(Double(i))) }
    do {
        try await client.submitBatch(listens: batch1000, userToken: "token")
        expectEqual("1000 items sends exactly 1 request", boundaryReqCount, 1)
    } catch {
        expect("submitBatch 1000 items succeeds", false, detail: "Error: \(error)")
    }

    // 4. Exact boundary test: 1001 items (2 requests: 1000 and 1)
    ListenBrainzMockURLProtocol.reset()
    boundaryReqCount = 0
    var chunkSizes: [Int] = []
    ListenBrainzMockURLProtocol.requestHandler = { request in
        boundaryReqCount += 1
        if let bodyData = getRequestBodyData(request),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let payload = json["payload"] as? [[String: Any]] {
            chunkSizes.append(payload.count)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }
    let batch1001 = (0..<1001).map { i in (track: sampleTrack, timestamp: baseDate.addingTimeInterval(Double(i))) }
    do {
        try await client.submitBatch(listens: batch1001, userToken: "token")
        expectEqual("1001 items sends 2 requests", boundaryReqCount, 2)
        expectEqual("1001 items chunk 1 size is 1000", chunkSizes.first, 1000)
        expectEqual("1001 items chunk 2 size is 1", chunkSizes.last, 1)
    } catch {
        expect("submitBatch 1001 items succeeds", false, detail: "Error: \(error)")
    }

    // 5. Large batch test: 1050 items
    ListenBrainzMockURLProtocol.reset()
    var batchRequestsCount = 0
    var receivedPayloadCounts: [Int] = []

    ListenBrainzMockURLProtocol.requestHandler = { request in
        batchRequestsCount += 1
        if let bodyData = getRequestBodyData(request),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let payload = json["payload"] as? [[String: Any]] {
            receivedPayloadCounts.append(payload.count)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(#"{"status": "ok"}"#.utf8))
    }

    let largeBatch = (0..<1050).map { i in
        (track: sampleTrack, timestamp: baseDate.addingTimeInterval(Double(i)))
    }

    do {
        try await client.submitBatch(listens: largeBatch, userToken: "batch-token")
        expectEqual("1050 items split into 2 requests", batchRequestsCount, 2)
        expectEqual("1st chunk has 1000 items", receivedPayloadCounts.first, 1000)
        expectEqual("2nd chunk has 50 items", receivedPayloadCounts.last, 50)
    } catch {
        expect("submitBatch 1050 items succeeds", false, detail: "Error: \(error)")
    }

    section("ListenBrainz · Auth Manager")

    // Clear environment before testing AuthManager
    ListenBrainzSessionStore.deleteUserToken()
    UserDefaults.standard.removeObject(forKey: "FastScrobbler.listenbrainz.username")

    let authManager = ListenBrainzAuthManager()

    let isConnInitial = authManager.isConnected
    let tokenInitial = authManager.userToken
    let userInitial = authManager.username

    expect("AuthManager initially not connected", !isConnInitial)
    expect("AuthManager initial userToken is nil", tokenInitial == nil)
    expect("AuthManager initial username is nil", userInitial == nil)

    // 1. Connect with empty token throws AuthError.emptyToken
    do {
        try await authManager.connect(token: "  ")
        expect("connect with empty token throws emptyToken", false)
    } catch let err as ListenBrainzAuthManager.AuthError {
        if case .emptyToken = err {
            expect("connect with empty token throws emptyToken", true)
        } else {
            expect("connect with empty token throws emptyToken", false, detail: "Got \(err)")
        }
    } catch {
        expect("connect with empty token throws emptyToken", false, detail: "Unexpected error: \(error)")
    }

    expectEqual(
        "AuthError.emptyToken localized description",
        ListenBrainzAuthManager.AuthError.emptyToken.localizedDescription,
        "Please enter a ListenBrainz API token."
    )
    expectEqual(
        "AuthError.invalidToken localized description",
        ListenBrainzAuthManager.AuthError.invalidToken.localizedDescription,
        "Invalid ListenBrainz API token."
    )

    // 2. Connect with valid token
    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let json = #"{"code": 200, "message": "Token valid", "user_name": "connected_lb_user", "valid": true}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    do {
        try await authManager.connect(token: "valid-auth-token")
        expect("AuthManager connect succeeds", authManager.isConnected)
        expectEqual("AuthManager userToken updated", authManager.userToken, "valid-auth-token")
        expectEqual("AuthManager username updated", authManager.username, "connected_lb_user")
        expectEqual("Session store updated on connect", ListenBrainzSessionStore.readUserToken(), "valid-auth-token")
        expectEqual("AppGroup username updated on connect", AppGroup.userDefaults.string(forKey: "FastScrobbler.listenbrainz.username"), "connected_lb_user")
    } catch {
        expect("AuthManager connect succeeds", false, detail: "Error: \(error)")
    }

    // URLs & property verification on AuthManager
    expectEqual(
        "tokenPageURL is profile page",
        authManager.tokenPageURL.absoluteString,
        "https://listenbrainz.org/profile/"
    )

    let connectedProfileURL = authManager.profileURL
    expectEqual("profileURL includes username when connected", connectedProfileURL?.absoluteString, "https://listenbrainz.org/user/connected_lb_user")

    // 3. Refresh user info if needed
    AppGroup.userDefaults.removeObject(forKey: "FastScrobbler.listenbrainz.username")
    UserDefaults.standard.removeObject(forKey: "FastScrobbler.listenbrainz.username")
    // Disconnect and reconnect to test refresh when username is nil
    authManager.disconnect()
    ListenBrainzSessionStore.writeUserToken("valid-auth-token")
    let authManagerRefresh = ListenBrainzAuthManager()
    expect("authManagerRefresh initially has nil username", authManagerRefresh.username == nil)

    ListenBrainzMockURLProtocol.reset()
    ListenBrainzMockURLProtocol.requestHandler = { request in
        let json = #"{"code": 200, "message": "Token valid", "user_name": "refreshed_user", "valid": true}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(json.utf8))
    }

    await authManagerRefresh.refreshUserInfoIfNeeded()
    expectEqual("refreshUserInfoIfNeeded fetches and sets username", authManagerRefresh.username, "refreshed_user")

    // 4. Disconnect clears state
    authManagerRefresh.disconnect()
    let isConnAfterDisc = authManagerRefresh.isConnected
    let tokenAfterDisc = authManagerRefresh.userToken
    let userAfterDisc = authManagerRefresh.username
    expect("disconnect clears isConnected", !isConnAfterDisc)
    expect("disconnect clears userToken", tokenAfterDisc == nil)
    expect("disconnect clears username", userAfterDisc == nil)
    expect("session store token cleared after disconnect", ListenBrainzSessionStore.readUserToken() == nil)
    expect("userdefaults username cleared after disconnect", AppGroup.userDefaults.string(forKey: "FastScrobbler.listenbrainz.username") == nil)

    section("ListenBrainz · Auth Manager Profile URL Encoding")

    ListenBrainzSessionStore.deleteUserToken()
    AppGroup.userDefaults.set("user with spaces", forKey: "FastScrobbler.listenbrainz.username")

    let authManager2 = ListenBrainzAuthManager()
    let profileURL = authManager2.profileURL
    expectEqual(
        "profileURL encodes username spaces",
        profileURL?.absoluteString,
        "https://listenbrainz.org/user/user%20with%20spaces"
    )

    if let freshURL = authManager2.freshProfileURL() {
        expect("freshProfileURL contains fs_refresh parameter", freshURL.absoluteString.contains("fs_refresh="))
        expect("freshProfileURL contains base user path", freshURL.absoluteString.contains("https://listenbrainz.org/user/user%20with%20spaces"))
    } else {
        expect("freshProfileURL returns valid URL", false)
    }

    section("ListenBrainz · Listening History Scan Availability")

    ListenBrainzSessionStore.writeUserToken("valid_test_token")
    let lbAuthManager = ListenBrainzAuthManager()
    let lbConnected = lbAuthManager.isConnected
    let lastFMSessionKey: String? = nil
    let hasAnyAccountTest = (lastFMSessionKey != nil) || lbConnected

    expect("ListenBrainz connected state is true when token exists", lbConnected)
    expect("hasAnyAccount returns true when signed into ListenBrainz only", hasAnyAccountTest)

    section("ListenBrainz · Single-Account Backlog Flush Logic")

    struct MockBacklogItem {
        var pendingServices: Set<ScrobbleService>
    }

    func simulateFlushPendingServices(item: inout MockBacklogItem, sessionKey: String?, listenBrainzToken: String?) {
        let hasLastFM = sessionKey?.isEmpty == false
        let hasListenBrainz = listenBrainzToken?.isEmpty == false

        if !hasLastFM {
            item.pendingServices.remove(.lastfm)
        }
        if !hasListenBrainz {
            item.pendingServices.remove(.listenbrainz)
        }
    }

    var lbOnlyItem = MockBacklogItem(pendingServices: [.lastfm, .listenbrainz])
    simulateFlushPendingServices(item: &lbOnlyItem, sessionKey: nil, listenBrainzToken: "valid-token")
    expectEqual("single account ListenBrainz removes lastfm from pendingServices", lbOnlyItem.pendingServices, [.listenbrainz])

    var lastFMOnlyItem = MockBacklogItem(pendingServices: [.lastfm, .listenbrainz])
    simulateFlushPendingServices(item: &lastFMOnlyItem, sessionKey: "valid-session", listenBrainzToken: nil)
    expectEqual("single account Last.fm removes listenbrainz from pendingServices", lastFMOnlyItem.pendingServices, [.lastfm])

    section("ListenBrainz · Disconnected Service Backlog Flush Pruning")

    func simulateFlushItemProcessing(pendingServices: inout Set<ScrobbleService>, sessionKey: String?, listenBrainzToken: String?) -> (isEmpty: Bool, scrobbledInThisFlush: Bool) {
        var scrobbledInThisFlush = false
        let hasLastFM = sessionKey?.isEmpty == false
        let hasListenBrainz = listenBrainzToken?.isEmpty == false

        if !hasLastFM { pendingServices.remove(.lastfm) }
        if !hasListenBrainz { pendingServices.remove(.listenbrainz) }

        // Simulate ListenBrainz API call failing/succeeding
        if pendingServices.contains(.listenbrainz), hasListenBrainz {
            pendingServices.remove(.listenbrainz)
            scrobbledInThisFlush = true
        }

        return (pendingServices.isEmpty, scrobbledInThisFlush)
    }

    var disconnectedItem = MockBacklogItem(pendingServices: [.listenbrainz])
    let (isEmpty, scrobbled) = simulateFlushItemProcessing(pendingServices: &disconnectedItem.pendingServices, sessionKey: nil, listenBrainzToken: nil)
    expect("disconnected service backlog item becomes empty", isEmpty)
    expect("disconnected service backlog item is not marked scrobbledInThisFlush", !scrobbled)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "FastScrobbler.listenbrainz.username")
    AppGroup.userDefaults.removeObject(forKey: "FastScrobbler.listenbrainz.username")
    ListenBrainzSessionStore.deleteUserToken()
    URLProtocol.unregisterClass(ListenBrainzMockURLProtocol.self)
}
