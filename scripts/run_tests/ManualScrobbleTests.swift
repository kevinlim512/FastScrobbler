import Foundation

func runManualScrobbleTests() {
    // ─── Manual Scrobble — input trimming and metadata assembly ──────────────────
    // Replicates submitManualScrobble field-trimming logic from ScrobbleEngine.swift.
    // Whitespace is stripped; blank optional fields become nil.

    section("Manual Scrobble · Input trimming and metadata assembly")

    struct ManualScrobbleInput {
        let artist: String
        let title: String
        let album: String?
        let albumArtist: String?
        let timestamp: Int
    }

    func buildManualScrobbleTrack(artist: String, title: String, album: String?, albumArtist: String?, timestamp: Int) -> ManualScrobbleInput {
        let trimmedAlbum = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbumArtist = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ManualScrobbleInput(
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            album: (trimmedAlbum?.isEmpty == false) ? trimmedAlbum : nil,
            albumArtist: (trimmedAlbumArtist?.isEmpty == false) ? trimmedAlbumArtist : nil,
            timestamp: timestamp
        )
    }

    let ms1 = buildManualScrobbleTrack(artist: "  The Beatles  ", title: "  Hey Jude  ", album: nil, albumArtist: nil, timestamp: 1000)
    expect("artist whitespace trimmed",     ms1.artist == "The Beatles", detail: "got '\(ms1.artist)'")
    expect("title whitespace trimmed",      ms1.title == "Hey Jude",     detail: "got '\(ms1.title)'")
    expect("nil album stays nil",           ms1.album == nil)

    let ms2 = buildManualScrobbleTrack(artist: "Artist", title: "Song", album: "   ", albumArtist: "   ", timestamp: 1000)
    expect("blank album becomes nil",       ms2.album == nil,       detail: "got '\(ms2.album ?? "nil")'")
    expect("blank albumArtist becomes nil", ms2.albumArtist == nil, detail: "got '\(ms2.albumArtist ?? "nil")'")

    let ms3 = buildManualScrobbleTrack(artist: "Artist", title: "Song", album: "  White Album  ", albumArtist: "  The Beatles  ", timestamp: 1000)
    expect("album whitespace trimmed",       ms3.album == "White Album",   detail: "got '\(ms3.album ?? "nil")'")
    expect("albumArtist whitespace trimmed", ms3.albumArtist == "The Beatles", detail: "got '\(ms3.albumArtist ?? "nil")'")

    section("Manual Scrobble · Pro metadata preferences")

    struct SimTrack {
        var artist: String
        var title: String
        var album: String?
        var albumArtist: String?
    }

    func applyAlbumArtistPreference(_ track: SimTrack, enabled: Bool) -> SimTrack {
        guard enabled else { return track }
        guard let albumArtist = track.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !albumArtist.isEmpty else {
            return track
        }
        guard albumArtist.compare("Various Artists", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else {
            return track
        }

        var copy = track
        copy.artist = albumArtist
        copy.albumArtist = nil
        return copy
    }

    let manualTrackWithAlbumArtist = SimTrack(
        artist: "Track Artist",
        title: "Song",
        album: "Album",
        albumArtist: "Album Artist"
    )
    let transformedManualTrack = applyAlbumArtistPreference(manualTrackWithAlbumArtist, enabled: true)
    expect("manual scrobble uses albumArtist as artist when enabled", transformedManualTrack.artist == "Album Artist", detail: "got '\(transformedManualTrack.artist)'")
    expect("manual scrobble clears albumArtist metadata after substitution", transformedManualTrack.albumArtist == nil, detail: "got '\(transformedManualTrack.albumArtist ?? "nil")'")

    let manualVariousArtistsTrack = SimTrack(
        artist: "Track Artist",
        title: "Song",
        album: "Compilation",
        albumArtist: "Various Artists"
    )
    let unchangedVariousArtistsTrack = applyAlbumArtistPreference(manualVariousArtistsTrack, enabled: true)
    expect("manual scrobble leaves 'Various Artists' unchanged", unchangedVariousArtistsTrack.artist == "Track Artist", detail: "got '\(unchangedVariousArtistsTrack.artist)'")

    // ─── Manual Scrobble — canSubmit validation ────────────────────────────────────
    // Replicates ManualScrobbleView.canSubmit logic.

    section("Manual Scrobble · canSubmit validation")

    func canSubmit(artist: String, title: String, isSubmitting: Bool, isSubmitted: Bool) -> Bool {
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting &&
        !isSubmitted
    }

    expect("valid artist+title is submittable",         canSubmit(artist: "A", title: "T", isSubmitting: false, isSubmitted: false))
    expect("empty artist blocks submit",                !canSubmit(artist: "",  title: "T", isSubmitting: false, isSubmitted: false))
    expect("whitespace-only artist blocks submit",      !canSubmit(artist: "  ", title: "T", isSubmitting: false, isSubmitted: false))
    expect("empty title blocks submit",                 !canSubmit(artist: "A", title: "",  isSubmitting: false, isSubmitted: false))
    expect("whitespace-only title blocks submit",       !canSubmit(artist: "A", title: "  ", isSubmitting: false, isSubmitted: false))
    expect("isSubmitting=true blocks submit",           !canSubmit(artist: "A", title: "T", isSubmitting: true,  isSubmitted: false))
    expect("isSubmitted=true blocks submit",            !canSubmit(artist: "A", title: "T", isSubmitting: false, isSubmitted: true))
    expect("both empty blocks submit",                  !canSubmit(artist: "",  title: "",  isSubmitting: false, isSubmitted: false))

    // ─── Manual Scrobble — timestamp selection ────────────────────────────────────
    // Replicates ManualScrobbleView.timestamp computed property.

    section("Manual Scrobble · Timestamp selection")

    func computeTimestamp(useCustom: Bool, customDate: Date, now: Date) -> Int {
        let date = useCustom ? customDate : now
        return Int(date.timeIntervalSince1970)
    }

    let tsNow = Date()
    let tsCustom = tsNow.addingTimeInterval(-3600)  // 1 hour ago

    expect("useCustom=false uses now",        computeTimestamp(useCustom: false, customDate: tsCustom, now: tsNow) == Int(tsNow.timeIntervalSince1970))
    expect("useCustom=true uses customDate",  computeTimestamp(useCustom: true,  customDate: tsCustom, now: tsNow) == Int(tsCustom.timeIntervalSince1970))
    expect("timestamp is Unix epoch (Int)",   computeTimestamp(useCustom: false, customDate: tsCustom, now: tsNow) > 1_000_000_000)

    let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: tsNow) ?? tsNow
    expect("two-weeks-ago boundary is within allowed range",
           computeTimestamp(useCustom: true, customDate: twoWeeksAgo, now: tsNow) >= Int(twoWeeksAgo.timeIntervalSince1970))

    // ─── Manual Scrobble — Batch Quantity Generation ─────────────────────────────
    // Replicates submitManualScrobble batch item timestamp calculations.

    section("Manual Scrobble · Batch Quantity Generation")

    func generateBatchItems(baseTimestamp: Int, quantity: Int) -> [(timestamp: Int, index: Int)] {
        let clamped = max(1, min(5, quantity))
        return (0..<clamped).map { i in (timestamp: baseTimestamp + i, index: i) }
    }

    let b1 = generateBatchItems(baseTimestamp: 1_700_000_000, quantity: 1)
    expect("quantity 1 produces 1 item", b1.count == 1)
    expect("quantity 1 item timestamp matches base", b1.first?.timestamp == 1_700_000_000)

    let b5 = generateBatchItems(baseTimestamp: 1_700_000_000, quantity: 5)
    expect("quantity 5 produces 5 items", b5.count == 5)
    expect("quantity 5 timestamps are incremented by 1 sec", b5.map { $0.timestamp } == [1_700_000_000, 1_700_000_001, 1_700_000_002, 1_700_000_003, 1_700_000_004])

    let bClampUpper = generateBatchItems(baseTimestamp: 1_700_000_000, quantity: 10)
    expect("quantity > 5 is clamped to 5", bClampUpper.count == 5)

    let bClampLower = generateBatchItems(baseTimestamp: 1_700_000_000, quantity: 0)
    expect("quantity < 1 is clamped to 1", bClampLower.count == 1)

    // ─── Manual Scrobble · Consecutive Log Grouping ─────────────────────────────

    section("Manual Scrobble · Consecutive Log Grouping")

    struct SimManualLogItem {
        let id: UUID
        let artist: String
        let title: String
        let dedupeKey: String
    }

    let itemA1 = SimManualLogItem(id: UUID(), artist: "Beyoncé", title: "Halo", dedupeKey: "beyoncé|halo")
    let itemA2 = SimManualLogItem(id: UUID(), artist: "Beyoncé", title: "Halo", dedupeKey: "beyoncé|halo")
    let itemA3 = SimManualLogItem(id: UUID(), artist: "Beyoncé", title: "Halo", dedupeKey: "beyoncé|halo")
    let itemB = SimManualLogItem(id: UUID(), artist: "Adele", title: "Hello", dedupeKey: "adele|hello")
    let itemA4 = SimManualLogItem(id: UUID(), artist: "Beyoncé", title: "Halo", dedupeKey: "beyoncé|halo")

    let groupedLog = ConsecutivePlayGrouper.groups(
        from: [itemA1, itemA2, itemA3, itemB, itemA4],
        shouldGroup: { _ in true },
        dedupeKey: \.dedupeKey,
        memberID: \.id
    )

    expect("consecutive manual log entries collapse into groups", groupedLog.count == 3)
    expect("first group has count 3 for Beyoncé - Halo", groupedLog[0].count == 3)
    expect("second group has count 1 for Adele - Hello", groupedLog[1].count == 1)
    expect("third group has count 1 for non-consecutive Beyoncé - Halo", groupedLog[2].count == 1)

    // ─── Current-track manual scrobble timestamp avoidance ────────────────────────
    // Replicates ScrobbleEngine current-track manual timestamp selection.

    section("Current-track manual scrobble · Timestamp avoidance")

    var lastManualScrobbleTrackKey: String?
    var lastManualScrobbleBaseTimestamp: Int?
    var lastManualScrobbleTimestamp: Int?

    func currentTrackManualTimestamp(trackKey: String, now: Date) -> Int {
        let baseTimestamp = max(1, Int(now.timeIntervalSince1970.rounded(.down)))
        let timestamp: Int
        if lastManualScrobbleTrackKey == trackKey,
           lastManualScrobbleBaseTimestamp == baseTimestamp,
           let lastTimestamp = lastManualScrobbleTimestamp
        {
            timestamp = max(1, lastTimestamp - 1)
        } else {
            timestamp = baseTimestamp
        }

        lastManualScrobbleTrackKey = trackKey
        lastManualScrobbleBaseTimestamp = baseTimestamp
        lastManualScrobbleTimestamp = timestamp
        return timestamp
    }

    let manualBaseNow = Date(timeIntervalSince1970: 1_700_000_100)

    let mt1 = currentTrackManualTimestamp(trackKey: "track-a", now: manualBaseNow)
    expect("first current-track manual scrobble uses button-press time", mt1 == 1_700_000_100, detail: "got \(mt1)")

    let mt2 = currentTrackManualTimestamp(trackKey: "track-a", now: manualBaseNow)
    expect("same-track duplicate timestamp decrements by 1", mt2 == 1_700_000_099, detail: "got \(mt2)")

    let mt3 = currentTrackManualTimestamp(trackKey: "track-a", now: manualBaseNow.addingTimeInterval(5))
    expect("same track moves back to fresh button-press time in a new second", mt3 == 1_700_000_105, detail: "got \(mt3)")

    let mt4 = currentTrackManualTimestamp(trackKey: "track-b", now: manualBaseNow)
    expect("different track resets duplicate-timestamp guard", mt4 == 1_700_000_100, detail: "got \(mt4)")

    lastManualScrobbleTrackKey = "track-c"
    lastManualScrobbleBaseTimestamp = 1
    lastManualScrobbleTimestamp = 1
    let mt5 = currentTrackManualTimestamp(trackKey: "track-c", now: Date(timeIntervalSince1970: 0))
    expect("duplicate-timestamp decrement floors at 1", mt5 == 1, detail: "got \(mt5)")

    section("Shortcut current-track scrobble · Timestamp selection")

    func shortcutCurrentTrackTimestamp(now: Date) -> Int {
        max(1, Int(now.timeIntervalSince1970.rounded(.down)))
    }

    expectEqual("shortcut current-track scrobble uses button-press time", shortcutCurrentTrackTimestamp(now: manualBaseNow), 1_700_000_100)
    expectEqual("shortcut current-track scrobble matches the first Scrobble Now timestamp", shortcutCurrentTrackTimestamp(now: manualBaseNow), mt1)

    section("Current-track manual scrobble · Pause behavior")

    func canManualCurrentTrackScrobble(isSignedIn: Bool, isUserPaused: Bool) -> Bool {
        guard isSignedIn else { return false }
        return true
    }

    expect("paused state still allows current-track manual scrobble when signed in",
           canManualCurrentTrackScrobble(isSignedIn: true, isUserPaused: true))
    expect("signed-out state still blocks current-track manual scrobble",
           !canManualCurrentTrackScrobble(isSignedIn: false, isUserPaused: true))

    // ─── Manual Scrobble — backlog fallback on failure ────────────────────────────
    // Validates the pattern: on error, enqueue to backlog with .manual origin, then re-throw.

    section("Manual Scrobble · Backlog fallback on submit error")

    enum SimManualScrobbleError: Error { case networkError }
    enum SimScrobbleOrigin: String { case manual, live }
    struct SimBacklogEntry2 { let key: String; let ts: Int; let origin: SimScrobbleOrigin }

    func simulateManualScrobble(
        shouldFail: Bool,
        artist: String, title: String, timestamp: Int,
        backlog: inout [SimBacklogEntry2],
        log: inout [(key: String, ts: Int)]
    ) throws {
        let trackKey = "meta:\(artist.lowercased())|\(title.lowercased())|"
        if shouldFail {
            backlog.append(SimBacklogEntry2(key: trackKey, ts: timestamp, origin: .manual))
            throw SimManualScrobbleError.networkError
        } else {
            log.append((key: trackKey, ts: timestamp))
        }
    }

    var simBacklog: [SimBacklogEntry2] = []
    var simLog: [(key: String, ts: Int)] = []

    // Success path: log is updated, backlog unchanged
    try? simulateManualScrobble(shouldFail: false, artist: "Artist", title: "Song", timestamp: 5000,
                                backlog: &simBacklog, log: &simLog)
    expect("success: scrobble log has entry",   simLog.count == 1, detail: "got \(simLog.count)")
    expect("success: backlog is empty",         simBacklog.isEmpty)

    // Failure path: backlog gets entry, log unchanged
    var didThrow = false
    do {
        try simulateManualScrobble(shouldFail: true, artist: "Artist2", title: "Song2", timestamp: 6000,
                                   backlog: &simBacklog, log: &simLog)
    } catch {
        didThrow = true
    }
    expect("failure: error is re-thrown",               didThrow)
    expect("failure: backlog has entry",                simBacklog.count == 1, detail: "got \(simBacklog.count)")
    expect("failure: backlog entry has manual origin",  simBacklog.first?.origin == .manual)
    expect("failure: scrobble log unchanged (no add)",  simLog.count == 1, detail: "got \(simLog.count)")

    // ─── Manual Scrobble — retry dedupe and ambiguous delivery ──────────────────
    // Mirrors ScrobbleEngine.shouldEnqueueManualRetry(track:timestamp:after:).

    section("Manual Scrobble · Retry dedupe and ambiguous delivery")

    enum SimManualRetryError {
        case transientHTTP(Int)
        case invalidResponse
        case timedOut
        case notConnected
        case ignored(Int?)
    }

    func shouldRetryManualScrobble(_ error: SimManualRetryError) -> Bool {
        switch error {
        case .transientHTTP(let code):
            return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
        case .invalidResponse:
            return true
        case .timedOut, .notConnected:
            return true
        case .ignored(let code):
            return code == 5
        }
    }

    func manualRetryDeliveryIsAmbiguous(_ error: SimManualRetryError) -> Bool {
        switch error {
        case .invalidResponse, .timedOut:
            return true
        case .transientHTTP, .notConnected, .ignored:
            return false
        }
    }

    func shouldEnqueueManualRetry(
        key: String,
        timestamp: Int,
        error: SimManualRetryError,
        backlog: [SimBacklogEntry2],
        log: [(key: String, ts: Int)]
    ) -> Bool {
        guard shouldRetryManualScrobble(error) else { return false }
        guard !manualRetryDeliveryIsAmbiguous(error) else { return false }
        let tolerance = 10
        let alreadyQueued = backlog.contains { $0.key == key && abs($0.ts - timestamp) <= tolerance }
        guard !alreadyQueued else { return false }
        return !log.contains { $0.key == key && abs($0.ts - timestamp) <= tolerance }
    }

    let retryKey = "meta:artist|song|"
    expect("retryable HTTP failure enqueues when no duplicate exists",
           shouldEnqueueManualRetry(key: retryKey, timestamp: 10_000, error: .transientHTTP(503), backlog: [], log: []))
    expect("existing backlog match suppresses retry enqueue",
           !shouldEnqueueManualRetry(key: retryKey, timestamp: 10_005, error: .transientHTTP(503), backlog: [SimBacklogEntry2(key: retryKey, ts: 10_000, origin: .manual)], log: []))
    expect("existing scrobble log match suppresses retry enqueue",
           !shouldEnqueueManualRetry(key: retryKey, timestamp: 10_005, error: .transientHTTP(503), backlog: [], log: [(key: retryKey, ts: 10_000)]))
    expect("timeout is treated as ambiguous delivery and not queued",
           !shouldEnqueueManualRetry(key: retryKey, timestamp: 10_000, error: .timedOut, backlog: [], log: []))
    expect("invalid response is treated as ambiguous delivery and not queued",
           !shouldEnqueueManualRetry(key: retryKey, timestamp: 10_000, error: .invalidResponse, backlog: [], log: []))
    expect("offline failure can queue for later",
           shouldEnqueueManualRetry(key: retryKey, timestamp: 10_000, error: .notConnected, backlog: [], log: []))
    expect("non-retryable ignored scrobble is not queued",
           !shouldEnqueueManualRetry(key: retryKey, timestamp: 10_000, error: .ignored(1), backlog: [], log: []))

    // ─── Scrobble Now — duration and progress bypass validation ─────────────────

    section("Scrobble Now · Duration and progress bypass validation")

    struct SimScrobbleNowTrack {
        let artist: String
        let title: String
        let durationSeconds: Double?
    }

    enum SimPlaybackState { case playing, paused, stopped }

    struct SimScrobbleNowDecision {
        let canScrobble: Bool
        let reason: String?
    }

    func evaluateScrobbleNow(track: SimScrobbleNowTrack, state: SimPlaybackState, playbackTime: Double) -> SimScrobbleNowDecision {
        let trimmedArtist = track.artist.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = track.title.trimmingCharacters(in: .whitespaces)
        if trimmedArtist.isEmpty || trimmedTitle.isEmpty {
            return SimScrobbleNowDecision(canScrobble: false, reason: "Missing required track metadata.")
        }
        // Scrobble Now bypasses playbackState, duration, and threshold checks!
        return SimScrobbleNowDecision(canScrobble: true, reason: nil)
    }

    let tShort = SimScrobbleNowTrack(artist: "Artist", title: "Short Song", durationSeconds: 15.0)
    let tNilDuration = SimScrobbleNowTrack(artist: "Artist", title: "Stream Song", durationSeconds: nil)
    let tZeroDuration = SimScrobbleNowTrack(artist: "Artist", title: "Zero Song", durationSeconds: 0)
    let tBlankArtist = SimScrobbleNowTrack(artist: "   ", title: "Song", durationSeconds: 180.0)

    expect("Scrobble Now allows short track (<30s)", evaluateScrobbleNow(track: tShort, state: .playing, playbackTime: 2.0).canScrobble)
    expect("Scrobble Now allows nil duration track", evaluateScrobbleNow(track: tNilDuration, state: .paused, playbackTime: 0.0).canScrobble)
    expect("Scrobble Now allows zero duration track", evaluateScrobbleNow(track: tZeroDuration, state: .stopped, playbackTime: 0.0).canScrobble)
    expect("Scrobble Now allows paused state at 0s progress", evaluateScrobbleNow(track: tShort, state: .paused, playbackTime: 0.0).canScrobble)
    expect("Scrobble Now blocks blank metadata", !evaluateScrobbleNow(track: tBlankArtist, state: .playing, playbackTime: 10.0).canScrobble)
}
