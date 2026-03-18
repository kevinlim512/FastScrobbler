import Foundation
import MediaPlayer

enum AppleMusicFavorites {
    /// iOS Music currently surfaces the user's "Favorite Songs" as a smart playlist.
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
        // Only trust the Favorites playlist index. Library rating metadata can be non-zero for tracks
        // that are merely saved in Apple Music, which causes false Last.fm loves.
        return index?.contains(item) == true
    }
}
