import Foundation

func runBacklogTests() {
    section("Backlog · 10-minute backoff")

    func shouldSkipDueToBackoff(lastAttemptAt: Date?, now: Date, ignoreBackoff: Bool) -> Bool {
        guard !ignoreBackoff, let last = lastAttemptAt else { return false }
        return now.timeIntervalSince(last) < 10 * 60
    }

    let backoffNow = Date()
    expectFalse("nil lastAttemptAt = always attempt",       shouldSkipDueToBackoff(lastAttemptAt: nil, now: backoffNow, ignoreBackoff: false))
    expectTrue("failed 5 min ago = skip",                  shouldSkipDueToBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-5*60), now: backoffNow, ignoreBackoff: false))
    expectTrue("failed 9m59s ago = skip",                  shouldSkipDueToBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-599), now: backoffNow, ignoreBackoff: false))
    expectFalse("failed exactly 10 min ago = retry",        shouldSkipDueToBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-600), now: backoffNow, ignoreBackoff: false))
    expectFalse("failed 11 min ago = retry",                shouldSkipDueToBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-660), now: backoffNow, ignoreBackoff: false))
    expectFalse("ignoreBackoff=true bypasses cooldown",     shouldSkipDueToBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-1), now: backoffNow, ignoreBackoff: true))

    // ─── Backlog exponential backoff ──────────────────────────────────────────────
    section("Backlog · Exponential backoff schedule")

    func shouldSkipDueToExponentialBackoff(lastAttemptAt: Date?, attemptCount: Int, now: Date, ignoreBackoff: Bool, jitter: TimeInterval = 0) -> Bool {
        guard !ignoreBackoff, let last = lastAttemptAt else { return false }
        let exponent = max(0, min(attemptCount - 1, 6))
        let baseDelay = min(TimeInterval(60 * (1 << exponent)), 60 * 60)
        return now.timeIntervalSince(last) < baseDelay + jitter
    }

    expectTrue("attempt 1 waits 60s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-59), attemptCount: 1, now: backoffNow, ignoreBackoff: false))
    expectFalse("attempt 1 retries at 60s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-60), attemptCount: 1, now: backoffNow, ignoreBackoff: false))
    expectTrue("attempt 2 waits 120s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-119), attemptCount: 2, now: backoffNow, ignoreBackoff: false))
    expectTrue("attempt 3 waits 240s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-239), attemptCount: 3, now: backoffNow, ignoreBackoff: false))
    expectTrue("attempt 8 caps at 3600s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-3599), attemptCount: 8, now: backoffNow, ignoreBackoff: false))
    expectFalse("attempt 8 retries at 3600s", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-3600), attemptCount: 8, now: backoffNow, ignoreBackoff: false))
    expectFalse("ignoreBackoff bypasses exponential delay", shouldSkipDueToExponentialBackoff(lastAttemptAt: backoffNow.addingTimeInterval(-1), attemptCount: 8, now: backoffNow, ignoreBackoff: true))

    // ─── Backlog max batch size ───────────────────────────────────────────────────
    section("Backlog · Max batch size (25 items)")

    func simulateBatchFlush(queueSize: Int, maxItems: Int) -> (processed: Int, remaining: Int) {
        var queue = Array(0..<queueSize)
        var processed = 0
        let idx = 0
        while idx < queue.count, processed < maxItems {
            queue.remove(at: idx)
            processed += 1
        }
        return (processed, queue.count)
    }

    let batch30 = simulateBatchFlush(queueSize: 30, maxItems: 25)
    expectEqual("30-item queue: processes exactly 25", batch30.processed, 25)
    expectEqual("30-item queue: 5 remain", batch30.remaining, 5)

    let batch10 = simulateBatchFlush(queueSize: 10, maxItems: 25)
    expectEqual("10-item queue: processes all 10", batch10.processed, 10)
    expectEqual("10-item queue: 0 remain", batch10.remaining, 0)

    let batch0 = simulateBatchFlush(queueSize: 0, maxItems: 25)
    expectEqual("empty queue: processes 0", batch0.processed, 0)

    // ─── Backlog enqueue deduplication ───────────────────────────────────────────
    section("Backlog · Enqueue exact-duplicate prevention")

    struct BacklogEntry { let key: String; let ts: Int; let origin: String? }

    func simulateEnqueue(queue: inout [BacklogEntry], key: String, ts: Int, origin: String?, allowDuplicates: Bool = false) -> Bool {
        let allowsOriginExactDuplicates = origin == "playbackHistory"
        if !allowDuplicates, !allowsOriginExactDuplicates, queue.contains(where: { $0.key == key && $0.ts == ts }) {
            return false // rejected
        }
        queue.append(BacklogEntry(key: key, ts: ts, origin: origin))
        return true // accepted
    }

    var bq: [BacklogEntry] = []
    let added1 = simulateEnqueue(queue: &bq, key: "track-a", ts: 1000, origin: nil)
    let added2 = simulateEnqueue(queue: &bq, key: "track-a", ts: 1000, origin: nil)
    let added3 = simulateEnqueue(queue: &bq, key: "track-a", ts: 2000, origin: nil)
    let added4 = simulateEnqueue(queue: &bq, key: "track-b", ts: 1000, origin: nil)
    let added5 = simulateEnqueue(queue: &bq, key: "track-a", ts: 3000, origin: "playbackHistory")
    let added6 = simulateEnqueue(queue: &bq, key: "track-a", ts: 3000, origin: "playbackHistory")
    let added7 = simulateEnqueue(queue: &bq, key: "track-a", ts: 1000, origin: nil, allowDuplicates: true)

    expectTrue("first enqueue accepted", added1)
    expectFalse("exact duplicate rejected", added2)
    expectTrue("same track different timestamp accepted", added3)
    expectTrue("different track same timestamp accepted", added4)
    expectTrue("playback-history exact duplicate accepted", added5 && added6)
    expectTrue("exact duplicate accepted when explicitly allowed", added7)
    expectEqual("queue has 6 items after allowed duplicate", bq.count, 6)

    section("Backlog · Recovery duplicate strength using production RecoveryDuplicateMatcher")

    let sampleTrack = Track(artist: "Radiohead", title: "Karma Police", album: "OK Computer", durationSeconds: 200)

    let evalPlayedAtMatch = RecoveryDuplicateMatcher.evaluate(
        storedTrack: sampleTrack,
        storedStartTimestamp: 1_000,
        storedSource: .recentlyPlayed,
        candidateTrack: sampleTrack,
        candidateStartTimestamp: 1_020,
        candidatePlayedAtTimestamp: 1_200,
        weakStartToleranceSeconds: 360
    )
    expectEqual("recently-played backlog rows create strong duplicates when playedAt matches", evalPlayedAtMatch.level, .strongDuplicate)

    let evalExactStartMatch = RecoveryDuplicateMatcher.evaluate(
        storedTrack: sampleTrack,
        storedStartTimestamp: 1_000,
        storedSource: .recentlyPlayed,
        candidateTrack: sampleTrack,
        candidateStartTimestamp: 1_000,
        candidatePlayedAtTimestamp: 1_200,
        weakStartToleranceSeconds: 360
    )
    expectEqual("exact same-track recovery start remains a strong duplicate", evalExactStartMatch.level, .strongDuplicate)

    let evalManualWeakMatch = RecoveryDuplicateMatcher.evaluate(
        storedTrack: sampleTrack,
        storedStartTimestamp: 1_000,
        storedSource: .manual,
        candidateTrack: sampleTrack,
        candidateStartTimestamp: 1_120,
        candidatePlayedAtTimestamp: 1_200,
        weakStartToleranceSeconds: 360
    )
    expectEqual("manual backlog rows keep weak-start duplicate behavior instead of using inferred end times", evalManualWeakMatch.level, .weakDuplicate)
}

func runBacklogTimestampPreservationTests() {
    section("Backlog · Timestamp preservation")

    struct PreservedBacklogEntry {
        let originalTimestamp: Int
        var attemptCount: Int = 0
    }

    func simulateRetryPreservingTimestamp(entry: inout PreservedBacklogEntry) -> Int {
        entry.attemptCount += 1
        return entry.originalTimestamp
    }

    var preservedEntry = PreservedBacklogEntry(originalTimestamp: 1_234_567_890)
    let preservedTimestamp = simulateRetryPreservingTimestamp(entry: &preservedEntry)
    expectEqual("backlog retry preserves the original captured timestamp", preservedTimestamp, 1_234_567_890)
    expectEqual("backlog retry only increments attempts, not timestamp", preservedEntry.attemptCount, 1)
}

func runBacklogCleanupTests() {
    section("Backlog · Storage cleanup")

    struct CleanupBacklogEntry {
        let id: Int
        let startTimestamp: Int
        let queuedAt: Int
        let attemptCount: Int
    }

    struct CleanupResult {
        let entries: [CleanupBacklogEntry]
        let removedTooOldCount: Int
        let removedTooManyFailedAttemptsCount: Int
        let removedTooManyItemsCount: Int
    }

    func cleanup(
        _ entries: [CleanupBacklogEntry],
        nowTimestamp: Int,
        maxAgeSeconds: Int = 14 * 24 * 60 * 60,
        maxPendingItems: Int = 1_000,
        maxAttemptCount: Int = 10
    ) -> CleanupResult {
        var working = entries
        let originalCount = working.count
        let cutoffTimestamp = nowTimestamp - maxAgeSeconds

        working.removeAll { $0.attemptCount >= maxAttemptCount }
        let removedTooManyFailedAttemptsCount = originalCount - working.count

        let countAfterFailedAttemptPrune = working.count
        working.removeAll { $0.startTimestamp > 0 && $0.startTimestamp < cutoffTimestamp }
        let removedTooOldCount = countAfterFailedAttemptPrune - working.count

        var removedTooManyItemsCount = 0
        if working.count > maxPendingItems {
            working.sort {
                if $0.startTimestamp == $1.startTimestamp {
                    return $0.queuedAt > $1.queuedAt
                }
                return $0.startTimestamp > $1.startTimestamp
            }
            removedTooManyItemsCount = working.count - maxPendingItems
            working.removeLast(removedTooManyItemsCount)
        }

        return CleanupResult(
            entries: working,
            removedTooOldCount: removedTooOldCount,
            removedTooManyFailedAttemptsCount: removedTooManyFailedAttemptsCount,
            removedTooManyItemsCount: removedTooManyItemsCount
        )
    }

    let now = 2_000_000_000
    let oldTimestamp = now - (15 * 24 * 60 * 60)
    let recentTimestamp = now - 60

    let ageResult = cleanup([
        CleanupBacklogEntry(id: 1, startTimestamp: oldTimestamp, queuedAt: oldTimestamp, attemptCount: 0),
        CleanupBacklogEntry(id: 2, startTimestamp: recentTimestamp, queuedAt: recentTimestamp, attemptCount: 0),
    ], nowTimestamp: now)
    expectEqual("cleanup removes entries older than 14 days", ageResult.removedTooOldCount, 1)
    expectEqual("cleanup keeps recent entries", ageResult.entries.map(\.id), [2])

    let failedResult = cleanup([
        CleanupBacklogEntry(id: 1, startTimestamp: recentTimestamp, queuedAt: recentTimestamp, attemptCount: 9),
        CleanupBacklogEntry(id: 2, startTimestamp: recentTimestamp + 1, queuedAt: recentTimestamp + 1, attemptCount: 10),
    ], nowTimestamp: now)
    expectEqual("cleanup removes entries with 10 failed attempts", failedResult.removedTooManyFailedAttemptsCount, 1)
    expectEqual("cleanup keeps entries below failed-attempt cap", failedResult.entries.map(\.id), [1])

    let oversizedEntries = (0..<1_010).map { index in
        CleanupBacklogEntry(
            id: index,
            startTimestamp: recentTimestamp + index,
            queuedAt: recentTimestamp + index,
            attemptCount: 0
        )
    }
    let oversizedResult = cleanup(oversizedEntries, nowTimestamp: now)
    expectEqual("cleanup trims oversized backlog to 1000 entries", oversizedResult.entries.count, 1_000)
    expectEqual("cleanup reports excess trimmed count", oversizedResult.removedTooManyItemsCount, 10)
    expect("cleanup preserves newest timestamp when trimming", oversizedResult.entries.contains(where: { $0.id == 1_009 }))
    expect("cleanup drops oldest timestamp when trimming", !oversizedResult.entries.contains(where: { $0.id == 0 }))

    let sameTimestampResult = cleanup([
        CleanupBacklogEntry(id: 1, startTimestamp: recentTimestamp, queuedAt: recentTimestamp, attemptCount: 0),
        CleanupBacklogEntry(id: 2, startTimestamp: recentTimestamp, queuedAt: recentTimestamp + 1, attemptCount: 0),
        CleanupBacklogEntry(id: 3, startTimestamp: recentTimestamp, queuedAt: recentTimestamp + 2, attemptCount: 0),
    ], nowTimestamp: now, maxPendingItems: 2)
    expectEqual("cleanup breaks equal timestamps by newest queuedAt", sameTimestampResult.entries.map(\.id), [3, 2])

    let clearResult = cleanup([], nowTimestamp: now)
    expectEqual("clear-all equivalent leaves no pending entries", clearResult.entries.count, 0)

    section("Backlog · Compact persistence migration")

    struct FullTrack: Codable {
        let artist: String
        let title: String
        let album: String?
        let albumArtist: String?
        let durationSeconds: Double?
        let usesFallbackDuration: Bool?
        let persistentID: UInt64?
        let playbackStoreID: String?
        let isCompilation: Bool?
    }

    struct LegacyItem: Codable {
        let id: UUID
        let track: FullTrack
        let startTimestamp: Int
        let origin: String?
        let wasAppleMusicFavorite: Bool?
        let queuedAt: Int
        let attemptCount: Int
        let lastAttemptAt: Int?
    }

    struct CompactTrack: Codable {
        let a: String
        let t: String
        let al: String?
        let aa: String?
        let d: Double?
        let uf: Bool?
        let p: UInt64?
        let ps: String?
        let ic: Bool?
    }

    struct CompactItem: Codable {
        let i: UUID
        let t: CompactTrack
        let s: Int
        let o: String?
        let f: Bool?
        let q: Int
        let a: Int
        let l: Int?
    }

    let legacyItems = (0..<10).map { index in
        LegacyItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))") ?? UUID(),
            track: FullTrack(
                artist: "Artist \(index)",
                title: "Song \(index)",
                album: "Album \(index)",
                albumArtist: "Album Artist \(index)",
                durationSeconds: 180,
                usesFallbackDuration: false,
                persistentID: UInt64(index + 1),
                playbackStoreID: "store-\(index)",
                isCompilation: false
            ),
            startTimestamp: 10_000 + index,
            origin: "live",
            wasAppleMusicFavorite: index.isMultiple(of: 2),
            queuedAt: 20_000 + index,
            attemptCount: index % 3,
            lastAttemptAt: 30_000 + index
        )
    }
    let compactItems = legacyItems.map { item in
        CompactItem(
            i: item.id,
            t: CompactTrack(
                a: item.track.artist,
                t: item.track.title,
                al: item.track.album,
                aa: item.track.albumArtist,
                d: item.track.durationSeconds,
                uf: item.track.usesFallbackDuration,
                p: item.track.persistentID,
                ps: item.track.playbackStoreID,
                ic: item.track.isCompilation
            ),
            s: item.startTimestamp,
            o: item.origin,
            f: item.wasAppleMusicFavorite,
            q: item.queuedAt,
            a: item.attemptCount,
            l: item.lastAttemptAt
        )
    }

    let encoder = JSONEncoder()
    let legacyData = try! encoder.encode(legacyItems)
    let compactData = try! encoder.encode(compactItems)
    expect("compact backlog persistence shrinks representative payloads", compactData.count < legacyData.count, detail: "legacy=\(legacyData.count), compact=\(compactData.count)")

    // ─── Backlog batch scrobble sentItems tracking ──────────────────────────────
    section("Backlog · Batch scrobble sentItems tracking")

    struct BatchItem {
        let id: UUID
        var pendingServices: Set<String>
    }

    func simulateBatchFlushWithIDs(
        items: inout [BatchItem],
        batchScrobbledIDs: Set<UUID>
    ) -> [UUID] {
        var idx = 0
        var sentIDs: [UUID] = []

        while idx < items.count {
            let item = items[idx]
            let scrobbledInThisFlush = batchScrobbledIDs.contains(item.id)

            if item.pendingServices.isEmpty && !scrobbledInThisFlush {
                items.remove(at: idx)
                continue
            }

            if item.pendingServices.isEmpty {
                if scrobbledInThisFlush {
                    sentIDs.append(item.id)
                }
                items.remove(at: idx)
            } else {
                idx += 1
            }
        }
        return sentIDs
    }

    let id1 = UUID()
    let id2 = UUID()
    var batchQueue = [
        BatchItem(id: id1, pendingServices: []),
        BatchItem(id: id2, pendingServices: [])
    ]
    let sentBatchIDs = simulateBatchFlushWithIDs(items: &batchQueue, batchScrobbledIDs: [id1, id2])

    expect("batch-scrobbled items are returned in sentItems", sentBatchIDs.count == 2, detail: "got \(sentBatchIDs.count)")
    expect("batch-scrobbled items are removed from queue after flush", batchQueue.isEmpty)
}
