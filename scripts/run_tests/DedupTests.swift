import Foundation

func runDedupTimestampToleranceTests() {
    // ─── Duplicate scrobble timestamp tolerance ───────────────────────────────────
    // Tests containsSimilar matching behavior on real ScrobbleBacklog.Item entries.
    // Deduplication window: 10 seconds (tolerance = 10).

    section("Dedup · Timestamp tolerance (10s window)")

    func makeItem(key: String, ts: Int, origin: ScrobbleBacklog.Origin? = nil) -> ScrobbleBacklog.Item {
        ScrobbleBacklog.Item(
            id: UUID(),
            track: Track(artist: key, title: "Test Song"),
            startTimestamp: ts,
            origin: origin,
            wasAppleMusicFavorite: false,
            queuedAt: Date(),
            attemptCount: 0
        )
    }

    func dedupeKey(for artistKey: String) -> String {
        Track(artist: artistKey, title: "Test Song").dedupeKey
    }

    func containsSimilar(items: [ScrobbleBacklog.Item], key: String, around ts: Int, tolerance: Int) -> Bool {
        let tol = max(0, tolerance)
        return items.contains(where: { $0.track.dedupeKey == key && abs($0.startTimestamp - ts) <= tol })
    }

    let existing = [makeItem(key: "track-a", ts: 1000)]
    let keyA = dedupeKey(for: "track-a")
    let keyB = dedupeKey(for: "track-b")

    expect("same track at T+5 is duplicate",    containsSimilar(items: existing, key: keyA, around: 1005, tolerance: 10))
    expect("same track at T+10 is duplicate",   containsSimilar(items: existing, key: keyA, around: 1010, tolerance: 10))
    expect("same track at T+11 is NOT dup",     !containsSimilar(items: existing, key: keyA, around: 1011, tolerance: 10))
    expect("different track same ts is NOT dup",!containsSimilar(items: existing, key: keyB, around: 1000, tolerance: 10))
    expect("same track at T-10 is duplicate",   containsSimilar(items: existing, key: keyA, around: 990, tolerance: 10))
    expect("tolerance=0 only matches exact ts", containsSimilar(items: existing, key: keyA, around: 1000, tolerance: 0))
    expect("tolerance=0 doesn't match T+1",     !containsSimilar(items: existing, key: keyA, around: 1001, tolerance: 0))
    expect("negative tolerance clamps to 0",    !containsSimilar(items: existing, key: keyA, around: 1001, tolerance: -5))
}

func runDedupNearestMatchTests() {
    section("Dedup · Nearest matching timestamp is selected")

    func makeItem(key: String, ts: Int) -> ScrobbleBacklog.Item {
        ScrobbleBacklog.Item(
            id: UUID(),
            track: Track(artist: key, title: "Test Song"),
            startTimestamp: ts,
            origin: nil,
            wasAppleMusicFavorite: false,
            queuedAt: Date(),
            attemptCount: 0
        )
    }

    func dedupeKey(for artistKey: String) -> String {
        Track(artist: artistKey, title: "Test Song").dedupeKey
    }

    func mostSimilar(items: [ScrobbleBacklog.Item], key: String, around ts: Int, tolerance: Int) -> ScrobbleBacklog.Item? {
        let tol = max(0, tolerance)
        return items
            .filter { $0.track.dedupeKey == key && abs($0.startTimestamp - ts) <= tol }
            .min(by: { abs($0.startTimestamp - ts) < abs($1.startTimestamp - ts) })
    }

    let similarItems = [
        makeItem(key: "track-a", ts: 980),
        makeItem(key: "track-a", ts: 1008),
        makeItem(key: "track-a", ts: 1015),
        makeItem(key: "track-b", ts: 1001),
    ]

    let keyA = dedupeKey(for: "track-a")
    let keyB = dedupeKey(for: "track-b")

    expect("nearest item within tolerance is returned", mostSimilar(items: similarItems, key: keyA, around: 1005, tolerance: 20)?.startTimestamp == 1008,
           detail: "got \(mostSimilar(items: similarItems, key: keyA, around: 1005, tolerance: 20)?.startTimestamp ?? -1)")
    expect("out-of-window candidates return nil", mostSimilar(items: similarItems, key: keyA, around: 1050, tolerance: 10) == nil)
    expect("different dedupeKey is ignored", mostSimilar(items: similarItems, key: keyB, around: 1005, tolerance: 10)?.startTimestamp == 1001,
           detail: "got \(mostSimilar(items: similarItems, key: keyB, around: 1005, tolerance: 10)?.startTimestamp ?? -1)")
}

func runDedupRandomizedPreventionTests() {
    section("Dedup · Seeded randomized duplicate prevention")

    struct SeededRandomNumberGenerator {
        private(set) var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % span)
        }

        mutating func bool() -> Bool {
            next().isMultiple(of: 2)
        }
    }

    func dedupeKey(for artistKey: String) -> String {
        Track(artist: artistKey, title: "Test Song").dedupeKey
    }

    func containsSimilar(items: [ScrobbleBacklog.Item], key: String, around ts: Int, tolerance: Int) -> Bool {
        let tol = max(0, tolerance)
        return items.contains(where: { $0.track.dedupeKey == key && abs($0.startTimestamp - ts) <= tol })
    }

    func simulateEnqueue(
        queue: inout [ScrobbleBacklog.Item],
        artistKey: String,
        ts: Int,
        origin: ScrobbleBacklog.Origin?,
        allowExactDuplicates: Bool = false
    ) -> Bool {
        let key = dedupeKey(for: artistKey)
        let allowsOriginExactDuplicates = origin == .playbackHistory
        if !allowExactDuplicates,
           !allowsOriginExactDuplicates,
           queue.contains(where: { $0.track.dedupeKey == key && $0.startTimestamp == ts })
        {
            return false
        }

        queue.append(ScrobbleBacklog.Item(
            id: UUID(),
            track: Track(artist: artistKey, title: "Test Song"),
            startTimestamp: ts,
            origin: origin,
            wasAppleMusicFavorite: false,
            queuedAt: Date(),
            attemptCount: 0
        ))
        return true
    }

    let seed: UInt64 = 0x5C0BB1E5
    var rng = SeededRandomNumberGenerator(state: seed)
    var timestampFailures: [String] = []
    var enqueueFailures: [String] = []
    let tolerance = 10

    for index in 0..<250 {
        let artistKey = "track-\(rng.int(in: 0...24))"
        let otherArtistKey = "\(artistKey)-other"
        let key = dedupeKey(for: artistKey)
        let otherKey = dedupeKey(for: otherArtistKey)
        let baseTimestamp = 1_700_000_000 + rng.int(in: 0...80_000)
        let existing = [ScrobbleBacklog.Item(
            id: UUID(),
            track: Track(artist: artistKey, title: "Test Song"),
            startTimestamp: baseTimestamp,
            origin: nil,
            wasAppleMusicFavorite: false,
            queuedAt: Date(),
            attemptCount: 0
        )]
        let insideOffset = rng.bool() ? rng.int(in: 0...tolerance) : -rng.int(in: 0...tolerance)
        let outsideMagnitude = rng.int(in: (tolerance + 1)...(tolerance + 90))
        let outsideOffset = rng.bool() ? outsideMagnitude : -outsideMagnitude
        let nearbyOffset = rng.int(in: -tolerance...tolerance)

        if !containsSimilar(items: existing, key: key, around: baseTimestamp + insideOffset, tolerance: tolerance) {
            timestampFailures.append("seed=\(seed) case=\(index) key=\(key) base=\(baseTimestamp) offset=\(insideOffset) expected duplicate")
        }

        if containsSimilar(items: existing, key: key, around: baseTimestamp + outsideOffset, tolerance: tolerance) {
            timestampFailures.append("seed=\(seed) case=\(index) key=\(key) base=\(baseTimestamp) offset=\(outsideOffset) expected allowed")
        }

        if containsSimilar(items: existing, key: otherKey, around: baseTimestamp + nearbyOffset, tolerance: tolerance) {
            timestampFailures.append("seed=\(seed) case=\(index) key=\(otherKey) base=\(baseTimestamp) offset=\(nearbyOffset) expected different track allowed")
        }

        if !containsSimilar(items: existing, key: key, around: baseTimestamp, tolerance: -rng.int(in: 1...40)) {
            timestampFailures.append("seed=\(seed) case=\(index) key=\(key) base=\(baseTimestamp) negative tolerance should allow exact match")
        }

        if containsSimilar(items: existing, key: key, around: baseTimestamp + 1, tolerance: -rng.int(in: 1...40)) {
            timestampFailures.append("seed=\(seed) case=\(index) key=\(key) base=\(baseTimestamp) negative tolerance should reject non-exact match")
        }
    }

    var queue: [ScrobbleBacklog.Item] = []
    var expectedExactDuplicates = 0
    var expectedAccepted = 0

    for index in 0..<180 {
        let artistKey = "queued-track-\(rng.int(in: 0...17))"
        let key = dedupeKey(for: artistKey)
        let timestamp = 2_000_000_000 + rng.int(in: 0...30)
        let origin: ScrobbleBacklog.Origin? = rng.int(in: 0...5) == 0 ? .playbackHistory : nil
        let allowExactDuplicates = rng.int(in: 0...11) == 0
        let shouldReject = !allowExactDuplicates &&
            origin != .playbackHistory &&
            queue.contains(where: { $0.track.dedupeKey == key && $0.startTimestamp == timestamp })
        let accepted = simulateEnqueue(
            queue: &queue,
            artistKey: artistKey,
            ts: timestamp,
            origin: origin,
            allowExactDuplicates: allowExactDuplicates
        )

        if accepted == shouldReject {
            enqueueFailures.append("seed=\(seed) case=\(index) key=\(key) ts=\(timestamp) origin=\(origin?.rawValue ?? "nil") allowExactDuplicates=\(allowExactDuplicates) accepted=\(accepted)")
        }

        if shouldReject {
            expectedExactDuplicates += 1
        } else {
            expectedAccepted += 1
        }
    }

    expect("randomized timestamp duplicate checks match tolerance rules",
           timestampFailures.isEmpty,
           detail: timestampFailures.prefix(3).joined(separator: " | "))
    expect("randomized enqueue policy rejects only exact non-playback-history duplicates",
           enqueueFailures.isEmpty,
           detail: enqueueFailures.prefix(3).joined(separator: " | "))
    expectEqual("randomized enqueue accepted count matches expected policy", queue.count, expectedAccepted)
    expect("randomized enqueue generated at least one rejected duplicate",
           expectedExactDuplicates > 0,
           detail: "seed=\(seed) rejected=\(expectedExactDuplicates)")
}


