import AppIntents
import Foundation
import MediaPlayer
import OSLog

extension Notification.Name {
    static let openManualScrobble = Notification.Name("FastScrobbler.openManualScrobble")
    static let openHelp = Notification.Name("FastScrobbler.openHelp")
    static let triggerPendingScan = Notification.Name("FastScrobbler.triggerPendingScan")
    static let triggerScrobbleSong = Notification.Name("FastScrobbler.triggerScrobbleSong")
}

enum ShortcutsIntentError: Error, LocalizedError {
    case notConnected
    case mediaLibraryDenied
    case noNowPlaying
    case invalidNowPlayingMetadata

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return NSLocalizedString("Connect Last.fm or ListenBrainz to scrobble.", comment: "")
        case .mediaLibraryDenied:
            return NSLocalizedString("Media Library access is required to read now-playing metadata.", comment: "")
        case .noNowPlaying:
            return NSLocalizedString("No now-playing track.", comment: "")
        case .invalidNowPlayingMetadata:
            return NSLocalizedString("Now-playing track metadata was incomplete.", comment: "")
        }
    }
}

private enum ShortcutsPlaybackReader {
    static func nowPlayingTrackAndPlaybackTime() throws -> (track: Track, playbackTimeSeconds: TimeInterval) {
        let player = MPMusicPlayerController.systemMusicPlayer
        if MPMediaLibrary.authorizationStatus() == .authorized, let item = player.nowPlayingItem {
            let artist = (item.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty && !title.isEmpty {
                let album = item.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let albumArtist = item.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
                let isCompilation = item.isCompilation
                let duration = item.playbackDuration
                let pid = item.persistentID
                let playbackStoreID = item.playbackStoreID

                let track = Track(
                    artist: artist,
                    title: title,
                    album: (album?.isEmpty == false) ? album : nil,
                    albumArtist: (albumArtist?.isEmpty == false) ? albumArtist : nil,
                    durationSeconds: duration > 0 ? duration : nil,
                    persistentID: pid,
                    playbackStoreID: playbackStoreID.isEmpty ? nil : playbackStoreID,
                    isCompilation: isCompilation
                )

                return (track: track, playbackTimeSeconds: max(0, player.currentPlaybackTime))
            }
        }

        if let info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            let artist = ((info[MPMediaItemPropertyArtist] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((info[MPMediaItemPropertyTitle] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, !title.isEmpty else {
                throw ShortcutsIntentError.invalidNowPlayingMetadata
            }

            let album = (info[MPMediaItemPropertyAlbumTitle] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let albumArtist = (info[MPMediaItemPropertyAlbumArtist] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration: TimeInterval? = {
                if let n = info[MPMediaItemPropertyPlaybackDuration] as? NSNumber { return n.doubleValue }
                if let d = info[MPMediaItemPropertyPlaybackDuration] as? Double { return d }
                return nil
            }()
            let elapsed: TimeInterval = {
                if let n = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber { return n.doubleValue }
                if let d = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double { return d }
                return 0
            }()
            let pid: UInt64? = {
                if let n = info[MPMediaItemPropertyPersistentID] as? NSNumber { return n.uint64Value }
                if let u = info[MPMediaItemPropertyPersistentID] as? UInt64 { return u }
                return nil
            }()
            let isCompilation: Bool? = {
                if let n = info[MPMediaItemPropertyIsCompilation] as? NSNumber { return n.boolValue }
                if let b = info[MPMediaItemPropertyIsCompilation] as? Bool { return b }
                return nil
            }()

            let track = Track(
                artist: artist,
                title: title,
                album: (album?.isEmpty == false) ? album : nil,
                albumArtist: (albumArtist?.isEmpty == false) ? albumArtist : nil,
                durationSeconds: (duration ?? 0) > 0 ? duration : nil,
                persistentID: pid,
                playbackStoreID: nil,
                isCompilation: isCompilation
            )
            return (track: track, playbackTimeSeconds: max(0, elapsed))
        }

        if MPMediaLibrary.authorizationStatus() != .authorized {
            throw ShortcutsIntentError.mediaLibraryDenied
        }
        throw ShortcutsIntentError.noNowPlaying
    }
}

struct OpenManualScrobbleIntent: AppIntent {
    static let title: LocalizedStringResource = "Manual Scrobble"
    static let description = IntentDescription("Opens the Manual Scrobble screen in FastScrobbler.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        AppSettings.requestPendingManualScrobbleLaunch()
        await MainActor.run {
            NotificationCenter.default.post(name: .openManualScrobble, object: nil)
        }
        return .result()
    }
}

enum ListeningHistoryReviewLaunchTarget: String, AppEnum {
    case reviewList

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Listening History Review")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .reviewList: DisplayRepresentation("Review List")
    ]
}

struct OpenListeningHistoryReviewIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Listening History Review"
    static let description = IntentDescription("Opens the Listening History review list in FastScrobbler.")

    @Parameter(title: "Target")
    var target: ListeningHistoryReviewLaunchTarget

    init() {
        target = .reviewList
    }

    init(target: ListeningHistoryReviewLaunchTarget) {
        self.target = target
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppSettings.requestOpeningListeningHistoryReview()
        ControlWidgetStatusStore.markSuccess(.scanListeningHistory, duration: 1)
        return .result(
            dialog: IntentDialog(
                stringLiteral: NSLocalizedString(
                    "Opening the Listening History review list in FastScrobbler.",
                    comment: ""
                )
            )
        )
    }
}

struct SendNowPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Now Playing"
    static let description = IntentDescription("Sends the currently playing track to Last.fm or ListenBrainz as \"Now Playing\".")
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "FastScrobbler", category: "SendNowPlayingIntent")

        let sessionKey = LastFMSessionStore.readSessionKey()
        let listenBrainzToken = ListenBrainzSessionStore.readUserToken()

        guard sessionKey != nil || (listenBrainzToken != nil && !listenBrainzToken!.isEmpty) else {
            throw ShortcutsIntentError.notConnected
        }

        ControlWidgetStatusStore.markInProgress(.sendNowPlaying)

        let track = try ShortcutsPlaybackReader.nowPlayingTrackAndPlaybackTime().track
        let trackToSend = track.applyingProScrobblePreferences()

        async let lastFMTask: Result<Void, Error>? = {
            guard let sessionKey, let client = try? LastFMClient() else { return nil }
            do {
                try await client.updateNowPlaying(track: trackToSend, sessionKey: sessionKey)
                return .success(())
            } catch {
                logger.warning("Last.fm updateNowPlaying failed: \(error.localizedDescription, privacy: .public)")
                return .failure(error)
            }
        }()

        async let listenBrainzTask: Result<Void, Error>? = {
            guard let listenBrainzToken, !listenBrainzToken.isEmpty else { return nil }
            do {
                try await ListenBrainzClient().sendNowPlaying(track: trackToSend, userToken: listenBrainzToken)
                return .success(())
            } catch {
                logger.warning("ListenBrainz updateNowPlaying failed: \(error.localizedDescription, privacy: .public)")
                return .failure(error)
            }
        }()

        let (lastFMResult, listenBrainzResult) = await (lastFMTask, listenBrainzTask)

        var lastError: Error?
        var sentAny = false

        if let lastFMResult {
            switch lastFMResult {
            case .success:
                sentAny = true
            case .failure(let error):
                lastError = error
            }
        }

        if let listenBrainzResult {
            switch listenBrainzResult {
            case .success:
                sentAny = true
            case .failure(let error):
                if lastError == nil { lastError = error }
            }
        }

        if sentAny {
            ControlWidgetStatusStore.markSuccess(.sendNowPlaying, duration: 1)
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String.localizedStringWithFormat(
                        NSLocalizedString("Sent now playing: %@ — %@", comment: ""),
                        trackToSend.artist,
                        trackToSend.title
                    )
                )
            )
        } else {
            ControlWidgetStatusStore.clear(.sendNowPlaying)
            if let error = lastError {
                throw error
            } else {
                throw ShortcutsIntentError.notConnected
            }
        }
    }
}

struct ScrobbleSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Scrobble Song"
    static let description = IntentDescription("Scrobbles the currently playing track to Last.fm or ListenBrainz.")
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleSongIntent")

        let sessionKey = LastFMSessionStore.readSessionKey()
        let listenBrainzToken = ListenBrainzSessionStore.readUserToken()

        guard sessionKey != nil || (listenBrainzToken != nil && !listenBrainzToken!.isEmpty) else {
            throw ShortcutsIntentError.notConnected
        }

        ControlWidgetStatusStore.markInProgress(.scrobbleSong)

        let now = Date()
        let (track, _) = try ShortcutsPlaybackReader.nowPlayingTrackAndPlaybackTime()
        let scrobbleTrack = track.applyingProScrobblePreferences()
        let ts = max(1, Int(now.timeIntervalSince1970.rounded(.down)))

        var activeServices: Set<ScrobbleService> = []
        if sessionKey != nil { activeServices.insert(.lastfm) }
        if listenBrainzToken != nil && !listenBrainzToken!.isEmpty { activeServices.insert(.listenbrainz) }

        async let lastFMTask: (failed: Bool, error: Error?)? = {
            guard activeServices.contains(.lastfm), let sessionKey, let client = try? LastFMClient() else { return nil }
            do {
                try await client.scrobble(track: scrobbleTrack, sessionKey: sessionKey, startTimestamp: ts)
                return (failed: false, error: nil)
            } catch {
                logger.warning("Last.fm scrobble failed: \(error.localizedDescription, privacy: .public)")
                return (failed: true, error: error)
            }
        }()

        async let listenBrainzTask: (failed: Bool, error: Error?)? = {
            guard activeServices.contains(.listenbrainz), let listenBrainzToken, !listenBrainzToken.isEmpty else { return nil }
            do {
                try await ListenBrainzClient().submitScrobble(
                    track: scrobbleTrack,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                    userToken: listenBrainzToken
                )
                return (failed: false, error: nil)
            } catch {
                logger.warning("ListenBrainz scrobble failed: \(error.localizedDescription, privacy: .public)")
                return (failed: true, error: error)
            }
        }()

        let (lastFMOutcome, listenBrainzOutcome) = await (lastFMTask, listenBrainzTask)

        var failedServices: Set<ScrobbleService> = []
        var lastFMError: Error?

        if let lastFMOutcome {
            if lastFMOutcome.failed {
                failedServices.insert(.lastfm)
                lastFMError = lastFMOutcome.error
            }
        }

        if let listenBrainzOutcome {
            if listenBrainzOutcome.failed {
                failedServices.insert(.listenbrainz)
            }
        }

        let succeededServices = activeServices.subtracting(failedServices)
        if !succeededServices.isEmpty {
            await MainActor.run {
                ScrobbleLogStore.shared.record(track: scrobbleTrack, startTimestamp: ts, source: .live)
            }
            ControlWidgetStatusStore.markSuccess(.scrobbleSong, duration: 1)
        } else {
            ControlWidgetStatusStore.clear(.scrobbleSong)
        }

        if !failedServices.isEmpty {
            let sampleError = lastFMError ?? ListenBrainzClient.ClientError.invalidResponse
            let preventDuplicates = ProSettings.preventDuplicateScrobblesEnabled()
            await ScrobbleBacklog.shared.enqueue(
                track: scrobbleTrack,
                startTimestamp: ts,
                origin: .live,
                wasAppleMusicFavorite: false,
                pendingServices: failedServices,
                allowExactDuplicates: !preventDuplicates
            )
            if succeededServices.isEmpty {
                throw sampleError
            }
        }

        return .result(
            dialog: IntentDialog(
                stringLiteral: String.localizedStringWithFormat(
                    NSLocalizedString("Scrobbled: %@ — %@", comment: ""),
                    scrobbleTrack.artist,
                    scrobbleTrack.title
                )
            )
        )
    }
}

struct ScanListeningHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan History"
    static let description = IntentDescription("Scans Listening History for missed scrobbles.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        guard LastFMSessionStore.readSessionKey() != nil || ListenBrainzSessionStore.readUserToken() != nil else {
            throw ShortcutsIntentError.notConnected
        }

        ControlWidgetStatusStore.markInProgress(.scanListeningHistory)
        let request: AppSettings.PendingListeningHistoryLaunchRequest =
            AppSettings.listeningHistoryRequireConfirmationEnabled() ? .scanAndOpenReview : .scanAndShowResult
        AppSettings.requestPendingListeningHistoryLaunch(request)
        ControlWidgetStatusStore.markSuccess(.scanListeningHistory, duration: 1)
        return .result()
    }
}

@available(iOS 16.0, *)
struct FastScrobblerShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScrobbleSongIntent(),
            phrases: [
                "Scrobble song in \(.applicationName)",
                "Scrobble now in \(.applicationName)",
                "Scrobble this track in \(.applicationName)",
            ],
            shortTitle: "Scrobble Song",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: SendNowPlayingIntent(),
            phrases: [
                "Send now playing in \(.applicationName)",
                "Update now playing in \(.applicationName)",
            ],
            shortTitle: "Send Now Playing",
            systemImageName: "music.note"
        )

        AppShortcut(
            intent: OpenManualScrobbleIntent(),
            phrases: [
                "Manual scrobble in \(.applicationName)",
                "Open manual scrobble in \(.applicationName)",
            ],
            shortTitle: "Manual Scrobble",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: ScanListeningHistoryIntent(),
            phrases: [
                "Scan listening history in \(.applicationName)",
                "Scan history in \(.applicationName)",
            ],
            shortTitle: "Scan History",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
