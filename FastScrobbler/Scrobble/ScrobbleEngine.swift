import Foundation
import OSLog

@MainActor
final class ScrobbleEngine: ObservableObject {
    private static let tickIntervalSeconds: TimeInterval = 3.0

    enum ActivityKeys {
        static let lastTickAt = "FastScrobbler.ScrobbleEngine.lastTickAt"
        static let userPaused = "FastScrobbler.ScrobbleEngine.userPaused"
    }

    private struct PlaybackSession {
        var track: Track
        var startedAt: Date
        var hasSentNowPlaying = false
        var hasScrobbled = false
        var hasLovedOnThisSession: Bool = false
        var accumulatedPlaySeconds: TimeInterval = 0
        var lastPlayObservedAt: Date?
        var lastPlayObservedPlaybackTimeSeconds: TimeInterval?
        var resumeWindowEndsAt: Date?
        var lastNowPlayingAttemptAt: Date?
        var lastScrobbleAttemptAt: Date?
    }

    @Published private(set) var statusText: String = "Idle"
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isUserPaused: Bool = UserDefaults.standard.bool(forKey: ActivityKeys.userPaused)

    private let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleEngine")
    private var session: PlaybackSession?
    private var tickTimer: Timer?
    private var lastLiveActivityEventAt: Date = .distantPast

    private let auth: LastFMAuthManager
    private let observer: AppleMusicNowPlayingObserver
    private let backlog: ScrobbleBacklog
    private let scrobbleLog: ScrobbleLogStore
    private var lastManualScrobbleTrackKey: String?
    private var lastManualScrobbleTimestamp: Int?

    init(
        auth: LastFMAuthManager,
        observer: AppleMusicNowPlayingObserver,
        backlog: ScrobbleBacklog = .shared,
        scrobbleLog: ScrobbleLogStore? = nil
    ) {
        self.auth = auth
        self.observer = observer
        self.backlog = backlog
        self.scrobbleLog = scrobbleLog ?? .shared
    }

    func start() {
        guard !isUserPaused else {
            isRunning = false
            tickTimer?.invalidate()
            tickTimer = nil
            statusText = "Paused"
            Task { @MainActor in
                await LiveActivityManager.shared.update(
                    status: statusText,
                    track: observer.track,
                    lastEventAt: Date(),
                    isActivelyScrobbling: false,
                    throttleSeconds: 0
                )
            }
            return
        }

        if isRunning {
            ensureTickTimer()
            return
        }

        LiveActivityManager.shared.startIfPossible()

        isRunning = true
        ensureTickTimer()
        statusText = "Running"
        Task { @MainActor in
            await LiveActivityManager.shared.update(
                status: "Running",
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )
        }
        Task { @MainActor in
            await tickAsync()
        }
    }

    func pauseForBackground() {
        tickTimer?.invalidate()
        tickTimer = nil

        guard isRunning else { return }
        statusText = "Backgrounded (syncs when iOS allows)"
        Task { @MainActor in
            await LiveActivityManager.shared.update(
                status: statusText,
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false,
                throttleSeconds: 0
            )
        }
    }

    func stop() {
        isRunning = false
        tickTimer?.invalidate()
        tickTimer = nil
        statusText = "Stopped"
        Task { @MainActor in
            await LiveActivityManager.shared.stop()
        }
    }

    private func ensureTickTimer() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tickAsync()
            }
        }
    }

    func tickAsync() async {
        guard !isUserPaused else {
            statusText = "Paused"
            await LiveActivityManager.shared.update(
                status: statusText,
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false,
                throttleSeconds: 0
            )
            return
        }

        guard let sessionKey = auth.sessionKey else {
            statusText = "Connect Last.fm to scrobble."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false
            )
            return
        }

        let now = Date()
        let previousTickAt = UserDefaults.standard.object(forKey: ActivityKeys.lastTickAt) as? Date
        UserDefaults.standard.set(now, forKey: ActivityKeys.lastTickAt)
        let gapSeconds: TimeInterval? = previousTickAt.map { now.timeIntervalSince($0) }

        guard let current = observer.track else {
            await finalizeIfNeeded(sessionKey: sessionKey, transitionAt: now)
            statusText = "No now-playing track."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: nil,
                lastEventAt: Date(),
                isActivelyScrobbling: false
            )
            return
        }

        if session?.track.dedupeKey != current.dedupeKey {
            let playbackTime = observer.playbackTimeSeconds
            let startedAt = now.addingTimeInterval(-max(0, playbackTime))
            await finalizeIfNeeded(sessionKey: sessionKey, transitionAt: startedAt)

            var newSession = PlaybackSession(track: current, startedAt: startedAt)
            newSession.accumulatedPlaySeconds = max(0, playbackTime)
            newSession.lastPlayObservedAt = now
            newSession.lastPlayObservedPlaybackTimeSeconds = max(0, playbackTime)
            if let gapSeconds, gapSeconds > 12 {
                newSession.resumeWindowEndsAt = now.addingTimeInterval(12)
            }
            session = newSession
            logger.debug("New session: \(current.artist, privacy: .public) - \(current.title, privacy: .public)")

            lastLiveActivityEventAt = now
            await LiveActivityManager.shared.update(
                status: "Track changed",
                track: current,
                lastEventAt: lastLiveActivityEventAt,
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )
        } else if session?.track != current, var s = session {
            // Metadata can change mid-play (e.g. duration becomes available). Keep the session stable to avoid
            // double-scrobbling, but update the track metadata it displays / scrobbles.
            s.track = current
            session = s
        }

        guard var s = session else { return }

        let playbackTime = max(0, observer.playbackTimeSeconds)
        if let gapSeconds, gapSeconds > 12 {
            s.resumeWindowEndsAt = now.addingTimeInterval(12)
            logger.debug("Execution gap detected (\(gapSeconds, privacy: .public)s). Enabling resume window.")
        }

        // When "Prevent duplicate scrobbles" is OFF, treat a loop/restart of the same track as a new
        // playback session so it can be scrobbled again. Apple Music looping doesn't always emit a
        // now-playing item change for the same track, so the app detects a wrap by watching playbackTime.
        if !ProSettings.preventDuplicateScrobblesEnabled(),
           s.resumeWindowEndsAt == nil,
           (gapSeconds.map { $0 <= 12 } ?? true),
           let lastPlaybackTime = s.lastPlayObservedPlaybackTimeSeconds,
           lastPlaybackTime > 15,
           playbackTime <= 5,
           lastPlaybackTime > playbackTime
        {
            let drop = lastPlaybackTime - playbackTime
            let duration = s.track.durationSeconds ?? 0
            let dropThreshold: TimeInterval = duration > 0 ? max(10, duration * 0.5) : 30

            if drop >= dropThreshold {
                let restartedAt = now.addingTimeInterval(-playbackTime)
                var newSession = PlaybackSession(track: s.track, startedAt: restartedAt)
                newSession.accumulatedPlaySeconds = playbackTime
                newSession.lastPlayObservedAt = now
                newSession.lastPlayObservedPlaybackTimeSeconds = playbackTime
                s = newSession

                lastLiveActivityEventAt = now
                await LiveActivityManager.shared.update(
                    status: "Track restarted",
                    track: s.track,
                    lastEventAt: lastLiveActivityEventAt,
                    isActivelyScrobbling: true,
                    throttleSeconds: 0
                )
            }
        }

        if let lastAt = s.lastPlayObservedAt, let lastPlaybackTime = s.lastPlayObservedPlaybackTimeSeconds {
            let wallDelta = now.timeIntervalSince(lastAt)
            let playbackDelta = playbackTime - lastPlaybackTime

            if wallDelta > 0, playbackDelta > 0 {
                // Use playback progression, capped by wall time, to handle normal playback and background/suspension gaps.
                // This avoids being gamed by seeking (large playback jumps in small wall time).
                s.accumulatedPlaySeconds += min(playbackDelta, wallDelta)
            }
        }

        // After a cold start / long suspension, Apple Music can report an initial playbackTime of 0 that then
        // "snaps" to the real value on a subsequent tick. If the app created the session from that stale sample,
        // its startedAt (and therefore scrobble timestamp) will be wrong and can cause duplicate scrobbles.
        let sessionAge = max(0, now.timeIntervalSince(s.startedAt))
        if sessionAge < 20, playbackTime > sessionAge + 15 {
            let candidateStartedAt = now.addingTimeInterval(-playbackTime)
            let correctionSeconds = s.startedAt.timeIntervalSince(candidateStartedAt)
            if correctionSeconds > 10 {
                logger.debug(
                    "Correcting startedAt by \(correctionSeconds, privacy: .public)s (age \(sessionAge, privacy: .public)s, playback \(playbackTime, privacy: .public)s)."
                )
                s.startedAt = candidateStartedAt
                if playbackTime > s.accumulatedPlaySeconds {
                    s.accumulatedPlaySeconds = playbackTime
                }
            }
        }

        // If the app just returned from a long suspension, the first playbackTime sample can be stale (e.g. 0),
        // then "snap" to the real value on the next tick. During a short resume window, trust playbackTime
        // as a floor so it doesn't miss the scrobble threshold due to sampling glitches.
        if let endsAt = s.resumeWindowEndsAt, now <= endsAt {
            if playbackTime > s.accumulatedPlaySeconds {
                if playbackTime - s.accumulatedPlaySeconds > 5 {
                    logger.debug(
                        "Resume window catch-up: accumulated \(s.accumulatedPlaySeconds, privacy: .public)s -> \(playbackTime, privacy: .public)s"
                    )
                }
                s.accumulatedPlaySeconds = playbackTime
            }
        } else if s.resumeWindowEndsAt != nil {
            s.resumeWindowEndsAt = nil
        }

        s.lastPlayObservedAt = now
        s.lastPlayObservedPlaybackTimeSeconds = playbackTime

        do {
            let client = try LastFMClient()
            s = await self.maybeSendNowPlaying(s, sessionKey: sessionKey, client: client)
            s = await self.maybeScrobble(s, sessionKey: sessionKey, client: client)
            session = s
            statusText = renderStatus(s)
            await LiveActivityManager.shared.update(
                status: statusText,
                track: s.track,
                lastEventAt: lastLiveActivityEventAt == .distantPast ? Date() : lastLiveActivityEventAt,
                isActivelyScrobbling: true
            )
        } catch {
            statusText = error.localizedDescription
            await LiveActivityManager.shared.update(
                status: statusText,
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false
            )
        }
    }

    func scrobbleNow(force: Bool = true) async {
        let now = Date()

        guard let sessionKey = auth.sessionKey else {
            statusText = "Connect Last.fm to scrobble."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: observer.track,
                lastEventAt: now,
                isActivelyScrobbling: false
            )
            return
        }

        guard let current = observer.track else {
            statusText = "No now-playing track."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: nil,
                lastEventAt: now,
                isActivelyScrobbling: false
            )
            return
        }

        let trackToScrobble = trackForScrobble(current)
        let shouldLoveOnLastFM = observer.track?.favoriteID == current.favoriteID && observer.isNowPlayingLovedInAppleMusic == true

        if ProSettings.preventDuplicateScrobblesEnabled(),
           let s = session,
           s.track.dedupeKey == current.dedupeKey,
           s.hasScrobbled
        {
            statusText = "Already scrobbled."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: current,
                lastEventAt: now,
                isActivelyScrobbling: true
            )
            return
        }

        statusText = "Scrobbling…"
        await LiveActivityManager.shared.update(
            status: statusText,
            track: current,
            lastEventAt: now,
            isActivelyScrobbling: true,
            throttleSeconds: 0
        )

        let playbackTime = max(0, observer.playbackTimeSeconds)
        let startedAt: Date = {
            if let s = session, s.track.dedupeKey == current.dedupeKey { return s.startedAt }
            return now.addingTimeInterval(-playbackTime)
        }()
        let ts = manualScrobbleTimestamp(for: trackToScrobble, startedAt: startedAt, now: now)
        let dedupeToleranceSeconds = 10

        let alreadyHandled: Bool
        if ProSettings.preventDuplicateScrobblesEnabled() {
            alreadyHandled =
                await backlog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds) ||
                scrobbleLog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds)
        } else {
            alreadyHandled = false
        }

        if alreadyHandled {
            if var s = session, s.track.dedupeKey == current.dedupeKey {
                s.hasScrobbled = true
                session = s
            }
            statusText = "Already scrobbled."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: current,
                lastEventAt: now,
                isActivelyScrobbling: true
            )
            return
        }

        do {
            let client = try LastFMClient()
            if force {
                try await client.scrobble(track: trackToScrobble, sessionKey: sessionKey, startTimestamp: ts)
                if observer.playbackState == .playing, observer.track?.dedupeKey == current.dedupeKey {
                    do {
                        try await client.updateNowPlaying(track: trackToScrobble, sessionKey: sessionKey)
                    } catch {
                        logger.warning("updateNowPlaying (post-manual-scrobble) failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } else if var s = session, s.track == current {
                s = await maybeScrobble(s, sessionKey: sessionKey, client: client)
                session = s
                return
            } else {
                var s = PlaybackSession(track: current, startedAt: startedAt)
                s.accumulatedPlaySeconds = playbackTime
                s.lastPlayObservedAt = now
                s.lastPlayObservedPlaybackTimeSeconds = playbackTime
                s = await maybeScrobble(s, sessionKey: sessionKey, client: client)
                session = s
                statusText = renderStatus(s)
                return
            }

            var s: PlaybackSession = {
                if var s = session, s.track == current {
                    s.hasScrobbled = true
                    return s
                }
                var s = PlaybackSession(track: current, startedAt: startedAt)
                s.accumulatedPlaySeconds = playbackTime
                s.lastPlayObservedAt = now
                s.lastPlayObservedPlaybackTimeSeconds = playbackTime
                s.hasScrobbled = true
                return s
            }()

            s = await maybeLoveOnLastFMAfterScrobble(
                s,
                trackToLove: trackToScrobble,
                sessionKey: sessionKey,
                client: client,
                wasAppleMusicFavorite: shouldLoveOnLastFM
            )
            session = s

            scrobbleLog.record(
                track: trackToScrobble,
                startTimestamp: ts,
                source: .live,
                lovedOnLastFM: s.hasLovedOnThisSession
            )

            lastLiveActivityEventAt = Date()
            statusText = s.hasLovedOnThisSession ? "Loved on Last.fm" : "Scrobbled"
            await LiveActivityManager.shared.update(
                status: statusText,
                track: current,
                lastEventAt: lastLiveActivityEventAt,
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )
        } catch {
            logger.warning("manual scrobble failed: \(error.localizedDescription, privacy: .public)")
            let shouldEnqueue: Bool
            if ProSettings.preventDuplicateScrobblesEnabled() {
                shouldEnqueue =
                    !(await backlog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds)) &&
                    !scrobbleLog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds)
            } else {
                shouldEnqueue = true
            }
            if shouldEnqueue {
                await backlog.enqueue(track: trackToScrobble, startTimestamp: ts, origin: .live, wasAppleMusicFavorite: shouldLoveOnLastFM)
            }
            BackgroundTaskManager.shared.scheduleAppRefresh()
            BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
            statusText = "Failed to scrobble now; queued for retry."
            await LiveActivityManager.shared.update(
                status: statusText,
                track: current,
                lastEventAt: Date(),
                isActivelyScrobbling: false
            )
        }
    }

    private func renderStatus(_ s: PlaybackSession) -> String {
        let played = Int(s.accumulatedPlaySeconds.rounded())
        var bits = ["\(s.track.artist) - \(s.track.title)", "played \(played)s"]
        if s.hasSentNowPlaying { bits.append("now playing sent") }
        if s.hasScrobbled { bits.append("scrobbled") }
        if s.hasLovedOnThisSession { bits.append("loved") }
        return bits.joined(separator: " | ")
    }

    private func manualScrobbleTimestamp(for track: Track, startedAt: Date, now: Date) -> Int {
        let baseTimestamp = Int(startedAt.timeIntervalSince1970.rounded(.down))
        guard !ProSettings.preventDuplicateScrobblesEnabled() else {
            lastManualScrobbleTrackKey = nil
            lastManualScrobbleTimestamp = nil
            return baseTimestamp
        }

        let nowTimestamp = Int(now.timeIntervalSince1970.rounded(.down))
        let preferredTimestamp = max(baseTimestamp, nowTimestamp)

        let timestamp: Int
        if lastManualScrobbleTrackKey == track.dedupeKey,
           let lastTimestamp = lastManualScrobbleTimestamp
        {
            if preferredTimestamp > lastTimestamp {
                timestamp = preferredTimestamp
            } else {
                timestamp = max(1, lastTimestamp - 1)
            }
        } else {
            timestamp = preferredTimestamp
        }

        lastManualScrobbleTrackKey = track.dedupeKey
        lastManualScrobbleTimestamp = timestamp
        return timestamp
    }

    private func maybeLoveOnLastFMAfterScrobble(
        _ s: PlaybackSession,
        trackToLove: Track,
        sessionKey: String,
        client: LastFMClient,
        wasAppleMusicFavorite: Bool
    ) async -> PlaybackSession {
        var s = s
        guard wasAppleMusicFavorite else { return s }
        guard ProSettings.loveOnFavoriteEnabled() else { return s }
        guard !s.hasLovedOnThisSession else { return s }

        do {
            try await client.love(track: trackToLove, sessionKey: sessionKey)
            s.hasLovedOnThisSession = true
            lastLiveActivityEventAt = Date()
            await LiveActivityManager.shared.update(
                status: "Loved on Last.fm",
                track: s.track,
                lastEventAt: lastLiveActivityEventAt,
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )
        } catch {
            // Keep silent; favouriting stays in Apple Music even if Last.fm call fails.
        }

        return s
    }

    private func maybeSendNowPlaying(_ s: PlaybackSession, sessionKey: String, client: LastFMClient) async -> PlaybackSession {
        var s = s
        guard !s.hasSentNowPlaying else { return s }
        guard observer.playbackState == .playing else { return s }

        let now = Date()
        if let last = s.lastNowPlayingAttemptAt, now.timeIntervalSince(last) < 10 { return s }
        s.lastNowPlayingAttemptAt = now

        do {
            try await client.updateNowPlaying(track: trackForScrobble(s.track), sessionKey: sessionKey)
            s.hasSentNowPlaying = true
            lastLiveActivityEventAt = Date()
            await LiveActivityManager.shared.update(
                status: "Now playing",
                track: s.track,
                lastEventAt: lastLiveActivityEventAt,
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )
        } catch {
            logger.warning("updateNowPlaying failed: \(error.localizedDescription, privacy: .public)")
        }
        return s
    }

    private func maybeScrobble(_ s: PlaybackSession, sessionKey: String, client: LastFMClient) async -> PlaybackSession {
        var s = s
        guard !s.hasScrobbled else { return s }
        guard observer.playbackState == .playing || observer.playbackState == .paused || observer.playbackState == .stopped else { return s }

        guard let duration = s.track.durationSeconds, duration > 0 else { return s }
        guard duration >= 30 else { return s } // Tracks that are 30 seconds or shorter are ignored.

        let thresholdFraction = ProSettings.scrobbleThresholdFraction()
        let threshold = duration * thresholdFraction
        guard s.accumulatedPlaySeconds >= threshold else { return s }

        let now = Date()
        if let last = s.lastScrobbleAttemptAt, now.timeIntervalSince(last) < 15 { return s }
        s.lastScrobbleAttemptAt = now

        let shouldLoveOnLastFM = observer.track?.favoriteID == s.track.favoriteID && observer.isNowPlayingLovedInAppleMusic == true

        do {
            let ts = Int(s.startedAt.timeIntervalSince1970.rounded(.down))
            let trackToScrobble = trackForScrobble(s.track)

            let dedupeToleranceSeconds = 10
            let alreadyHandled: Bool
            if ProSettings.preventDuplicateScrobblesEnabled() {
                alreadyHandled =
                    await backlog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds) ||
                    scrobbleLog.containsSimilar(track: trackToScrobble, around: ts, toleranceSeconds: dedupeToleranceSeconds)
            } else {
                alreadyHandled = false
            }
            if alreadyHandled {
                s.hasScrobbled = true
                return s
            }

            try await client.scrobble(track: trackToScrobble, sessionKey: sessionKey, startTimestamp: ts)
            s.hasScrobbled = true
            lastLiveActivityEventAt = Date()
            await LiveActivityManager.shared.update(
                status: "Scrobbled",
                track: s.track,
                lastEventAt: lastLiveActivityEventAt,
                isActivelyScrobbling: true,
                throttleSeconds: 0
            )

            if observer.playbackState == .playing, observer.track?.dedupeKey == s.track.dedupeKey {
                do {
                    try await client.updateNowPlaying(track: trackToScrobble, sessionKey: sessionKey)
                } catch {
                    logger.warning("updateNowPlaying (post-scrobble) failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            s = await maybeLoveOnLastFMAfterScrobble(
                s,
                trackToLove: trackToScrobble,
                sessionKey: sessionKey,
                client: client,
                wasAppleMusicFavorite: shouldLoveOnLastFM
            )

            scrobbleLog.record(
                track: trackToScrobble,
                startTimestamp: ts,
                source: .live,
                lovedOnLastFM: s.hasLovedOnThisSession
            )
        } catch {
            logger.warning("scrobble failed: \(error.localizedDescription, privacy: .public)")
            let ts = Int(s.startedAt.timeIntervalSince1970.rounded(.down))
            let trackToQueue = trackForScrobble(s.track)
            let dedupeToleranceSeconds = 10
            let shouldEnqueue: Bool
            if ProSettings.preventDuplicateScrobblesEnabled() {
                shouldEnqueue =
                    !(await backlog.containsSimilar(track: trackToQueue, around: ts, toleranceSeconds: dedupeToleranceSeconds)) &&
                    !scrobbleLog.containsSimilar(track: trackToQueue, around: ts, toleranceSeconds: dedupeToleranceSeconds)
            } else {
                shouldEnqueue = true
            }
            if shouldEnqueue {
                await backlog.enqueue(track: trackToQueue, startTimestamp: ts, origin: .live, wasAppleMusicFavorite: shouldLoveOnLastFM)
            }
            BackgroundTaskManager.shared.scheduleAppRefresh()
            BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        }
        return s
    }

    private func trackForScrobble(_ track: Track) -> Track {
        track.applyingProScrobblePreferences()
    }

    private func finalizeIfNeeded(sessionKey: String, transitionAt: Date) async {
        guard let s0 = session else { return }
        var s = s0
        guard !s.hasScrobbled else {
            session = nil
            return
        }

        // Track transitions can happen between ticks (especially near the end of a song). Because play time is
        // credited when it observes playbackTime increasing, the last ~tick interval of play can be missed.
        // Add a small, capped catch-up so high thresholds (e.g., 75%) still trigger when the user
        // has genuinely listened through the end.
        if let lastAt = s.lastPlayObservedAt {
            let wallDelta = transitionAt.timeIntervalSince(lastAt)
            if wallDelta > 0 {
                let maxCatchUp = Self.tickIntervalSeconds + 1.0
                s.accumulatedPlaySeconds += min(wallDelta, maxCatchUp)
                if let duration = s.track.durationSeconds, duration > 0 {
                    s.accumulatedPlaySeconds = min(s.accumulatedPlaySeconds, duration)
                }
            }
        }

        // If the user changed tracks and the app has already hit the threshold, attempt a last scrobble.
        do {
            let client = try LastFMClient()
            _ = await maybeScrobble(s, sessionKey: sessionKey, client: client)
        } catch {
            // Keep it silent on finalize.
        }
        session = nil
    }

    func setUserPaused(_ paused: Bool) {
        if isUserPaused == paused { return }
        isUserPaused = paused
        UserDefaults.standard.set(paused, forKey: ActivityKeys.userPaused)

        if paused {
            session = nil
            isRunning = false
            tickTimer?.invalidate()
            tickTimer = nil
            statusText = "Paused"
            Task { @MainActor in
                await LiveActivityManager.shared.update(
                    status: statusText,
                    track: observer.track,
                    lastEventAt: Date(),
                    isActivelyScrobbling: false,
                    throttleSeconds: 0
                )
            }
        } else {
            start()
            Task { @MainActor in
                await tickAsync()
            }
        }
    }
}
