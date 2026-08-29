import Foundation

func runLovedFeatureTests() {
    section("Loved feature · Favorite-source edge cases")

    let candidatePlaylistNames: Set<String> = [
        "Favorite Songs",
        "Favourite Songs",
    ]

    struct FavoritePlaylist {
        let name: String
        let trackIDs: [String]
    }

    func selectedFavoritesPlaylist(from playlists: [FavoritePlaylist]) -> FavoritePlaylist? {
        playlists.first { playlist in
            let trimmed = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return candidatePlaylistNames.contains(trimmed)
        }
    }

    let exactFavorite = FavoritePlaylist(name: "Favorite Songs", trackIDs: ["pid:1"])
    let exactFavourite = FavoritePlaylist(name: "Favourite Songs", trackIDs: ["pid:2"])
    let lowercased = FavoritePlaylist(name: "favorite songs", trackIDs: ["pid:3"])
    let uppercased = FavoritePlaylist(name: "FAVOURITE SONGS", trackIDs: ["pid:4"])
    let spaced = FavoritePlaylist(name: "  Favourite Songs  ", trackIDs: ["pid:5"])

    expectEqual(
        "exact US spelling is accepted",
        selectedFavoritesPlaylist(from: [exactFavorite])?.trackIDs,
        ["pid:1"]
    )
    expectEqual(
        "exact UK spelling is accepted",
        selectedFavoritesPlaylist(from: [exactFavourite])?.trackIDs,
        ["pid:2"]
    )
    expect(
        "lowercased playlist name is ignored",
        selectedFavoritesPlaylist(from: [lowercased]) == nil
    )
    expect(
        "uppercased playlist name is ignored",
        selectedFavoritesPlaylist(from: [uppercased]) == nil
    )
    expectEqual(
        "surrounding whitespace is trimmed before matching",
        selectedFavoritesPlaylist(from: [spaced])?.trackIDs,
        ["pid:5"]
    )

    let duplicateNames = [
        FavoritePlaylist(name: "Favourite Songs", trackIDs: ["pid:user-playlist"]),
        FavoritePlaylist(name: "Favourite Songs", trackIDs: ["pid:apple-smart-playlist"]),
    ]
    expectEqual(
        "duplicate matching playlist names pick the first playlist returned by MediaPlayer",
        selectedFavoritesPlaylist(from: duplicateNames)?.trackIDs,
        ["pid:user-playlist"]
    )

    section("Loved feature · Track identity matching")

    func isValidPlaybackStoreID(_ id: String?) -> Bool {
        guard let id else { return false }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "0"
    }

    struct FavoritesIndex {
        var persistentIDs: Set<UInt64>
        var playbackStoreIDs: Set<String>

        func contains(persistentID: UInt64, playbackStoreID: String?) -> Bool {
            if persistentID != 0, persistentIDs.contains(persistentID) { return true }
            guard isValidPlaybackStoreID(playbackStoreID), let playbackStoreID else { return false }
            return playbackStoreIDs.contains(playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    let exactTrackIndex = FavoritesIndex(
        persistentIDs: [101],
        playbackStoreIDs: ["clairo-blouse", "0"]
    )
    expect(
        "same persistent ID is treated as favorited",
        exactTrackIndex.contains(persistentID: 101, playbackStoreID: nil)
    )
    expect(
        "same playbackStoreID is treated as favorited",
        exactTrackIndex.contains(persistentID: 0, playbackStoreID: "clairo-blouse")
    )
    expect(
        "fallback store ID '0' for uploaded/custom tracks is ignored and not treated as favorited",
        !exactTrackIndex.contains(persistentID: 0, playbackStoreID: "0")
    )
    expect(
        "different live-version identity is not treated as favorited",
        !exactTrackIndex.contains(persistentID: 202, playbackStoreID: "clairo-blouse-live")
    )
    expect(
        "metadata similarity alone does not mark a live version as favorited",
        !exactTrackIndex.contains(persistentID: 0, playbackStoreID: nil)
    )

    section("Loved feature · Love submission guards")

    func shouldLoveLiveTrack(
        observerFavoriteID: String?,
        currentFavoriteID: String,
        isNowPlayingLovedInAppleMusic: Bool?,
        loveOnFavoriteEnabled: Bool,
        hasLovedOnThisSession: Bool
    ) -> Bool {
        let wasAppleMusicFavorite =
            observerFavoriteID == currentFavoriteID &&
            isNowPlayingLovedInAppleMusic == true
        guard wasAppleMusicFavorite else { return false }
        guard loveOnFavoriteEnabled else { return false }
        guard !hasLovedOnThisSession else { return false }
        return true
    }

    func shouldLoveBacklogItem(
        wasAppleMusicFavorite: Bool?,
        loveOnFavoriteEnabled: Bool
    ) -> Bool {
        wasAppleMusicFavorite == true && loveOnFavoriteEnabled
    }

    expect(
        "live scrobble loves when favorite ID matches and Apple Music says favorited",
        shouldLoveLiveTrack(
            observerFavoriteID: "pid:1",
            currentFavoriteID: "pid:1",
            isNowPlayingLovedInAppleMusic: true,
            loveOnFavoriteEnabled: true,
            hasLovedOnThisSession: false
        )
    )
    expect(
        "live scrobble does not love when favorite flag is nil",
        !shouldLoveLiveTrack(
            observerFavoriteID: "pid:1",
            currentFavoriteID: "pid:1",
            isNowPlayingLovedInAppleMusic: nil,
            loveOnFavoriteEnabled: true,
            hasLovedOnThisSession: false
        )
    )
    expect(
        "live scrobble does not love when track identity changed underneath the observer",
        !shouldLoveLiveTrack(
            observerFavoriteID: "pid:studio",
            currentFavoriteID: "pid:live",
            isNowPlayingLovedInAppleMusic: true,
            loveOnFavoriteEnabled: true,
            hasLovedOnThisSession: false
        )
    )
    expect(
        "live scrobble does not love twice in the same session",
        !shouldLoveLiveTrack(
            observerFavoriteID: "pid:1",
            currentFavoriteID: "pid:1",
            isNowPlayingLovedInAppleMusic: true,
            loveOnFavoriteEnabled: true,
            hasLovedOnThisSession: true
        )
    )
    expect(
        "live scrobble does not love when the Pro toggle is disabled",
        !shouldLoveLiveTrack(
            observerFavoriteID: "pid:1",
            currentFavoriteID: "pid:1",
            isNowPlayingLovedInAppleMusic: true,
            loveOnFavoriteEnabled: false,
            hasLovedOnThisSession: false
        )
    )
    expect(
        "backlog recovery can love imported favorites when the toggle is enabled",
        shouldLoveBacklogItem(wasAppleMusicFavorite: true, loveOnFavoriteEnabled: true)
    )
    expect(
        "backlog recovery does not love when the imported item was not favorited",
        !shouldLoveBacklogItem(wasAppleMusicFavorite: false, loveOnFavoriteEnabled: true)
    )
    expect(
        "backlog recovery does not love when the imported favorite flag is missing",
        !shouldLoveBacklogItem(wasAppleMusicFavorite: nil, loveOnFavoriteEnabled: true)
    )
}
