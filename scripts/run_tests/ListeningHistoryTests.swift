import Foundation

func runListeningHistoryRecoveryTests() {
    // ─── Listening History repeated-play recovery ────────────────────────────────
    // Replicates the count-based recovery logic in PlaybackHistoryImporter.

    section("Listening History · Repeated play recovery")

    func recoveredPlaybackHistoryStartTimestamps(
        playCount: Int,
        previousPlayCount: Int?,
        playedAt: Int,
        durationSeconds: Int?,
        previousSeenPlayedAt: Int?,
        preventDuplicates: Bool,
        scrobbleLoopedTracks: Bool
    ) -> [Int] {
        let delta: Int = {
            guard let previousPlayCount else {
                return 1
            }
            let d = playCount - previousPlayCount
            if d > 0 { return d }
            return 1
        }()

        let playsToImport: Int = {
            return max(delta, 1)
        }()

        let synthesizedPlayCount = playsToImport

        if let durationSeconds, durationSeconds > 0 {
            return (0..<synthesizedPlayCount).map { index in
                playedAt - durationSeconds * (synthesizedPlayCount - index - 1)
            }
        }

        guard synthesizedPlayCount > 1 else { return [playedAt] }

        return (0..<synthesizedPlayCount).map { index in
            playedAt - (synthesizedPlayCount - index - 1)
        }
    }

    let recoveredStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 20,
        previousPlayCount: nil,
        playedAt: 1_234,
        durationSeconds: 12,
        previousSeenPlayedAt: nil,
        preventDuplicates: false,
        scrobbleLoopedTracks: false
    )
    expectEqual("first sighting imports only the current lastPlayedDate play", recoveredStarts.count, 1)
    expect("first sighting uses Apple's lastPlayedDate when duration is known", recoveredStarts == [1_234], detail: "got \(recoveredStarts)")

    let conservativeStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 15,
        previousPlayCount: 0,
        playedAt: 4_405,
        durationSeconds: 60,
        previousSeenPlayedAt: nil,
        preventDuplicates: true,
        scrobbleLoopedTracks: false
    )
    expectEqual("known play-count increases can recover all new plays", conservativeStarts.count, 15)
    expect("known play-count increases stagger timestamps", conservativeStarts == [3_565, 3_625, 3_685, 3_745, 3_805, 3_865, 3_925, 3_985, 4_045, 4_105, 4_165, 4_225, 4_285, 4_345, 4_405], detail: "got \(conservativeStarts)")

    let loopToggleStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 20,
        previousPlayCount: nil,
        playedAt: 9_876,
        durationSeconds: 12,
        previousSeenPlayedAt: nil,
        preventDuplicates: true,
        scrobbleLoopedTracks: true
    )
    expectEqual("looped-track setting does not turn lifetime playCount into first-sighting imports", loopToggleStarts.count, 1)

    let samePlayedAtGrowthStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 4,
        previousPlayCount: 3,
        playedAt: 1_200,
        durationSeconds: 200,
        previousSeenPlayedAt: 1_200,
        preventDuplicates: false,
        scrobbleLoopedTracks: false
    )
    expect("same playedAt growth imports only the new delta play", samePlayedAtGrowthStarts == [1_200], detail: "got \(samePlayedAtGrowthStarts)")

    let samePlayedAtMultiGrowthStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 5,
        previousPlayCount: 3,
        playedAt: 1_200,
        durationSeconds: 200,
        previousSeenPlayedAt: 1_200,
        preventDuplicates: false,
        scrobbleLoopedTracks: false
    )
    expect("same playedAt multi-growth imports only the delta timeline", samePlayedAtMultiGrowthStarts == [1_000, 1_200], detail: "got \(samePlayedAtMultiGrowthStarts)")

    let unknownDurationStarts = recoveredPlaybackHistoryStartTimestamps(
        playCount: 1,
        previousPlayCount: nil,
        playedAt: 3_000,
        durationSeconds: nil,
        previousSeenPlayedAt: nil,
        preventDuplicates: false,
        scrobbleLoopedTracks: false
    )
    expect("unknown-duration first sighting falls back to Apple's timestamp", unknownDurationStarts == [3_000], detail: "got \(unknownDurationStarts)")

    section("Listening History · Edge cases")

    func productionPlaybackHistoryStartTimestamps(
        playedAt: Int,
        playCount: Int,
        durationSeconds: Double?
    ) -> [Int] {
        let count = max(playCount, 1)

        if let durationSeconds, durationSeconds > 0 {
            let spacingSeconds = max(Int(durationSeconds.rounded(.down)), 1)
            return (0..<count).map { index in
                max(1, playedAt - spacingSeconds * (count - index - 1))
            }
        }

        guard count > 1 else { return [max(1, playedAt)] }

        return (0..<count).map { index in
            max(1, playedAt - (count - index - 1))
        }
    }

    expectEqual(
        "zero playCount is clamped to one import candidate",
        productionPlaybackHistoryStartTimestamps(playedAt: 500, playCount: 0, durationSeconds: 30),
        [500]
    )
    expectEqual(
        "negative playCount is clamped to one import candidate",
        productionPlaybackHistoryStartTimestamps(playedAt: 500, playCount: -4, durationSeconds: 30),
        [500]
    )
    expectEqual(
        "fractional durations are rounded down before spacing recovered plays",
        productionPlaybackHistoryStartTimestamps(playedAt: 1_000, playCount: 3, durationSeconds: 30.9),
        [940, 970, 1_000]
    )
    expectEqual(
        "sub-second positive durations still space candidates at least one second apart",
        productionPlaybackHistoryStartTimestamps(playedAt: 10, playCount: 3, durationSeconds: 0.4),
        [8, 9, 10]
    )
    expectEqual(
        "known-duration candidates are clamped to valid Last.fm timestamps",
        productionPlaybackHistoryStartTimestamps(playedAt: 2, playCount: 3, durationSeconds: 5),
        [1, 1, 2]
    )
    expectEqual(
        "unknown-duration recovered candidates are clamped near the Unix epoch",
        productionPlaybackHistoryStartTimestamps(playedAt: 2, playCount: 5, durationSeconds: nil),
        [1, 1, 1, 1, 2]
    )

    func playbackHistoryPlayedAt(
        startTimestamp: Int,
        originalPlayedAt: Int,
        durationSeconds: Double?
    ) -> Int {
        if startTimestamp < originalPlayedAt {
            if let durationSeconds, durationSeconds > 0 {
                let candidatePlayedAtTimestamp = startTimestamp + max(Int(durationSeconds.rounded(.down)), 1)
                if candidatePlayedAtTimestamp <= originalPlayedAt {
                    return candidatePlayedAtTimestamp
                }
            }
            return startTimestamp
        }
        return originalPlayedAt
    }

    expectEqual(
        "candidate playedAt calculates completed time for earlier synthesized play when duration is known",
        playbackHistoryPlayedAt(startTimestamp: 940, originalPlayedAt: 1_000, durationSeconds: 30.9),
        970
    )
    expectEqual(
        "candidate playedAt preserves Apple's timestamp for final play when startTimestamp matches or exceeds originalPlayedAt",
        playbackHistoryPlayedAt(startTimestamp: 1_000, originalPlayedAt: 1_000, durationSeconds: 30.9),
        1_000
    )
    expectEqual(
        "candidate playedAt uses startTimestamp when duration is unknown",
        playbackHistoryPlayedAt(startTimestamp: 999, originalPlayedAt: 1_050, durationSeconds: nil),
        999
    )
    expectEqual(
        "candidate playedAt preserves Apple's timestamp for tiny positive durations at upper bound",
        playbackHistoryPlayedAt(startTimestamp: 10, originalPlayedAt: 10, durationSeconds: 0.4),
        10
    )

    section("Listening History · Looped scrobble submission")
    let loopedStarts = (0..<5).map { index in
        10_000 - 215 * (5 - index - 1)
    }
    let loopedPlayedAts = loopedStarts.map { start in
        playbackHistoryPlayedAt(startTimestamp: start, originalPlayedAt: 10_000, durationSeconds: 210)
    }
    expectEqual(
        "looped scrobbles produce distinct candidate playedAt timestamps so none are incorrectly rejected as duplicate",
        Set(loopedPlayedAts).count,
        5
    )
    expectEqual(
        "looped scrobbles playedAt values step according to track duration",
        loopedPlayedAts,
        [9350, 9565, 9780, 9995, 10000]
    )

    section("Listening History · Media library snapshot diff")

    struct FakeLibrarySnapshotRecord: Equatable {
        let itemID: String
        let dedupeKey: String
        let playCount: Int
        let lastPlayedAt: Int?
        let durationSeconds: Int?
    }

    func snapshotCandidateStarts(
        current: FakeLibrarySnapshotRecord,
        previous: FakeLibrarySnapshotRecord?,
        fetchCutoff: Int,
        importedKeys: Set<String> = [],
        maxDelta: Int = 80,
        repeatGapSeconds: Int = 5
    ) -> [Int] {
        guard let playedAt = current.lastPlayedAt else { return [] }
        guard playedAt > fetchCutoff else { return [] }

        let baselinePlayedAt = previous?.lastPlayedAt
        let baselinePlayCount = previous?.playCount
        let hasNewPlayedAt = baselinePlayedAt.map { playedAt > $0 } ?? true
        let hasCountIncrease = baselinePlayCount.map { current.playCount > $0 } ?? false
        guard hasNewPlayedAt || hasCountIncrease else { return [] }

        let delta: Int = {
            guard let baselinePlayCount else { return 1 }
            let increased = current.playCount - baselinePlayCount
            if increased > 0 { return increased }
            return hasNewPlayedAt ? 1 : 0
        }()
        let count = min(max(delta, 0), maxDelta)
        guard count > 0 else { return [] }

        let starts: [Int]
        if let durationSeconds = current.durationSeconds, durationSeconds > 0 {
            let spacing = durationSeconds + repeatGapSeconds
            starts = (0..<count).map { index in
                let end = playedAt - spacing * (count - index - 1)
                return max(1, end - durationSeconds)
            }
        } else if count == 1 {
            starts = [playedAt]
        } else {
            starts = (0..<count).map { index in
                max(1, playedAt - (count - index - 1))
            }
        }

        return starts.filter { start in
            !importedKeys.contains("\(current.itemID)|\(current.dedupeKey)|\(start)|\(playedAt)")
        }
    }

    let snapshotCurrent = FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 4, lastPlayedAt: 2_000, durationSeconds: 180)
    expectEqual(
        "first snapshot sighting imports only the latest play inside lookback",
        snapshotCandidateStarts(current: snapshotCurrent, previous: nil, fetchCutoff: 1_000),
        [1_820]
    )
    expectEqual(
        "unchanged snapshot produces no candidates",
        snapshotCandidateStarts(current: snapshotCurrent, previous: snapshotCurrent, fetchCutoff: 1_000),
        []
    )
    expectEqual(
        "single play-count increase creates one synthesized start",
        snapshotCandidateStarts(
            current: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 5, lastPlayedAt: 2_200, durationSeconds: 180),
            previous: snapshotCurrent,
            fetchCutoff: 1_000
        ),
        [2_020]
    )
    expectEqual(
        "multi-play delta expands backwards from lastPlayedDate with a small gap",
        snapshotCandidateStarts(
            current: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 7, lastPlayedAt: 2_555, durationSeconds: 180),
            previous: snapshotCurrent,
            fetchCutoff: 1_000
        ),
        [2_005, 2_190, 2_375]
    )
    expectEqual(
        "lastPlayedDate advance without play-count increase creates one safe candidate",
        snapshotCandidateStarts(
            current: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 4, lastPlayedAt: 2_300, durationSeconds: 180),
            previous: snapshotCurrent,
            fetchCutoff: 1_000
        ),
        [2_120]
    )
    expectEqual(
        "import ledger prevents re-importing the same synthesized candidate",
        snapshotCandidateStarts(
            current: snapshotCurrent,
            previous: nil,
            fetchCutoff: 1_000,
            importedKeys: ["pid:1|track-a|1820|2000"]
        ),
        []
    )
    expectEqual(
        "large play-count jumps are capped at the per-track safety limit",
        snapshotCandidateStarts(
            current: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 100, lastPlayedAt: 5_000, durationSeconds: 60),
            previous: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 0, lastPlayedAt: 4_000, durationSeconds: 60),
            fetchCutoff: 1_000
        ).count,
        80
    )
    expectEqual(
        "missing duration multi-delta falls back to one-second spacing",
        snapshotCandidateStarts(
            current: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 3, lastPlayedAt: 2_000, durationSeconds: nil),
            previous: FakeLibrarySnapshotRecord(itemID: "pid:1", dedupeKey: "track-a", playCount: 1, lastPlayedAt: 1_800, durationSeconds: nil),
            fetchCutoff: 1_000
        ),
        [1_999, 2_000]
    )

    struct FakeHistoryCandidate {
        let artist: String?
        let title: String?
        let playedAt: Int
        let previousSeenPlayedAt: Int?
        let playCount: Int
        let previousPlayCount: Int?
    }

    func shouldImportPlaybackHistoryCandidate(_ candidate: FakeHistoryCandidate, fetchCutoff: Int) -> Bool {
        let artist = candidate.artist ?? ""
        let title = candidate.title ?? ""
        guard !artist.isEmpty, !title.isEmpty else { return false }

        let playCutoff: Int = {
            if let previousSeenPlayedAt = candidate.previousSeenPlayedAt {
                return max(fetchCutoff, previousSeenPlayedAt)
            }
            return fetchCutoff
        }()
        let hasNewPlayedAt = candidate.playedAt > playCutoff
        let hasCountIncreaseAtSamePlayedAt = candidate.previousSeenPlayedAt == candidate.playedAt &&
            candidate.previousPlayCount.map { candidate.playCount > $0 } == true
        return hasNewPlayedAt || hasCountIncreaseAtSamePlayedAt
    }

    expect(
        "blank artist is skipped before cursor state changes",
        !shouldImportPlaybackHistoryCandidate(
            FakeHistoryCandidate(artist: "", title: "Song", playedAt: 2_001, previousSeenPlayedAt: nil, playCount: 1, previousPlayCount: nil),
            fetchCutoff: 2_000
        )
    )
    expect(
        "blank title is skipped before cursor state changes",
        !shouldImportPlaybackHistoryCandidate(
            FakeHistoryCandidate(artist: "Artist", title: nil, playedAt: 2_001, previousSeenPlayedAt: nil, playCount: 1, previousPlayCount: nil),
            fetchCutoff: 2_000
        )
    )
    expect(
        "play exactly at cutoff is skipped without a same-playedAt count increase",
        !shouldImportPlaybackHistoryCandidate(
            FakeHistoryCandidate(artist: "Artist", title: "Song", playedAt: 2_000, previousSeenPlayedAt: nil, playCount: 2, previousPlayCount: 1),
            fetchCutoff: 2_000
        )
    )
    expect(
        "per-track cursor can skip an older backfilled play after global fetch cutoff",
        !shouldImportPlaybackHistoryCandidate(
            FakeHistoryCandidate(artist: "Artist", title: "Song", playedAt: 2_100, previousSeenPlayedAt: 2_200, playCount: 5, previousPlayCount: 4),
            fetchCutoff: 2_000
        )
    )
    expect(
        "same playedAt with increased count is imported even at the per-track cursor",
        shouldImportPlaybackHistoryCandidate(
            FakeHistoryCandidate(artist: "Artist", title: "Song", playedAt: 2_200, previousSeenPlayedAt: 2_200, playCount: 5, previousPlayCount: 4),
            fetchCutoff: 2_000
        )
    )

    func shouldAdvancePlaybackHistoryCursor(candidateCount: Int, importedBeforeTrack: Int, maxItems: Int) -> Bool {
        var importedCount = importedBeforeTrack
        var processedAllCandidateTimestamps = true
        for _ in 0..<candidateCount {
            guard importedCount < maxItems else {
                processedAllCandidateTimestamps = false
                break
            }
            importedCount += 1
        }
        return processedAllCandidateTimestamps
    }

    expect("cursor advances when the full recovered timeline is processed",
           shouldAdvancePlaybackHistoryCursor(candidateCount: 3, importedBeforeTrack: 0, maxItems: 3))
    expect("cursor does not advance when the batch ends mid-timeline",
           !shouldAdvancePlaybackHistoryCursor(candidateCount: 4, importedBeforeTrack: 0, maxItems: 3))

    section("Listening History · Import state pruning")

    func pruneState(
        lastSeenByTrackID: [String: Int],
        playCountByTrackID: [String: Int],
        now: Int,
        retentionDays: Int = 14,
        maxEntries: Int = 2_500
    ) -> ([String: Int], [String: Int]) {
        let cutoff = now - retentionDays * 24 * 60 * 60
        var filteredLastSeen = lastSeenByTrackID.filter { $0.value >= cutoff }
        let allowedIDs = Set(filteredLastSeen.keys)
        var filteredPlayCount = playCountByTrackID.filter { allowedIDs.contains($0.key) }

        if filteredLastSeen.count > maxEntries {
            let newest = filteredLastSeen.sorted(by: { $0.value > $1.value }).prefix(maxEntries)
            let keepIDs = Set(newest.map(\.key))
            filteredLastSeen = filteredLastSeen.filter { keepIDs.contains($0.key) }
            filteredPlayCount = filteredPlayCount.filter { keepIDs.contains($0.key) }
        }

        return (filteredLastSeen, filteredPlayCount)
    }

    let pruneNow = 2_000_000_000
    let staleState = pruneState(
        lastSeenByTrackID: [
            "fresh": pruneNow - 60,
            "stale": pruneNow - (15 * 24 * 60 * 60)
        ],
        playCountByTrackID: [
            "fresh": 3,
            "stale": 8
        ],
        now: pruneNow
    )
    expectEqual("state pruning removes track cursors older than 14 days", Array(staleState.0.keys).sorted(), ["fresh"])
    expectEqual("state pruning drops play counts for removed cursors", Array(staleState.1.keys).sorted(), ["fresh"])

    let oversizedLastSeen = Dictionary(uniqueKeysWithValues: (0..<2_510).map { index in
        ("track-\(index)", pruneNow - index)
    })
    let oversizedPlayCounts = Dictionary(uniqueKeysWithValues: (0..<2_510).map { index in
        ("track-\(index)", index)
    })
    let oversizedState = pruneState(lastSeenByTrackID: oversizedLastSeen, playCountByTrackID: oversizedPlayCounts, now: pruneNow)
    expectEqual("state pruning trims tracked IDs to 2500", oversizedState.0.count, 2_500)
    expectEqual("state pruning trims play-count map to the same 2500 IDs", oversizedState.1.count, 2_500)
    expect("state pruning preserves the newest tracked ID", oversizedState.0.keys.contains("track-0"))
    expect("state pruning drops the oldest tracked ID", !oversizedState.0.keys.contains("track-2509"))

    func shouldProcessPlaybackHistoryCandidate(
        playedAt: Int,
        playCutoff: Int,
        previousSeenPlayedAt: Int?,
        playCount: Int,
        previousPlayCount: Int?
    ) -> Bool {
        let hasNewPlayedAt = playedAt > playCutoff
        let hasCountIncreaseAtSamePlayedAt = previousSeenPlayedAt == playedAt &&
            previousPlayCount.map { playCount > $0 } == true
        return hasNewPlayedAt || hasCountIncreaseAtSamePlayedAt
    }

    expect("same-minute candidate is still processed when playCount increases",
           shouldProcessPlaybackHistoryCandidate(playedAt: 2_000, playCutoff: 2_000, previousSeenPlayedAt: 2_000, playCount: 7, previousPlayCount: 5))
    expect("same-minute candidate is skipped when playCount is unchanged",
           !shouldProcessPlaybackHistoryCandidate(playedAt: 2_000, playCutoff: 2_000, previousSeenPlayedAt: 2_000, playCount: 7, previousPlayCount: 7))

    section("Listening History · Same-timestamp delta protection")

    func importedPlaybackHistoryStartsForSameTimestampGrowth(
        playedAt: Int,
        playCount: Int,
        previousPlayCount: Int?,
        durationSeconds: Int?,
        existingStarts: [Int]
    ) -> [Int] {
        let candidateStarts = recoveredPlaybackHistoryStartTimestamps(
            playCount: playCount,
            previousPlayCount: previousPlayCount,
            playedAt: playedAt,
            durationSeconds: durationSeconds,
            previousSeenPlayedAt: playedAt,
            preventDuplicates: true,
            scrobbleLoopedTracks: false
        )

        return candidateStarts.filter { candidate in
            !existingStarts.contains(where: { abs($0 - candidate) <= 3 })
        }
    }

    let sameTimestampDeltaOnlyStarts = importedPlaybackHistoryStartsForSameTimestampGrowth(
        playedAt: 1_200,
        playCount: 4,
        previousPlayCount: 3,
        durationSeconds: 200,
        existingStarts: [400, 600, 800]
    )
    expectEqual("same-timestamp growth only surfaces one new start", sameTimestampDeltaOnlyStarts, [1_200])

    let sameTimestampRescanStarts = importedPlaybackHistoryStartsForSameTimestampGrowth(
        playedAt: 1_200,
        playCount: 4,
        previousPlayCount: 4,
        durationSeconds: 200,
        existingStarts: [400, 600, 800, 1_200]
    )
    expectEqual("same-timestamp rescan imports nothing after state catches up", sameTimestampRescanStarts, [])

    let sameTimestampTwoPlayDeltaStarts = importedPlaybackHistoryStartsForSameTimestampGrowth(
        playedAt: 1_200,
        playCount: 5,
        previousPlayCount: 3,
        durationSeconds: 200,
        existingStarts: [400, 600]
    )
    expectEqual("same-timestamp two-play growth yields only two new starts", sameTimestampTwoPlayDeltaStarts, [1_000, 1_200])

    let sameTimestampLiveOverlapStarts = importedPlaybackHistoryStartsForSameTimestampGrowth(
        playedAt: 1_200,
        playCount: 4,
        previousPlayCount: 3,
        durationSeconds: 200,
        existingStarts: [1_200]
    )
    expectEqual("same-timestamp growth is fully suppressed when the new play already exists", sameTimestampLiveOverlapStarts, [])

    section("Listening History · Strong recovery duplicate matching")

    struct FakeHistoryMatch {
        let dedupeKey: String
        let startTimestamp: Int
        let durationSeconds: Int?
        let style: String
    }

    enum FakeRecoveryDuplicateLevel {
        case none
        case weak
        case strong
    }

    func playedAtTimestamp(for item: FakeHistoryMatch) -> Int {
        switch item.style {
        case "manual", "history":
            return item.startTimestamp
        default:
            guard let durationSeconds = item.durationSeconds else { return item.startTimestamp }
            return item.startTimestamp + durationSeconds
        }
    }

    func recoveryDuplicateLevel(
        item: FakeHistoryMatch,
        key: String,
        candidateStart: Int,
        candidatePlayedAt: Int,
        exactTolerance: Int = 10,
        playedTolerance: Int = 90,
        weakTolerance: Int
    ) -> FakeRecoveryDuplicateLevel {
        guard item.dedupeKey == key else { return .none }

        let weakTol = max(0, weakTolerance)
        let exactTol = max(0, exactTolerance)
        let playedTol = max(0, playedTolerance)
        let startDistance = abs(item.startTimestamp - candidateStart)

        if startDistance <= exactTol {
            return .strong
        }

        let playedAtDistance = abs(playedAtTimestamp(for: item) - candidatePlayedAt)

        if playedAtDistance <= playedTol {
            return .strong
        }

        if weakTol > 0, startDistance <= weakTol {
            return .weak
        }

        return .none
    }

    func shouldSkipPlaybackHistoryCandidate(
        ledgerContainsCandidate: Bool,
        duplicateLevel: FakeRecoveryDuplicateLevel,
        preventDuplicates: Bool
    ) -> Bool {
        guard preventDuplicates else { return false }
        return ledgerContainsCandidate || duplicateLevel == .strong
    }

    let recentThenHistory = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 1_000, durationSeconds: 200, style: "recentlyPlayed")
    expectEqual(
        "recently-played imported first is a strong duplicate when the playedAt matches",
        recoveryDuplicateLevel(item: recentThenHistory, key: "track-a", candidateStart: 1_015, candidatePlayedAt: 1_200, weakTolerance: 360),
        .strong
    )

    let historyThenRecent = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 1_000, durationSeconds: 200, style: "history")
    expectEqual(
        "listening-history imported first is a strong duplicate when the playedAt matches",
        recoveryDuplicateLevel(item: historyThenRecent, key: "track-a", candidateStart: 1_015, candidatePlayedAt: 1_000, weakTolerance: 360),
        .strong
    )

    expectEqual(
        "same-track recovery start inside exact tolerance is a strong duplicate",
        recoveryDuplicateLevel(item: historyThenRecent, key: "track-a", candidateStart: 1_008, candidatePlayedAt: 1_208, weakTolerance: 360),
        .strong
    )

    let exactRecoveryDuplicate = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 1_000, durationSeconds: 200, style: "history")
    expectEqual(
        "exact same-track recovery start remains a strong duplicate",
        recoveryDuplicateLevel(item: exactRecoveryDuplicate, key: "track-a", candidateStart: 1_000, candidatePlayedAt: 1_200, weakTolerance: 360),
        .strong
    )

    let weakOverlap = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 1_000, durationSeconds: 200, style: "history")
    expectEqual(
        "same track replayed a few minutes later is only a weak overlap, not a strong duplicate",
        recoveryDuplicateLevel(item: weakOverlap, key: "track-a", candidateStart: 1_180, candidatePlayedAt: 1_380, weakTolerance: 360),
        .weak
    )

    expectEqual(
        "same track outside exact and playedAt tolerances is not a strong duplicate",
        recoveryDuplicateLevel(item: weakOverlap, key: "track-a", candidateStart: 1_180, candidatePlayedAt: 1_380, weakTolerance: 0),
        .none
    )

    let missingDuration = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 1_500, durationSeconds: nil, style: "recentlyPlayed")
    expectEqual(
        "missing duration falls back safely and does not over-suppress cross-source imports",
        recoveryDuplicateLevel(item: missingDuration, key: "track-a", candidateStart: 1_600, candidatePlayedAt: 1_800, weakTolerance: 360),
        .weak
    )

    let manualSameTimestamp = FakeHistoryMatch(dedupeKey: "track-a", startTimestamp: 2_200, durationSeconds: 180, style: "manual")
    expectEqual(
        "manual scrobbles still block exact same-timestamp recovery imports",
        recoveryDuplicateLevel(item: manualSameTimestamp, key: "track-a", candidateStart: 2_200, candidatePlayedAt: 2_380, weakTolerance: 360),
        .strong
    )
    expect("listening-history ledger blocks import when duplicate prevention is enabled",
           shouldSkipPlaybackHistoryCandidate(ledgerContainsCandidate: true, duplicateLevel: .none, preventDuplicates: true))
    expect("listening-history ledger does not block import when duplicate prevention is disabled",
           !shouldSkipPlaybackHistoryCandidate(ledgerContainsCandidate: true, duplicateLevel: .none, preventDuplicates: false))
    expect("listening-history strong duplicate blocks import when duplicate prevention is enabled",
           shouldSkipPlaybackHistoryCandidate(ledgerContainsCandidate: false, duplicateLevel: .strong, preventDuplicates: true))
    expect("listening-history strong duplicate does not block import when duplicate prevention is disabled",
           !shouldSkipPlaybackHistoryCandidate(ledgerContainsCandidate: false, duplicateLevel: .strong, preventDuplicates: false))

    let differentTrack = FakeHistoryMatch(dedupeKey: "track-b", startTimestamp: 2_200, durationSeconds: 180, style: "history")
    expectEqual(
        "dedupe key mismatches never suppress a recovery import",
        recoveryDuplicateLevel(item: differentTrack, key: "track-a", candidateStart: 2_200, candidatePlayedAt: 2_380, weakTolerance: 360),
        .none
    )

    // ─── Dedup nearest-match selection ────────────────────────────────────────────
}
