import Foundation

func runProMetadataTests() {
    // ─── 3b: Pro settings snapshot ───────────────────────────────────────────────

    section("3b · Pro settings snapshot — scrobbleTrack stable within session")

    // Simulate: scrobbleTrack is computed once at session start and reused,
    // even if the underlying applyingProScrobblePreferences would return differently later.
    struct SimTrack: Equatable {
        var title: String
        func withBracketsRemoved() -> SimTrack { SimTrack(title: title.replacingOccurrences(of: #" \(.*\)"#, with: "", options: .regularExpression)) }
    }

    struct SimSession {
        var rawTrack: SimTrack
        var scrobbleTrack: SimTrack?
    }

    var proRemoveBracketsEnabled = true

    func applyPro(_ track: SimTrack) -> SimTrack {
        proRemoveBracketsEnabled ? track.withBracketsRemoved() : track
    }

    // Session starts with brackets-enabled Pro setting
    var session = SimSession(rawTrack: SimTrack(title: "Song (feat. X)"))
    session.scrobbleTrack = applyPro(session.rawTrack)

    let scrobbleTrackAtStart = session.scrobbleTrack!
    expect("scrobbleTrack has brackets removed at session start",
           scrobbleTrackAtStart.title == "Song", detail: "got '\(scrobbleTrackAtStart.title)'")

    // User toggles off bracket removal mid-session
    proRemoveBracketsEnabled = false

    // The cached scrobbleTrack should NOT change
    expect("scrobbleTrack unchanged after Pro setting toggle",
           session.scrobbleTrack?.title == "Song", detail: "got '\(session.scrobbleTrack?.title ?? "nil")'")

    // applyPro now returns different result — confirming the snapshot is different from live
    let liveResult = applyPro(session.rawTrack)
    expect("live applyPro now returns unmodified title (settings changed)",
           liveResult.title == "Song (feat. X)", detail: "got '\(liveResult.title)'")

    expect("cached and live results diverge (proving snapshot is working)",
           session.scrobbleTrack?.title != liveResult.title)

    // ─── EP/Single suffix stripping ───────────────────────────────────────────────
    // Replicates strippingEpAndSingleSuffixFromAlbumIfPresent() from Track.swift.

    section("Pro · EP/Single suffix stripping")

    func stripEpSingleSuffix(from album: String) -> String {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["- EP", "- Single"]
        for suffix in suffixes {
            if trimmed.hasSuffix(suffix) {
                let stripped = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return stripped.isEmpty ? trimmed : stripped
            }
        }
        return trimmed
    }

    expect("strips '- EP' suffix",       stripEpSingleSuffix(from: "Folklore - EP") == "Folklore",
           detail: "got '\(stripEpSingleSuffix(from: "Folklore - EP"))'")
    expect("strips '- Single' suffix",   stripEpSingleSuffix(from: "Circles - Single") == "Circles",
           detail: "got '\(stripEpSingleSuffix(from: "Circles - Single"))'")
    expect("leaves plain album name",    stripEpSingleSuffix(from: "Album Name") == "Album Name",
           detail: "got '\(stripEpSingleSuffix(from: "Album Name"))'")
    expect("'EP' as prefix is kept",     stripEpSingleSuffix(from: "EP Recordings") == "EP Recordings",
           detail: "got '\(stripEpSingleSuffix(from: "EP Recordings"))'")
    expect("strips with extra whitespace", stripEpSingleSuffix(from: "  My Album - EP  ") == "My Album",
           detail: "got '\(stripEpSingleSuffix(from: "  My Album - EP  "))'")

    // ─── Album artist substitution ────────────────────────────────────────────────
    // Replicates usableAlbumArtistForArtistSubstitution(_:isCompilation:) from Track.swift.

    section("Pro · Album artist substitution")

    func usableAlbumArtist(_ albumArtist: String?, isCompilation: Bool?) -> String? {
        guard let trimmed = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.compare("Various Artists", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else {
            return nil
        }
        return trimmed
    }

    expect("uses albumArtist when available",    usableAlbumArtist("The Band", isCompilation: nil) == "The Band")
    expect("returns nil for nil albumArtist",    usableAlbumArtist(nil, isCompilation: nil) == nil)
    expect("returns nil for empty albumArtist",  usableAlbumArtist("   ", isCompilation: nil) == nil)
    expect("compilations use albumArtist",       usableAlbumArtist("The Band", isCompilation: true) == "The Band")
    expect("'Various Artists' is nil",           usableAlbumArtist("Various Artists", isCompilation: nil) == nil)
    expect("'various artists' (lowercase) nil",  usableAlbumArtist("various artists", isCompilation: nil) == nil)
    expect("non-compilation uses albumArtist",   usableAlbumArtist("The Band", isCompilation: false) == "The Band")

    // ─── First-artist-only parsing ───────────────────────────────────────────────

    section("Pro · First artist only parsing")

    func firstArtistOnly(from artist: String, ignoredArtists: [String] = []) -> String? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty else { return nil }

        let normalizedArtist = trimmedArtist.lowercased()
        for ignored in ignoredArtists {
            if ignored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedArtist {
                return nil
            }
        }

        let separators: [Character] = ["&", ","]
        var earliestSeparatorIndex: String.Index?

        for separator in separators {
            guard let index = trimmedArtist.firstIndex(of: separator) else { continue }
            if let currentEarliest = earliestSeparatorIndex {
                if index < currentEarliest {
                    earliestSeparatorIndex = index
                }
            } else {
                earliestSeparatorIndex = index
            }
        }

        guard let splitIndex = earliestSeparatorIndex else {
            return trimmedArtist == artist ? nil : trimmedArtist
        }

        let firstArtist = trimmedArtist[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstArtist.isEmpty else { return nil }
        return firstArtist == artist ? nil : firstArtist
    }

    expectEqual("ampersand keeps only first artist", firstArtistOnly(from: "Lady Gaga & Doechii"), "Lady Gaga")
    expectEqual("comma keeps only first artist", firstArtistOnly(from: "Lady Gaga, Doechii"), "Lady Gaga")
    expectEqual("no separator is unchanged", firstArtistOnly(from: "Lady Gaga"), nil)
    expectEqual("leading and trailing whitespace are trimmed", firstArtistOnly(from: "  Lady Gaga  "), "Lady Gaga")
    expectEqual("empty leading segment is ignored", firstArtistOnly(from: ", Doechii"), nil)
    expectEqual("ignored artist matching case-insensitively skips splitting", firstArtistOnly(from: "Earth, Wind & Fire", ignoredArtists: ["earth, wind & fire"]), nil)
    expectEqual("non-ignored artist is still split", firstArtistOnly(from: "Lady Gaga & Doechii", ignoredArtists: ["Earth, Wind & Fire"]), "Lady Gaga")

    // ─── Track dedup key (libraryIdentityKey) ────────────────────────────────────
    // Replicates stableLibraryIdentity from Track.swift.

    section("Track · libraryIdentityKey fallback chain")

    func stableLibraryIdentity(persistentID: UInt64?, playbackStoreID: String?, artist: String, title: String, album: String?) -> String {
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let persistentID, persistentID != 0 {
            return "pid:\(persistentID)"
        }
        if let playbackStoreID {
            let trimmed = playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return "sid:\(trimmed.lowercased())" }
        }
        let albumValue = album.map(norm) ?? ""
        return "meta:\(norm(artist))|\(norm(title))|\(albumValue)"
    }

    let keyWithPID    = stableLibraryIdentity(persistentID: 42, playbackStoreID: "sid1", artist: "A", title: "T", album: "Al")
    let keyWithSID    = stableLibraryIdentity(persistentID: nil, playbackStoreID: "sid1", artist: "A", title: "T", album: "Al")
    let keyWithMeta   = stableLibraryIdentity(persistentID: nil, playbackStoreID: nil, artist: "Artist", title: "Title", album: "Album")
    let keyWithMetaLo = stableLibraryIdentity(persistentID: nil, playbackStoreID: nil, artist: "ARTIST", title: "TITLE", album: "ALBUM")

    expect("persistentID takes priority",            keyWithPID == "pid:42",              detail: "got '\(keyWithPID)'")
    expect("playbackStoreID used when no pid",       keyWithSID == "sid:sid1",            detail: "got '\(keyWithSID)'")
    expect("meta key uses normalized components",    keyWithMeta == "meta:artist|title|album", detail: "got '\(keyWithMeta)'")
    expect("meta key is case-insensitive",           keyWithMeta == keyWithMetaLo,        detail: "meta='\(keyWithMeta)' metaLo='\(keyWithMetaLo)'")
    expect("persistentID=0 falls through to sid",   stableLibraryIdentity(persistentID: 0, playbackStoreID: "x", artist: "A", title: "T", album: nil) == "sid:x")
    expect("empty sid falls through to meta",        stableLibraryIdentity(persistentID: nil, playbackStoreID: "  ", artist: "A", title: "T", album: nil) == "meta:a|t|")
}
