import Foundation
import OSLog

actor ScrobbleBacklog {
    enum Origin: String, Codable, Sendable {
        case live
        case playbackHistory
        case recentlyPlayed
    }

    struct Item: Codable, Hashable {
        var id: UUID
        var track: Track
        var startTimestamp: Int
        var origin: Origin?
        var wasAppleMusicFavorite: Bool?
        var queuedAt: Date
        var attemptCount: Int
        var lastAttemptAt: Date?
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

    static let shared = ScrobbleBacklog()

    private let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleBacklog")
    private var isLoaded = false
    private var isFlushing = false
    private var items: [Item] = []

    private init() {}

    func pendingCount() async -> Int {
        await loadIfNeeded()
        return items.count
    }

    func enqueue(track: Track, startTimestamp: Int) async {
        await enqueue(track: track, startTimestamp: startTimestamp, origin: nil)
    }

    func enqueue(track: Track, startTimestamp: Int, origin: Origin?) async {
        await enqueue(track: track, startTimestamp: startTimestamp, origin: origin, wasAppleMusicFavorite: nil)
    }

    func enqueue(track: Track, startTimestamp: Int, origin: Origin?, wasAppleMusicFavorite: Bool?) async {
        await enqueue(
            track: track,
            startTimestamp: startTimestamp,
            origin: origin,
            wasAppleMusicFavorite: wasAppleMusicFavorite,
            allowExactDuplicates: false
        )
    }

    func enqueue(
        track: Track,
        startTimestamp: Int,
        origin: Origin?,
        wasAppleMusicFavorite: Bool?,
        allowExactDuplicates: Bool
    ) async {
        await loadIfNeeded()

        if !allowExactDuplicates,
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
                lastAttemptAt: nil
            )
        )
        await save()
    }

    func containsSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) async -> Bool {
        await loadIfNeeded()
        let tol = max(0, toleranceSeconds)
        return items.contains(where: {
            $0.track.dedupeKey == track.dedupeKey && abs($0.startTimestamp - startTimestamp) <= tol
        })
    }

    func flush(sessionKey: String, maxItems: Int = 25) async -> FlushResult {
        await flush(sessionKey: sessionKey, maxItems: maxItems, ignoreBackoff: false)
    }

    func flush(sessionKey: String, maxItems: Int = 25, ignoreBackoff: Bool) async -> FlushResult {
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

        do {
            let client = try LastFMClient()

            items.sort(by: { $0.startTimestamp < $1.startTimestamp })
            var idx = 0
            while idx < items.count, sentCount < maxItems {
                var item = items[idx]

                if item.startTimestamp <= 0 || item.attemptCount >= 10 {
                    items.remove(at: idx)
                    continue
                }

                if !ignoreBackoff, let last = item.lastAttemptAt, now.timeIntervalSince(last) < 10 * 60 {
                    skippedCount += 1
                    idx += 1
                    continue
                }

                do {
                    try await client.scrobble(track: item.track, sessionKey: sessionKey, startTimestamp: item.startTimestamp)
                    var lovedOnLastFM = false
                    if item.wasAppleMusicFavorite == true, loveOnFavoriteEnabled {
                        do {
                            try await client.love(track: item.track, sessionKey: sessionKey)
                            lovedOnLastFM = true
                        } catch {
                            // Keep silent; scrobble succeeded even if loving fails.
                        }
                    }
                    sentItems.append(
                        FlushResult.SentItem(
                            track: item.track,
                            startTimestamp: item.startTimestamp,
                            scrobbledAt: now,
                            origin: item.origin,
                            lovedOnLastFM: lovedOnLastFM
                        )
                    )
                    if idx < items.count, items[idx].id == item.id {
                        items.remove(at: idx)
                    } else if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: currentIndex)
                    } else {
                        // Item was already removed (or the backlog was mutated unexpectedly while awaiting).
                    }
                    sentCount += 1
                } catch {
                    item.attemptCount += 1
                    item.lastAttemptAt = now
                    if idx < items.count, items[idx].id == item.id {
                        items[idx] = item
                    } else if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
                        items[currentIndex] = item
                    } else {
                        // Item was already removed (or the backlog was mutated unexpectedly while awaiting).
                    }
                    logger.warning("backlog scrobble failed: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }
        } catch {
            logger.warning("failed to init LastFMClient for backlog flush: \(error.localizedDescription, privacy: .public)")
        }

        await save()
        return FlushResult(sentCount: sentCount, skippedCount: skippedCount, remainingCount: items.count, sentItems: sentItems)
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
            items = try JSONDecoder().decode([Item].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() async {
        let url = fileURL()
        do {
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.warning("failed to persist backlog: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL() -> URL {
        sharedFileURL() ?? legacyFileURL()
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
}
