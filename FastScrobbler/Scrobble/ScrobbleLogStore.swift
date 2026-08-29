import Foundation
import OSLog

enum RecoveryDuplicateMatchLevel: Int, Comparable, Sendable {
    case none = 0
    case weakDuplicate = 1
    case strongDuplicate = 2

    static func < (lhs: RecoveryDuplicateMatchLevel, rhs: RecoveryDuplicateMatchLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
final class ListeningHistoryReviewStore: ObservableObject {
    struct Entry: Identifiable, Codable, Hashable, Sendable {
        var id: UUID
        var track: Track
        var startTimestamp: Int
        var playedAt: Date
        var origin: ScrobbleBacklog.Origin
        var wasAppleMusicFavorite: Bool?
        var queuedAt: Date
    }

    static let shared = ListeningHistoryReviewStore()

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "FastScrobbler", category: "ListeningHistoryReviewStore")

    private init() {
        load()
    }

    func pendingEntries() -> [Entry] {
        entries
    }

    func pendingCount() -> Int {
        entries.count
    }

    @discardableResult
    func upsert(_ incomingEntries: [Entry]) -> Int {
        guard !incomingEntries.isEmpty else { return 0 }

        var entriesByIdentity = Dictionary(uniqueKeysWithValues: entries.map { (mergeIdentity(for: $0), $0) })
        var insertedCount = 0

        for entry in incomingEntries {
            let identity = mergeIdentity(for: entry)
            if let existing = entriesByIdentity[identity] {
                var updated = existing
                updated.track = entry.track
                updated.wasAppleMusicFavorite = entry.wasAppleMusicFavorite
                updated.queuedAt = max(existing.queuedAt, entry.queuedAt)
                entriesByIdentity[identity] = updated
            } else {
                entriesByIdentity[identity] = entry
                insertedCount += 1
            }
        }

        entries = normalizedEntries(Array(entriesByIdentity.values))
        save()
        return insertedCount
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let originalCount = entries.count
        entries.removeAll { ids.contains($0.id) }
        guard entries.count != originalCount else { return }
        save()
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        save()
    }

    func dequeueAllForSubmission() -> [Entry] {
        let snapshot = submissionOrder(entries)
        entries = []
        save()
        return snapshot
    }

    func dequeueForSubmission(ids: Set<UUID>) -> [Entry] {
        guard !ids.isEmpty else { return [] }

        let selectedEntries = entries.filter { ids.contains($0.id) }
        guard !selectedEntries.isEmpty else { return [] }

        entries.removeAll { ids.contains($0.id) }
        save()
        return submissionOrder(selectedEntries)
    }

    func reload() {
        load()
    }

    private func normalizedEntries(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            if $0.startTimestamp == $1.startTimestamp {
                if $0.queuedAt == $1.queuedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.queuedAt > $1.queuedAt
            }
            return $0.startTimestamp > $1.startTimestamp
        }
    }

    private func submissionOrder(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            if $0.startTimestamp == $1.startTimestamp {
                return $0.queuedAt < $1.queuedAt
            }
            return $0.startTimestamp < $1.startTimestamp
        }
    }

    private func mergeIdentity(for entry: Entry) -> String {
        "\(entry.origin.rawValue)|\(entry.track.dedupeKey)|\(entry.startTimestamp)"
    }

    private func load() {
        let legacyURL = legacyFileURL()
        let sharedURL = sharedFileURL()

        func readEntries(from url: URL) -> [Entry] {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([Entry].self, from: data)
            } catch {
                return []
            }
        }

        if let sharedURL {
            let sharedEntries = readEntries(from: sharedURL)
            let legacyEntries = readEntries(from: legacyURL)
            var map = Dictionary(uniqueKeysWithValues: sharedEntries.map { (mergeIdentity(for: $0), $0) })

            for entry in legacyEntries {
                let identity = mergeIdentity(for: entry)
                if let existing = map[identity] {
                    if entry.queuedAt > existing.queuedAt {
                        map[identity] = entry
                    }
                } else {
                    map[identity] = entry
                }
            }

            entries = normalizedEntries(Array(map.values))

            do {
                try persist(entries, preferredURL: sharedURL, fallbackURL: legacyURL)
            } catch {
                logger.warning("failed to persist merged review queue: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            entries = normalizedEntries(readEntries(from: legacyURL))
        }
    }

    private func save() {
        entries = normalizedEntries(entries)
        do {
            try persist(entries, preferredURL: sharedFileURL(), fallbackURL: legacyFileURL())
        } catch {
            logger.warning("failed to persist review queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL() -> URL {
        sharedFileURL() ?? legacyFileURL()
    }

    private func sharedFileURL() -> URL? {
        AppGroup.sharedDataDirectoryURL()?
            .appendingPathComponent("listening_history_review_queue.json")
    }

    private func legacyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? {
            logger.warning("applicationSupportDirectory unavailable; falling back to temporaryDirectory")
            return FileManager.default.temporaryDirectory
        }()
        let bundleID = Bundle.main.bundleIdentifier ?? "FastScrobbler"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("listening_history_review_queue.json")
    }

    private func persist(_ entries: [Entry], preferredURL: URL?, fallbackURL: URL) throws {
        let data = try JSONEncoder().encode(entries)

        if let preferredURL {
            do {
                try write(data, to: preferredURL)
                deleteLegacyFileIfRedundant(sharedURL: preferredURL, legacyURL: fallbackURL)
                return
            } catch {
                logger.warning("shared review queue write failed; falling back to Application Support: \(error.localizedDescription, privacy: .public)")
            }
        }

        try write(data, to: fallbackURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: [.atomic])
    }

    private func deleteLegacyFileIfRedundant(sharedURL: URL, legacyURL: URL) {
        guard sharedURL.path != legacyURL.path else { return }
        guard FileManager.default.fileExists(atPath: sharedURL.path) else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }
}

struct RecoveryDuplicateMatch<Matched: Sendable>: Sendable {
    let level: RecoveryDuplicateMatchLevel
    let matched: Matched
}

enum RecoveryDuplicateStoredSource: Sendable {
    case live
    case backlog
    case playbackHistory
    case recentlyPlayed
    case manual
}

enum RecoveryDuplicateMatcher {
    static let balancedExactStartToleranceSeconds = 10
    static let balancedPlayedAtToleranceSeconds = 90

    struct Evaluation: Sendable {
        let level: RecoveryDuplicateMatchLevel
        let startDistance: Int
        let playedAtDistance: Int?
    }

    static func playbackDurationSeconds(for storedTrack: Track, fallbackTrack: Track) -> Int? {
        let candidates = [storedTrack.durationSeconds, fallbackTrack.durationSeconds]
        for candidate in candidates {
            guard let candidate, candidate > 0 else { continue }
            return Int(candidate.rounded(.down))
        }
        return nil
    }

    static func playedAtTimestamp(
        for source: RecoveryDuplicateStoredSource,
        startTimestamp: Int,
        storedTrack: Track,
        fallbackTrack: Track
    ) -> Int {
        switch source {
        case .manual:
            return startTimestamp
        case .playbackHistory:
            return startTimestamp
        case .live, .backlog, .recentlyPlayed:
            guard let durationSeconds = playbackDurationSeconds(for: storedTrack, fallbackTrack: fallbackTrack) else {
                return startTimestamp
            }
            return startTimestamp + durationSeconds
        }
    }

    static func evaluate(
        storedTrack: Track,
        storedStartTimestamp: Int,
        storedSource: RecoveryDuplicateStoredSource,
        candidateTrack: Track,
        candidateStartTimestamp: Int,
        candidatePlayedAtTimestamp: Int,
        exactStartToleranceSeconds: Int = balancedExactStartToleranceSeconds,
        playedAtToleranceSeconds: Int = balancedPlayedAtToleranceSeconds,
        weakStartToleranceSeconds: Int
    ) -> Evaluation {
        guard storedTrack.dedupeKey == candidateTrack.dedupeKey else {
            return Evaluation(level: .none, startDistance: .max, playedAtDistance: nil)
        }

        let weakTol = max(0, weakStartToleranceSeconds)
        let exactTol = max(0, exactStartToleranceSeconds)
        let playedTol = max(0, playedAtToleranceSeconds)
        let startDistance = abs(storedStartTimestamp - candidateStartTimestamp)

        if startDistance <= exactTol {
            return Evaluation(level: .strongDuplicate, startDistance: startDistance, playedAtDistance: nil)
        }

        let storedPlayedAtTimestamp = playedAtTimestamp(
            for: storedSource,
            startTimestamp: storedStartTimestamp,
            storedTrack: storedTrack,
            fallbackTrack: candidateTrack
        )
        let playedAtDistance = abs(storedPlayedAtTimestamp - candidatePlayedAtTimestamp)

        if playedAtDistance <= playedTol {
            return Evaluation(level: .strongDuplicate, startDistance: startDistance, playedAtDistance: playedAtDistance)
        }

        if weakTol > 0, startDistance <= weakTol {
            return Evaluation(level: .weakDuplicate, startDistance: startDistance, playedAtDistance: nil)
        }

        return Evaluation(level: .none, startDistance: startDistance, playedAtDistance: playedAtDistance)
    }

    static func isPreferred(_ candidate: Evaluation, over current: Evaluation?) -> Bool {
        guard let current else { return true }
        guard candidate.level != current.level else {
            let candidateScore = candidate.playedAtDistance ?? candidate.startDistance
            let currentScore = current.playedAtDistance ?? current.startDistance
            if candidateScore != currentScore {
                return candidateScore < currentScore
            }
            return candidate.startDistance < current.startDistance
        }
        return candidate.level > current.level
    }
}

@MainActor
final class ScrobbleLogStore: ObservableObject {
    enum Limits {
        static let maxStoredEntries = 100
        static let defaultDisplayLimit = 50
        static let manualDisplayLimit = 30
        static let maxEntryAge: TimeInterval = 21 * 24 * 60 * 60
    }

    enum Source: String, Codable, Sendable {
        case live
        case backlog
        case playbackHistory
        case recentlyPlayed
        case manual
    }

    struct Entry: Identifiable, Codable, Hashable, Sendable {
        var id: UUID
        var track: Track
        var startTimestamp: Int
        var scrobbledAt: Date
        var source: Source
        var lovedOnLastFM: Bool?
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

    private struct PersistedEntry: Codable {
        var id: UUID
        var track: PersistedTrack
        var startTimestamp: Int
        var scrobbledAt: Date
        var source: Source
        var lovedOnLastFM: Bool?

        private enum CodingKeys: String, CodingKey {
            case id = "i"
            case track = "t"
            case startTimestamp = "s"
            case scrobbledAt = "c"
            case source = "o"
            case lovedOnLastFM = "l"
        }

        init(entry: Entry) {
            id = entry.id
            track = PersistedTrack(track: entry.track)
            startTimestamp = entry.startTimestamp
            scrobbledAt = entry.scrobbledAt
            source = entry.source
            lovedOnLastFM = entry.lovedOnLastFM
        }

        var entry: Entry {
            Entry(
                id: id,
                track: track.track,
                startTimestamp: startTimestamp,
                scrobbledAt: scrobbledAt,
                source: source,
                lovedOnLastFM: lovedOnLastFM
            )
        }
    }

    static let shared = ScrobbleLogStore()

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleLogStore")

    private init() {
        load()
    }

    func recentEntries(limit: Int = Limits.defaultDisplayLimit) -> [Entry] {
        Array(entries.prefix(max(0, limit)))
    }

    func syncedEntriesSnapshot() -> [Entry] {
        entries
    }

    func manualEntries(limit: Int = Limits.manualDisplayLimit) -> [Entry] {
        Array(entries.filter { $0.source == .manual }.prefix(max(0, limit)))
    }

    func record(
        track: Track,
        startTimestamp: Int,
        scrobbledAt: Date = Date(),
        source: Source,
        lovedOnLastFM: Bool = false,
        allowExactDuplicates: Bool = false
    ) {
        let entry = Entry(
            id: UUID(),
            track: track,
            startTimestamp: startTimestamp,
            scrobbledAt: scrobbledAt,
            source: source,
            lovedOnLastFM: lovedOnLastFM
        )

        if !allowExactDuplicates,
           entries.contains(where: { $0.startTimestamp == startTimestamp && $0.track.dedupeKey == track.dedupeKey })
        {
            return
        }

        entries.append(entry)
        normalizeEntries(now: Date())
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func cleanupNow() {
        normalizeEntries(now: Date())
        save()
    }

    func reload() {
        load()
    }

    func replaceEntriesForSync(_ syncedEntries: [Entry]) {
        entries = normalizedEntries(Self.mergedSyncedEntries(local: [], remote: syncedEntries), now: Date())
        save()
    }

    func storageSizeBytes() -> Int64 {
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

    func isMostRecentScrobble(dedupeKey: String) -> Bool {
        entries.max(by: { $0.startTimestamp < $1.startTimestamp })?.track.dedupeKey == dedupeKey
    }

    func containsSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) -> Bool {
        let tol = max(0, toleranceSeconds)
        return entries.contains(where: {
            $0.track.dedupeKey == track.dedupeKey && abs($0.startTimestamp - startTimestamp) <= tol
        })
    }

    func mostSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) -> Entry? {
        let tol = max(0, toleranceSeconds)
        return entries
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
    ) -> RecoveryDuplicateMatch<Entry>? {
        let candidatePlayedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        var bestEntry: Entry?
        var bestEvaluation: RecoveryDuplicateMatcher.Evaluation?

        for entry in entries {
            let evaluation = RecoveryDuplicateMatcher.evaluate(
                storedTrack: entry.track,
                storedStartTimestamp: entry.startTimestamp,
                storedSource: recoveryDuplicateStoredSource(for: entry.source),
                candidateTrack: track,
                candidateStartTimestamp: startTimestamp,
                candidatePlayedAtTimestamp: candidatePlayedAtTimestamp,
                exactStartToleranceSeconds: exactStartToleranceSeconds,
                playedAtToleranceSeconds: playedAtToleranceSeconds,
                weakStartToleranceSeconds: weakStartToleranceSeconds
            )
            guard evaluation.level != .none else { continue }
            if RecoveryDuplicateMatcher.isPreferred(evaluation, over: bestEvaluation) {
                bestEntry = entry
                bestEvaluation = evaluation
            }
        }

        guard let bestEntry, let bestEvaluation else { return nil }
        return RecoveryDuplicateMatch(level: bestEvaluation.level, matched: bestEntry)
    }

    func containsPlaybackHistoryMatch(track: Track, playedAt: Date, endTimestampToleranceSeconds: Int) -> Bool {
        let playedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        let tol = max(0, endTimestampToleranceSeconds)

        return entries.contains(where: { entry in
            let evaluation = RecoveryDuplicateMatcher.evaluate(
                storedTrack: entry.track,
                storedStartTimestamp: entry.startTimestamp,
                storedSource: recoveryDuplicateStoredSource(for: entry.source),
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
    ) -> Int {
        let playedAtTimestamp = Int(playedAt.timeIntervalSince1970.rounded(.down))
        let exactTol = max(0, exactTimestampToleranceSeconds)
        let endTol = max(0, endTimestampToleranceSeconds)

        return entries.filter { entry in
            matchesPlaybackHistoryImport(
                entry: entry,
                track: track,
                startTimestamp: startTimestamp,
                playedAtTimestamp: playedAtTimestamp,
                exactTimestampToleranceSeconds: exactTol,
                endTimestampToleranceSeconds: endTol
            )
        }.count
    }

    static func mergedSyncedEntries(local: [Entry], remote: [Entry]) -> [Entry] {
        var mergedByIdentity: [String: Entry] = [:]

        func identity(for entry: Entry) -> String {
            "\(entry.source.rawValue)|\(entry.track.dedupeKey)|\(entry.startTimestamp)"
        }

        for entry in local + remote {
            let key = identity(for: entry)
            if let existing = mergedByIdentity[key] {
                if entry.scrobbledAt > existing.scrobbledAt {
                    mergedByIdentity[key] = entry
                }
            } else {
                mergedByIdentity[key] = entry
            }
        }

        return Array(mergedByIdentity.values)
    }

    private func load() {
        let legacyURL = legacyFileURL()
        let sharedURL = sharedFileURL()

        func readEntries(from url: URL) -> [Entry] {
            do {
                let data = try Data(contentsOf: url)
                return try decodeEntries(from: data)
            } catch {
                return []
            }
        }

        if let sharedURL {
            let sharedEntries = readEntries(from: sharedURL)
            let legacyEntries = readEntries(from: legacyURL)

            var map: [String: Entry] = [:]
            for e in sharedEntries {
                map[mergeIdentity(for: e)] = e
            }
            for e in legacyEntries {
                let key = mergeIdentity(for: e)
                if let existing = map[key] {
                    if e.scrobbledAt > existing.scrobbledAt {
                        map[key] = e
                    }
                } else {
                    map[key] = e
                }
            }

            entries = normalizedEntries(Array(map.values), now: Date())

            // Persist into the shared container so app + extensions share the same dedupe history.
            do {
                try persist(entries, preferredURL: sharedURL, fallbackURL: legacyURL)
            } catch {
                logger.warning("failed to persist merged scrobble log: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            entries = normalizedEntries(readEntries(from: legacyURL), now: Date())
        }
    }

    private func save() {
        normalizeEntries(now: Date())
        do {
            try persist(entries, preferredURL: sharedFileURL(), fallbackURL: legacyFileURL())
            ICloudSyncLocalChangeNotifier.post(.scrobbleLog)
        } catch {
            logger.warning("failed to persist scrobble log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func playbackDurationSeconds(for storedTrack: Track, fallbackTrack: Track) -> Int? {
        RecoveryDuplicateMatcher.playbackDurationSeconds(for: storedTrack, fallbackTrack: fallbackTrack)
    }

    private func normalizeEntries(now: Date) {
        entries = normalizedEntries(entries, now: now)
    }

    private func normalizedEntries(_ entries: [Entry], now: Date) -> [Entry] {
        let cutoff = now.addingTimeInterval(-Limits.maxEntryAge)
        var normalized = entries.filter { $0.scrobbledAt >= cutoff }
        normalized.sort {
            if $0.scrobbledAt == $1.scrobbledAt {
                return $0.startTimestamp > $1.startTimestamp
            }
            return $0.scrobbledAt > $1.scrobbledAt
        }
        if normalized.count > Limits.maxStoredEntries {
            normalized.removeLast(normalized.count - Limits.maxStoredEntries)
        }
        return normalized
    }

    private func mergeIdentity(for entry: Entry) -> String {
        "\(entry.source.rawValue)|\(entry.track.dedupeKey)|\(entry.startTimestamp)"
    }

    private func matchesPlaybackHistoryImport(
        entry: Entry,
        track: Track,
        startTimestamp: Int,
        playedAtTimestamp: Int,
        exactTimestampToleranceSeconds: Int,
        endTimestampToleranceSeconds: Int
    ) -> Bool {
        let evaluation = RecoveryDuplicateMatcher.evaluate(
            storedTrack: entry.track,
            storedStartTimestamp: entry.startTimestamp,
            storedSource: recoveryDuplicateStoredSource(for: entry.source),
            candidateTrack: track,
            candidateStartTimestamp: startTimestamp,
            candidatePlayedAtTimestamp: playedAtTimestamp,
            exactStartToleranceSeconds: exactTimestampToleranceSeconds,
            playedAtToleranceSeconds: endTimestampToleranceSeconds,
            weakStartToleranceSeconds: 0
        )
        return evaluation.level == .strongDuplicate
    }

    private func recoveryDuplicateStoredSource(for source: Source) -> RecoveryDuplicateStoredSource {
        switch source {
        case .live:
            return .live
        case .backlog:
            return .backlog
        case .playbackHistory:
            return .playbackHistory
        case .recentlyPlayed:
            return .recentlyPlayed
        case .manual:
            return .manual
        }
    }

    private func fileURL() -> URL {
        sharedFileURL() ?? legacyFileURL()
    }

    private func sharedFileURL() -> URL? {
        AppGroup.sharedDataDirectoryURL()?
            .appendingPathComponent("scrobble_log.json")
    }

    private func legacyFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? {
            logger.warning("applicationSupportDirectory unavailable; falling back to temporaryDirectory")
            return FileManager.default.temporaryDirectory
        }()
        let bundleID = Bundle.main.bundleIdentifier ?? "FastScrobbler"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("scrobble_log.json")
    }

    private func persist(_ entries: [Entry], preferredURL: URL?, fallbackURL: URL) throws {
        let data = try JSONEncoder().encode(entries.map(PersistedEntry.init))

        if let preferredURL {
            do {
                try write(data, to: preferredURL)
                deleteLegacyFileIfRedundant(sharedURL: preferredURL, legacyURL: fallbackURL)
                return
            } catch {
                logger.warning("shared scrobble log write failed; falling back to Application Support: \(error.localizedDescription, privacy: .public)")
            }
        }

        try write(data, to: fallbackURL)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: [.atomic])
    }

    private func decodeEntries(from data: Data) throws -> [Entry] {
        if let persisted = try? JSONDecoder().decode([PersistedEntry].self, from: data) {
            return persisted.map(\.entry)
        }
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    private func deleteLegacyFileIfRedundant(sharedURL: URL, legacyURL: URL) {
        guard sharedURL.path != legacyURL.path else { return }
        guard FileManager.default.fileExists(atPath: sharedURL.path) else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
