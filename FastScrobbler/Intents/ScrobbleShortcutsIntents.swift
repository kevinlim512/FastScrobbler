import AppIntents
import Foundation
import MediaPlayer
import OSLog

enum ShortcutsIntentError: Error, LocalizedError {
    case notConnected
    case mediaLibraryDenied
    case noNowPlaying
    case invalidNowPlayingMetadata

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect Last.fm to scrobble."
        case .mediaLibraryDenied:
            return "Media Library access is required to read now-playing metadata."
        case .noNowPlaying:
            return "No now-playing track."
        case .invalidNowPlayingMetadata:
            return "Now-playing track metadata was incomplete."
        }
    }
}

private enum ShortcutsPlaybackReader {
    static func nowPlayingTrackAndPlaybackTime() throws -> (track: Track, playbackTimeSeconds: TimeInterval) {
        let player = MPMusicPlayerController.systemMusicPlayer
        if MPMediaLibrary.authorizationStatus() == .authorized, let item = player.nowPlayingItem {
            let artist = (item.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, !title.isEmpty else {
                throw ShortcutsIntentError.invalidNowPlayingMetadata
            }

            let album = item.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let albumArtist = item.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = item.playbackDuration
            let pid = item.persistentID

            let track = Track(
                artist: artist,
                title: title,
                album: (album?.isEmpty == false) ? album : nil,
                albumArtist: (albumArtist?.isEmpty == false) ? albumArtist : nil,
                durationSeconds: duration > 0 ? duration : nil,
                persistentID: pid
            )

            return (track: track, playbackTimeSeconds: max(0, player.currentPlaybackTime))
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

            let track = Track(
                artist: artist,
                title: title,
                album: (album?.isEmpty == false) ? album : nil,
                albumArtist: (albumArtist?.isEmpty == false) ? albumArtist : nil,
                durationSeconds: (duration ?? 0) > 0 ? duration : nil,
                persistentID: pid
            )
            return (track: track, playbackTimeSeconds: max(0, elapsed))
        }

        if MPMediaLibrary.authorizationStatus() != .authorized {
            throw ShortcutsIntentError.mediaLibraryDenied
        }
        throw ShortcutsIntentError.noNowPlaying
    }
}

struct SendNowPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Now Playing"
    static let description = IntentDescription("Sends the currently playing track to Last.fm as “Now Playing”.")
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "FastScrobbler", category: "SendNowPlayingIntent")

        guard let sessionKey = KeychainStore.readString(service: "FastScrobbler", account: "lastfm.sessionKey") else {
            throw ShortcutsIntentError.notConnected
        }

        let track = try ShortcutsPlaybackReader.nowPlayingTrackAndPlaybackTime().track
        let trackToSend = track.applyingProScrobblePreferences()
        let client = try LastFMClient()

        do {
            try await client.updateNowPlaying(track: trackToSend, sessionKey: sessionKey)
            return .result(dialog: "Sent now playing: \(trackToSend.artist) — \(trackToSend.title)")
        } catch {
            logger.warning("updateNowPlaying failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

struct ScrobbleSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Scrobble Song"
    static let description = IntentDescription("Scrobbles the currently playing track to Last.fm.")
    static let openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleSongIntent")

        guard let sessionKey = KeychainStore.readString(service: "FastScrobbler", account: "lastfm.sessionKey") else {
            throw ShortcutsIntentError.notConnected
        }

        let now = Date()
        let (track, playbackTimeSeconds) = try ShortcutsPlaybackReader.nowPlayingTrackAndPlaybackTime()
        let scrobbleTrack = track.applyingProScrobblePreferences()
        let startedAt = now.addingTimeInterval(-max(0, playbackTimeSeconds))
        let ts = Int(startedAt.timeIntervalSince1970.rounded(.down))

        let client = try LastFMClient()
        do {
            try await client.scrobble(track: scrobbleTrack, sessionKey: sessionKey, startTimestamp: ts)
            await MainActor.run {
                ScrobbleLogStore.shared.record(track: scrobbleTrack, startTimestamp: ts, source: .live)
            }
            return .result(dialog: "Scrobbled: \(scrobbleTrack.artist) — \(scrobbleTrack.title)")
        } catch {
            logger.warning("manual scrobble failed: \(error.localizedDescription, privacy: .public)")
            await ScrobbleBacklog.shared.enqueue(track: scrobbleTrack, startTimestamp: ts)
            throw error
        }
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
    }
}
