import Foundation
import MediaPlayer

enum AppleMusicFavorites {
    /// iOS Music currently surfaces the user's "Favorite Songs" as a smart playlist across localized titles.
    private static let candidatePlaylistNames: Set<String> = [
        "Favorite Songs",
        "Favourite Songs",
        "Canciones favoritas",
        "Morceaux préférés",
        "Titres préférés",
        "お気に入りの曲",
        "喜爱歌曲",
        "最爱歌曲",
        "喜愛的歌曲",
        "最愛的歌曲",
        "Lieblingssongs",
        "Lieblingstitel",
        "Brani preferiti",
        "Músicas Favoritas",
        "Músicas Preferidas",
        "Любимые песни",
        "즐겨찾는 노래"
    ]

    static func isValidPlaybackStoreID(_ id: String?) -> Bool {
        guard let id else { return false }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "0"
    }

    struct Index: Sendable {
        fileprivate var persistentIDs: Set<UInt64>
        fileprivate var playbackStoreIDs: Set<String>

        func contains(_ item: MPMediaItem) -> Bool {
            let pid = item.persistentID
            if pid != 0, persistentIDs.contains(pid) { return true }
            let sid = item.playbackStoreID
            if AppleMusicFavorites.isValidPlaybackStoreID(sid) {
                let trimmed = sid.trimmingCharacters(in: .whitespacesAndNewlines)
                if playbackStoreIDs.contains(trimmed) { return true }
            }
            return false
        }

        func contains(playbackStoreID: String?) -> Bool {
            guard AppleMusicFavorites.isValidPlaybackStoreID(playbackStoreID), let playbackStoreID else { return false }
            let trimmed = playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            return playbackStoreIDs.contains(trimmed)
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

            let sid = item.playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidPlaybackStoreID(sid) { sids.insert(sid) }
        }

        return Index(persistentIDs: pids, playbackStoreIDs: sids)
    }

    static func isFavorited(_ item: MPMediaItem, index: Index?) -> Bool {
        // Only trust the Favorites playlist index. Library rating metadata can be non-zero for tracks
        // that are merely saved in Apple Music, which causes false Last.fm loves.
        return index?.contains(item) == true
    }

    static func isFavorited(playbackStoreID: String?, index: Index?) -> Bool {
        index?.contains(playbackStoreID: playbackStoreID) == true
    }
}

enum AppleMusicLibrarySongs {
    struct Index: Sendable {
        fileprivate var playbackStoreIDs: Set<String>

        func contains(playbackStoreID: String?) -> Bool {
            guard AppleMusicFavorites.isValidPlaybackStoreID(playbackStoreID), let playbackStoreID else { return false }
            let trimmed = playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            return playbackStoreIDs.contains(trimmed)
        }
    }

    static func buildIndex() -> Index? {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return nil }

        let query = MPMediaQuery.songs()
        let items = query.items ?? []
        guard !items.isEmpty else {
            return Index(playbackStoreIDs: [])
        }

        var storeIDs: Set<String> = []
        storeIDs.reserveCapacity(min(items.count, 2048))

        for item in items {
            let sid = item.playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            if AppleMusicFavorites.isValidPlaybackStoreID(sid) {
                storeIDs.insert(sid)
            }
        }

        return Index(playbackStoreIDs: storeIDs)
    }
}
