import Foundation
import MediaPlayer
import OSLog

@MainActor
final class PlaybackHistoryImporter {
    enum ImportKeys {
        static let lastImportAt = "FastScrobbler.PlaybackHistoryImporter.lastImportAt"
    }

    static let shared = PlaybackHistoryImporter()

    private let logger = Logger(subsystem: "FastScrobbler", category: "PlaybackHistoryImporter")

    private init() {}

    func importIntoBacklog(backlog: ScrobbleBacklog, maxItems: Int = 50) async -> Int {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return 0 }

        let lastImportAt = UserDefaults.standard.object(forKey: ImportKeys.lastImportAt) as? Date
        let cutoff = lastImportAt ?? Date(timeIntervalSinceNow: -24 * 60 * 60)

        guard let playlist = findPlaybackHistoryPlaylist() else {
            logger.debug("no playback history playlist found; skipping import")
            return 0
        }

        let items = playlist.items
        guard !items.isEmpty else { return 0 }

        var importedCount = 0
        var newestPlayedAt: Date?

        for item in items {
            guard importedCount < maxItems else { break }
            guard let playedAt = item.lastPlayedDate else { continue }
            guard playedAt > cutoff else { continue }

            let artist = item.artist ?? ""
            let title = item.title ?? ""
            guard !artist.isEmpty, !title.isEmpty else { continue }

            let duration = item.playbackDuration
            let track = Track(
                artist: artist,
                title: title,
                album: item.albumTitle,
                durationSeconds: duration > 0 ? duration : nil,
                persistentID: item.persistentID
            )

            let startTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
            await backlog.enqueue(track: track, startTimestamp: startTimestamp)
            importedCount += 1

            if newestPlayedAt == nil || playedAt > newestPlayedAt! {
                newestPlayedAt = playedAt
            }
        }

        if let newestPlayedAt {
            UserDefaults.standard.set(newestPlayedAt, forKey: ImportKeys.lastImportAt)
        }

        return importedCount
    }

    private func findPlaybackHistoryPlaylist() -> MPMediaPlaylist? {
        let query = MPMediaQuery.playlists()
        let playlists = query.collections as? [MPMediaPlaylist] ?? []
        if playlists.isEmpty { return nil }

        let candidateNames = [
            "Playback History",
            "Recently Played",
        ]

        for p in playlists {
            let name = p.name ?? ""
            if candidateNames.contains(name) {
                return p
            }
        }

        return nil
    }
}

