import Foundation
import MediaPlayer

enum AppleMusicFavorites {
    /// iOS Music currently surfaces the user's "Favorite Songs" as a smart playlist.
    /// Unfortunately, `MPMediaItem` does not expose a first-class "isFavorite" property,
    /// so we infer it by membership in that playlist (plus a legacy `rating` fallback).
    private static let candidatePlaylistNames: Set<String> = [
        "Favorite Songs",
        "Favourite Songs",
    ]

    struct Index: Sendable {
        fileprivate var persistentIDs: Set<UInt64>
        fileprivate var playbackStoreIDs: Set<String>

        func contains(_ item: MPMediaItem) -> Bool {
            let pid = item.persistentID
            if pid != 0, persistentIDs.contains(pid) { return true }
            let sid = item.playbackStoreID
            if !sid.isEmpty, playbackStoreIDs.contains(sid) { return true }
            return false
        }
    }

    static func buildIndex() -> Index? {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return nil }

        let query = MPMediaQuery.playlists()
        let playlists = query.collections as? [MPMediaPlaylist] ?? []
        guard !playlists.isEmpty else { return nil }

        guard let favoritesPlaylist = playlists.first(where: { p in
            guard let name = p.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return false }
            return candidatePlaylistNames.contains(name)
        }) else {
            return nil
        }

        var pids: Set<UInt64> = []
        pids.reserveCapacity(min(favoritesPlaylist.items.count, 256))
        var sids: Set<String> = []
        sids.reserveCapacity(min(favoritesPlaylist.items.count, 256))

        for item in favoritesPlaylist.items {
            let pid = item.persistentID
            if pid != 0 { pids.insert(pid) }

            let sid = item.playbackStoreID
            if !sid.isEmpty { sids.insert(sid) }
        }

        return Index(persistentIDs: pids, playbackStoreIDs: sids)
    }

    static func isFavorited(_ item: MPMediaItem, index: Index?) -> Bool {
        // Legacy / best-effort: some library items expose "favorite-ish" state via star rating.
        if item.rating != 0 { return true }
        return index?.contains(item) == true
    }
}
