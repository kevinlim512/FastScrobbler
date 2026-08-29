import Foundation
import OSLog

actor ScrobbleBacklog {
    enum Origin: String, Codable, Sendable {
        case live
        case playbackHistory
        case recentlyPlayed
        case manual
    }

    struct Item: Codable, Hashable, Sendable {
        var id: UUID
        var track: Track
        var startTimestamp: Int
        var origin: Origin?
        var wasAppleMusicFavorite: Bool?
        var queuedAt: Date
        var attemptCount: Int
        var lastAttemptAt: Date?
        var pendingServices: Set<ScrobbleService> = [.lastfm, .listenbrainz]
    }

    struct FlushResult: Sendable {
        struct SentItem: Sendable, Hashable {
            var track: Track
            var startTimestamp: Int
            var scrobbledAt: Date
            var origin: Origin?
            var lovedOnLastFM: Bool
        }

        var sentCount: Int
        var skippedCount: Int
        var remainingCount: Int
        var sentItems: [SentItem]
    }

    struct CleanupResult: Sendable, Equatable {
        var removedTooOldCount: Int
        var removedTooManyFailedAttemptsCount: Int
        var removedTooManyItemsCount: Int
        var remainingCount: Int

        var removedCount: Int {
            removedTooOldCount + removedTooManyFailedAttemptsCount + removedTooManyItemsCount
        }
    }

    static let shared = ScrobbleBacklog()

    private enum CleanupLimits {
        static let maxPendingItems = 1_000
        static let maxItemAge: TimeInterval = 14 * 24 * 60 * 60
        static let maxAttemptCount = 10
    }

    private struct PersistedTrack: Codable {
        var artist: String
        var title: String
        var album: String?
        var albumArtist: String?
        var durationSeconds: TimeInterval?
        var usesFallbackDuration: Bool?
        var persistentID: UInt64?
        var playbackStoreID: String?
        var isCompilation: Bool?

        private enum CodingKeys: String, CodingKey {
            case artist = "a"
            case title = "t"
            case album = "al"
            case albumArtist = "aa"
            case durationSeconds = "d"
            case usesFallbackDuration = "uf"
            case persistentID = "p"
            case playbackStoreID = "ps"
            case isCompilation = "ic"
        }

        init(track: Track) {
            artist = track.artist
            title = track.title
            album = track.album
            albumArtist = track.albumArtist
            durationSeconds = track.durationSeconds
            usesFallbackDuration = track.usesFallbackDuration
            persistentID = track.persistentID
            playbackStoreID = track.playbackStoreID
            isCompilation = track.isCompilation
        }

        var track: Track {
            Track(
                artist: artist,
                title: title,
                album: album,
                albumArtist: albumArtist,
                durationSeconds: durationSeconds,
                usesFallbackDuration: usesFallbackDuration,
                persistentID: persistentID,
                playbackStoreID: playbackStoreID,
                isCompilation: isCompilation
            )
        }
    }

    private struct PersistedItem: Codable {
        var id: UUID
        var track: PersistedTrack
        var startTimestamp: Int
        var origin: Origin?
        var wasAppleMusicFavorite: Bool?
        var queuedAt: Date
        var attemptCount: Int
        var lastAttemptAt: Date?
        var pendingServices: Set<ScrobbleService>?

        private enum CodingKeys: String, CodingKey {
            case id = "i"
            case track = "t"
            case startTimestamp = "s"
            case origin = "o"
            case wasAppleMusicFavorite = "f"
            case queuedAt = "q"
            case attemptCount = "a"
            case lastAttemptAt = "l"
            case pendingServices = "psv"
        }

        init(item: Item) {
            id = item.id
            track = PersistedTrack(track: item.track)
            startTimestamp = item.startTimestamp
            origin = item.origin
            wasAppleMusicFavorite = item.wasAppleMusicFavorite
            queuedAt = item.queuedAt
            attemptCount = item.attemptCount
            lastAttemptAt = item.lastAttemptAt
            pendingServices = item.pendingServices
        }

        var item: Item {
            Item(
                id: id,
                track: track.track,
                startTimestamp: startTimestamp,
                origin: origin,
                wasAppleMusicFavorite: wasAppleMusicFavorite,
                queuedAt: queuedAt,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                pendingServices: (pendingServices == nil || pendingServices?.isEmpty == true) ? [.lastfm] : pendingServices!
            )
        }
    }

    private let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleBacklog")
    private var isLoaded = false
    private var isFlushing = false
    private var items: [Item] = []

    private init() {}

    func pendingCount() async -> Int {
        await loadIfNeeded()
        return items.count
    }

    func syncedItemsSnapshot() async -> [Item] {
        await loadIfNeeded()
        return items
    }

    func storageSizeBytes() async -> Int64 {
        let urls = [sharedFileURL(), legacyFileURL()].compactMap { $0 }
        var seenPaths = Set<String>()
        var total: Int64 = 0

        for url in urls {
            guard seenPaths.insert(url.path).inserted else { continue }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                continue
            }
            total += size.int64Value
        }

        return total
    }

    @discardableResult
    func cleanupNow() async -> CleanupResult {
        await loadIfNeeded()
        let result = pruneItems(now: Date())
        if result.removedCount > 0 {
            logCleanup(result)
        }
        await save(pruneBeforeWrite: false)
        return result
    }

    func clearAll() async {
        await loadIfNeeded()
        guard !items.isEmpty else {
            await save(pruneBeforeWrite: false)
            return
        }
        items = []
        await save(pruneBeforeWrite: false)
    }

    func enqueue(track: Track, startTimestamp: Int) async {
        await enqueue(track: track, startTimestamp: startTimestamp, origin: nil)
    }

    func enqueue(track: Track, startTimestamp: Int, origin: Origin?) async {
        await enqueue(
            track: track,
            startTimestamp: startTimestamp,
            origin: origin,
            wasAppleMusicFavorite: nil,
            pendingServices: [.lastfm, .listenbrainz],
            allowExactDuplicates: false
        )
    }

    func enqueue(
        track: Track,
        startTimestamp: Int,
        origin: Origin?,
        wasAppleMusicFavorite: Bool?,
        pendingServices: Set<ScrobbleService> = [.lastfm, .listenbrainz],
        allowExactDuplicates: Bool = false
    ) async {
        await loadIfNeeded()
        _ = pruneItems(now: Date())

        let allowsOriginExactDuplicates = origin == .playbackHistory

        if !allowExactDuplicates,
           !allowsOriginExactDuplicates,
           items.contains(where: { $0.startTimestamp == startTimestamp && $0.track.dedupeKey == track.dedupeKey })
        {
            return
        }

        items.append(
            Item(
                id: UUID(),
                track: track,
                startTimestamp: startTimestamp,
                origin: origin,
                wasAppleMusicFavorite: wasAppleMusicFavorite,
                queuedAt: Date(),
                attemptCount: 0,
                lastAttemptAt: nil,
                pendingServices: pendingServices
            )
        )
        await save()
    }

    func isMostRecentScrobble(dedupeKey: String) async -> Bool {
        await loadIfNeeded()
        return items.max(by: { $0.startTimestamp < $1.startTimestamp })?.track.dedupeKey == dedupeKey
    }

    func containsSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) async -> Bool {
        await loadIfNeeded()
        let tol = max(0, toleranceSeconds)
        return items.contains(where: {
            $0.track.dedupeKey == track.dedupeKey && abs($0.startTimestamp - startTimestamp) <= tol
        })
    }

    func mostSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) async -> Item? {
        await loadIfNeeded()
        let tol = max(0, toleranceSeconds)
        return items
            .filter { $0.track.dedupeKey == track.dedupeKey && abs($0.startTimestamp - startTimestamp) <= tol }
            .min(by: { abs($0.startTimestamp - startTimestamp) < abs($1.startTimestamp - startTimestamp) })
    }

    func recoveryDuplicateMatch(
        track: Track,
        startTimestamp: Int,
        playedAt: Date,
        exactStartToleranceSeconds: Int = RecoveryDuplicateMatcher.balancedExactStartToleranceSeconds,
        playedAtToleranceSeconds: Int = RecoveryDuplicateMatcher.balancedPlayedAtToleranceSeconds,
        weakStartToleranceSeconds: Int
    ) async -> RecoveryDuplicateMatch<Item>? {
        await loadIfNeeded()
        let candidatePlayedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        var bestItem: Item?
        var bestEvaluation: RecoveryDuplicateMatcher.Evaluation?

        for item in items {
            let evaluation = RecoveryDuplicateMatcher.evaluate(
                storedTrack: item.track,
                storedStartTimestamp: item.startTimestamp,
                storedSource: recoveryDuplicateStoredSource(for: item.origin),
                candidateTrack: track,
                candidateStartTimestamp: startTimestamp,
                candidatePlayedAtTimestamp: candidatePlayedAtTimestamp,
                exactStartToleranceSeconds: exactStartToleranceSeconds,
                playedAtToleranceSeconds: playedAtToleranceSeconds,
                weakStartToleranceSeconds: weakStartToleranceSeconds
            )
            guard evaluation.level != .none else { continue }
            if RecoveryDuplicateMatcher.isPreferred(evaluation, over: bestEvaluation) {
                bestItem = item
                bestEvaluation = evaluation
            }
        }

        guard let bestItem, let bestEvaluation else { return nil }
        return RecoveryDuplicateMatch(level: bestEvaluation.level, matched: bestItem)
    }

    func containsPlaybackHistoryMatch(track: Track, playedAt: Date, endTimestampToleranceSeconds: Int) async -> Bool {
        await loadIfNeeded()
        let playedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        let tol = max(0, endTimestampToleranceSeconds)

        return items.contains(where: { item in
            let evaluation = RecoveryDuplicateMatcher.evaluate(
                storedTrack: item.track,
                storedStartTimestamp: item.startTimestamp,
                storedSource: recoveryDuplicateStoredSource(for: item.origin),
                candidateTrack: track,
                candidateStartTimestamp: playedAtTimestamp,
                candidatePlayedAtTimestamp: playedAtTimestamp,
                exactStartToleranceSeconds: 0,
                playedAtToleranceSeconds: tol,
                weakStartToleranceSeconds: 0
            )
            return evaluation.level == .strongDuplicate
        })
    }

    func playbackHistoryImportMatchCount(
        track: Track,
        startTimestamp: Int,
        playedAt: Date,
        exactTimestampToleranceSeconds: Int,
        endTimestampToleranceSeconds: Int
    ) async -> Int {
        await loadIfNeeded()
        let playedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        let exactTol = max(0, exactTimestampToleranceSeconds)
        let endTol = max(0, endTimestampToleranceSeconds)

        return items.filter { item in
            matchesPlaybackHistoryImport(
                item: item,
                track: track,
                startTimestamp: startTimestamp,
                playedAtTimestamp: playedAtTimestamp,
                exactTimestampToleranceSeconds: exactTol,
                endTimestampToleranceSeconds: endTol
            )
        }.count
    }

    @discardableResult
    func removeAll(origin targetOrigin: Origin) async -> Int {
        await loadIfNeeded()

        let originalCount = items.count
        items.removeAll { $0.origin == targetOrigin }
        let removedCount = originalCount - items.count

        if removedCount > 0 {
            await save()
        }

        return removedCount
    }

    func flush(sessionKey: String, maxItems: Int = 25) async -> FlushResult {
        await flush(sessionKey: sessionKey, listenBrainzToken: nil, maxItems: maxItems, ignoreBackoff: false)
    }

    func flush(sessionKey: String, maxItems: Int = 25, ignoreBackoff: Bool) async -> FlushResult {
        await flush(sessionKey: sessionKey, listenBrainzToken: nil, maxItems: maxItems, ignoreBackoff: ignoreBackoff)
    }

    func flush(
        sessionKey: String? = nil,
        listenBrainzToken: String? = nil,
        maxItems: Int = 25,
        ignoreBackoff: Bool = false
    ) async -> FlushResult {
        await loadIfNeeded()
        guard !isFlushing else {
            logger.debug("flush skipped (already in progress)")
            return FlushResult(sentCount: 0, skippedCount: 0, remainingCount: items.count, sentItems: [])
        }
        guard !items.isEmpty else {
            return FlushResult(sentCount: 0, skippedCount: 0, remainingCount: 0, sentItems: [])
        }

        isFlushing = true
        defer { isFlushing = false }

        let loveOnFavoriteEnabled = ProSettings.loveOnFavoriteEnabled()
        let now = Date()
        var sentCount = 0
        var skippedCount = 0
        var sentItems: [FlushResult.SentItem] = []

        let lastFMClient = try? LastFMClient()
        let listenBrainzClient = ListenBrainzClient()

        items.sort(by: { $0.startTimestamp < $1.startTimestamp })

        var batchScrobbledItemIDs: Set<UUID> = []

        // Batch Last.fm scrobbles if sessionKey is present
        if let sessionKey, !sessionKey.isEmpty, let lastFMClient {
            var eligibleIndices: [Int] = []
            var lastFMItemsToBatch: [(track: Track, startTimestamp: Int)] = []

            for (idx, item) in items.enumerated() {
                if lastFMItemsToBatch.count >= maxItems { break }
                guard item.startTimestamp > 0, item.attemptCount < 10 else { continue }
                var pending = item.pendingServices
                if listenBrainzToken?.isEmpty ?? true { pending.remove(.listenbrainz) }
                guard pending.contains(.lastfm) else { continue }

                if !ignoreBackoff, let last = item.lastAttemptAt {
                    let baseDelay = min(TimeInterval(60 * (1 << min(item.attemptCount - 1, 6))), 60 * 60)
                    let jitter = TimeInterval(Int.random(in: -30...30))
                    if now.timeIntervalSince(last) < baseDelay + jitter {
                        continue
                    }
                }

                eligibleIndices.append(idx)
                lastFMItemsToBatch.append((track: item.track, startTimestamp: item.startTimestamp))
            }

            if !lastFMItemsToBatch.isEmpty {
                do {
                    try await lastFMClient.scrobbleBatch(items: lastFMItemsToBatch, sessionKey: sessionKey)
                    for idx in eligibleIndices {
                        items[idx].pendingServices.remove(.lastfm)
                        batchScrobbledItemIDs.insert(items[idx].id)
                    }
                } catch {
                    let shouldRetry = (error as? LastFMClient.ClientError)?.shouldRetryScrobble ?? true
                    for idx in eligibleIndices {
                        if !shouldRetry {
                            items[idx].pendingServices.remove(.lastfm)
                        } else {
                            items[idx].attemptCount += 1
                            items[idx].lastAttemptAt = now
                        }
                    }
                }
            }
        }

        // Batch ListenBrainz scrobbles if token is present
        if let listenBrainzToken, !listenBrainzToken.isEmpty {
            var eligibleIndices: [Int] = []
            var listensToBatch: [(track: Track, timestamp: Date)] = []

            for (idx, item) in items.enumerated() {
                if listensToBatch.count >= maxItems { break }
                guard item.startTimestamp > 0, item.attemptCount < 10 else { continue }
                var pending = item.pendingServices
                if sessionKey?.isEmpty ?? true { pending.remove(.lastfm) }
                guard pending.contains(.listenbrainz) else { continue }

                if !ignoreBackoff, let last = item.lastAttemptAt {
                    let baseDelay = min(TimeInterval(60 * (1 << min(item.attemptCount - 1, 6))), 60 * 60)
                    let jitter = TimeInterval(Int.random(in: -30...30))
                    if now.timeIntervalSince(last) < baseDelay + jitter {
                        continue
                    }
                }

                eligibleIndices.append(idx)
                listensToBatch.append((track: item.track, timestamp: Date(timeIntervalSince1970: TimeInterval(item.startTimestamp))))
            }

            if !listensToBatch.isEmpty {
                do {
                    try await listenBrainzClient.submitBatch(listens: listensToBatch, userToken: listenBrainzToken)
                    for idx in eligibleIndices {
                        items[idx].pendingServices.remove(.listenbrainz)
                        batchScrobbledItemIDs.insert(items[idx].id)
                    }
                } catch {
                    let shouldRetry = (error as? ListenBrainzClient.ClientError)?.shouldRetryScrobble ?? true
                    for idx in eligibleIndices {
                        if !shouldRetry {
                            items[idx].pendingServices.remove(.listenbrainz)
                        } else {
                            items[idx].attemptCount += 1
                            items[idx].lastAttemptAt = now
                        }
                    }
                }
            }
        }

        var idx = 0
        while idx < items.count, sentCount < maxItems {
            var item = items[idx]
            var scrobbledInThisFlush = batchScrobbledItemIDs.contains(item.id)

            if item.startTimestamp <= 0 || item.attemptCount >= 10 || (item.pendingServices.isEmpty && !scrobbledInThisFlush) {
                logger.warning("discarding backlog item after \(item.attemptCount, privacy: .public) attempts: \(item.track.artist, privacy: .public) – \(item.track.title, privacy: .public)")
                items.remove(at: idx)
                continue
            }

            if !ignoreBackoff, let last = item.lastAttemptAt {
                let baseDelay = min(TimeInterval(60 * (1 << min(item.attemptCount - 1, 6))), 60 * 60)
                let jitter = TimeInterval(Int.random(in: -30...30))
                if now.timeIntervalSince(last) < baseDelay + jitter {
                    skippedCount += 1
                    idx += 1
                    continue
                }
            }

            var itemFailed = false
            var lovedOnLastFM = false

            let hasLastFM = sessionKey?.isEmpty == false
            let hasListenBrainz = listenBrainzToken?.isEmpty == false

            if !hasLastFM {
                item.pendingServices.remove(.lastfm)
            }
            if !hasListenBrainz {
                item.pendingServices.remove(.listenbrainz)
            }

            // 1. Process Last.fm if pending
            if item.pendingServices.contains(.lastfm) {
                if let sessionKey, let lastFMClient {
                    do {
                        try await lastFMClient.scrobble(track: item.track, sessionKey: sessionKey, startTimestamp: item.startTimestamp)
                        item.pendingServices.remove(.lastfm)
                        scrobbledInThisFlush = true
                        if item.wasAppleMusicFavorite == true, loveOnFavoriteEnabled {
                            do {
                                try await lastFMClient.love(track: item.track, sessionKey: sessionKey)
                                lovedOnLastFM = true
                            } catch {
                                // Keep silent
                            }
                        }
                    } catch {
                        if let clientError = error as? LastFMClient.ClientError, !clientError.shouldRetryScrobble {
                            item.pendingServices.remove(.lastfm)
                        } else {
                            itemFailed = true
                        }
                    }
                }
            }

            // 2. Process ListenBrainz if pending
            if item.pendingServices.contains(.listenbrainz) {
                if let listenBrainzToken, !listenBrainzToken.isEmpty {
                    do {
                        try await listenBrainzClient.submitScrobble(
                            track: item.track,
                            timestamp: Date(timeIntervalSince1970: TimeInterval(item.startTimestamp)),
                            userToken: listenBrainzToken
                        )
                        item.pendingServices.remove(.listenbrainz)
                        scrobbledInThisFlush = true
                    } catch {
                        if let clientError = error as? ListenBrainzClient.ClientError,
                           !clientError.shouldRetryScrobble {
                            item.pendingServices.remove(.listenbrainz)
                        } else {
                            itemFailed = true
                        }
                    }
                }
            }

            if item.pendingServices.isEmpty {
                if scrobbledInThisFlush {
                    sentItems.append(
                        FlushResult.SentItem(
                            track: item.track,
                            startTimestamp: item.startTimestamp,
                            scrobbledAt: now,
                            origin: item.origin,
                            lovedOnLastFM: lovedOnLastFM
                        )
                    )
                    sentCount += 1
                }
                if idx < items.count, items[idx].id == item.id {
                    items.remove(at: idx)
                } else if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
                    items.remove(at: currentIndex)
                }
            } else {
                if itemFailed {
                    item.attemptCount += 1
                    item.lastAttemptAt = now
                }
                if idx < items.count, items[idx].id == item.id {
                    items[idx] = item
                } else if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
                    items[currentIndex] = item
                }
                idx += 1
            }
        }

        await save()
        return FlushResult(sentCount: sentCount, skippedCount: skippedCount, remainingCount: items.count, sentItems: sentItems)
    }

    func replaceItemsForSync(_ syncedItems: [Item]) async {
        await loadIfNeeded()
        items = Self.mergedSyncedItems(local: [], remote: syncedItems)
        await save()
    }

    static func mergedSyncedItems(local: [Item], remote: [Item]) -> [Item] {
        var mergedByID: [UUID: Item] = [:]

        func mutationDate(for item: Item) -> Date {
            item.lastAttemptAt ?? item.queuedAt
        }

        func shouldReplace(existing: Item, with candidate: Item) -> Bool {
            let existingDate = mutationDate(for: existing)
            let candidateDate = mutationDate(for: candidate)
            if candidateDate != existingDate {
                return candidateDate > existingDate
            }
            if candidate.queuedAt != existing.queuedAt {
                return candidate.queuedAt > existing.queuedAt
            }
            return candidate.startTimestamp > existing.startTimestamp
        }

        for item in local + remote {
            if let existing = mergedByID[item.id] {
                if shouldReplace(existing: existing, with: item) {
                    mergedByID[item.id] = item
                }
            } else {
                mergedByID[item.id] = item
            }
        }

        return mergedByID.values.sorted {
            if $0.startTimestamp == $1.startTimestamp {
                return $0.queuedAt > $1.queuedAt
            }
            return $0.startTimestamp > $1.startTimestamp
        }
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true

        if let sharedURL = sharedFileURL() {
            let fm = FileManager.default
            if !fm.fileExists(atPath: sharedURL.path) {
                let legacyURL = legacyFileURL()
                if fm.fileExists(atPath: legacyURL.path) {
                    do {
                        try fm.createDirectory(at: sharedURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                        try fm.moveItem(at: legacyURL, to: sharedURL)
                    } catch {
                        logger.warning("failed to migrate backlog to app group: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        let url = fileURL()
        do {
            let data = try Data(contentsOf: url)
            items = try decodeItems(from: data)
        } catch {
            items = []
        }

        let result = pruneItems(now: Date())
        if result.removedCount > 0 {
            logCleanup(result)
            await save(pruneBeforeWrite: false)
        }
    }

    private func save(pruneBeforeWrite: Bool = true) async {
        let url = fileURL()
        do {
            if pruneBeforeWrite {
                let result = pruneItems(now: Date())
                if result.removedCount > 0 {
                    logCleanup(result)
                }
            }
            let data = try JSONEncoder().encode(items.map(PersistedItem.init))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: [.atomic])
            deleteLegacyFileIfRedundant()
            ICloudSyncLocalChangeNotifier.post(.backlog)
        } catch {
            logger.warning("failed to persist backlog: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneItems(now: Date) -> CleanupResult {
        let originalCount = items.count
        let cutoffTimestamp = Int(now.addingTimeInterval(-CleanupLimits.maxItemAge).timeIntervalSince1970.rounded(.down))

        items.removeAll { item in
            item.attemptCount >= CleanupLimits.maxAttemptCount
        }
        let removedTooManyFailedAttemptsCount = originalCount - items.count

        let countAfterFailedAttemptPrune = items.count
        items.removeAll { item in
            item.startTimestamp > 0 && item.startTimestamp < cutoffTimestamp
        }
        let removedTooOldCount = countAfterFailedAttemptPrune - items.count

        var removedTooManyItemsCount = 0
        if items.count > CleanupLimits.maxPendingItems {
            items.sort {
                if $0.startTimestamp == $1.startTimestamp {
                    return $0.queuedAt > $1.queuedAt
                }
                return $0.startTimestamp > $1.startTimestamp
            }
            removedTooManyItemsCount = items.count - CleanupLimits.maxPendingItems
            items.removeLast(removedTooManyItemsCount)
        }

        return CleanupResult(
            removedTooOldCount: removedTooOldCount,
            removedTooManyFailedAttemptsCount: removedTooManyFailedAttemptsCount,
            removedTooManyItemsCount: removedTooManyItemsCount,
            remainingCount: items.count
        )
    }

    private func logCleanup(_ result: CleanupResult) {
        logger.info(
            """
            cleaned scrobble backlog: old=\(result.removedTooOldCount, privacy: .public), \
            failed=\(result.removedTooManyFailedAttemptsCount, privacy: .public), \
            excess=\(result.removedTooManyItemsCount, privacy: .public), \
            remaining=\(result.remainingCount, privacy: .public)
            """
        )
    }

    private func playbackDurationSeconds(for storedTrack: Track, fallbackTrack: Track) -> Int? {
        RecoveryDuplicateMatcher.playbackDurationSeconds(for: storedTrack, fallbackTrack: fallbackTrack)
    }

    private func fileURL() -> URL {
        sharedFileURL() ?? legacyFileURL()
    }

    private func matchesPlaybackHistoryImport(
        item: Item,
        track: Track,
        startTimestamp: Int,
        playedAtTimestamp: Int,
        exactTimestampToleranceSeconds: Int,
        endTimestampToleranceSeconds: Int
    ) -> Bool {
        let evaluation = RecoveryDuplicateMatcher.evaluate(
            storedTrack: item.track,
            storedStartTimestamp: item.startTimestamp,
            storedSource: recoveryDuplicateStoredSource(for: item.origin),
            candidateTrack: track,
            candidateStartTimestamp: startTimestamp,
            candidatePlayedAtTimestamp: playedAtTimestamp,
            exactStartToleranceSeconds: exactTimestampToleranceSeconds,
            playedAtToleranceSeconds: endTimestampToleranceSeconds,
            weakStartToleranceSeconds: 0
        )
        return evaluation.level == .strongDuplicate
    }

    private func recoveryDuplicateStoredSource(for origin: Origin?) -> RecoveryDuplicateStoredSource {
        switch origin {
        case .live:
            return .live
        case .playbackHistory:
            return .playbackHistory
        case .recentlyPlayed:
            return .recentlyPlayed
        case .manual:
            return .manual
        case .none:
            return .backlog
        }
    }

    private func sharedFileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.kevin.FastScrobbler")?
            .appendingPathComponent("FastScrobblerShared", isDirectory: true)
            .appendingPathComponent("scrobble_backlog.json")
    }

    private func legacyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? {
            logger.warning("applicationSupportDirectory unavailable; falling back to temporaryDirectory")
            return FileManager.default.temporaryDirectory
        }()
        let bundleID = Bundle.main.bundleIdentifier ?? "FastScrobbler"
        return base.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("scrobble_backlog.json")
    }

    private func decodeItems(from data: Data) throws -> [Item] {
        if let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) {
            return persisted.map(\.item)
        }
        return try JSONDecoder().decode([Item].self, from: data)
    }

    private func deleteLegacyFileIfRedundant() {
        guard let sharedURL = sharedFileURL() else { return }
        let legacyURL = legacyFileURL()
        guard sharedURL.path != legacyURL.path else { return }
        guard FileManager.default.fileExists(atPath: sharedURL.path) else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
