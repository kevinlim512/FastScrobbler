import Foundation
import OSLog

@MainActor
final class ScrobbleLogStore: ObservableObject {
    enum Source: String, Codable, Sendable {
        case live
        case backlog
        case playbackHistory
        case recentlyPlayed
    }

    struct Entry: Identifiable, Codable, Hashable, Sendable {
        var id: UUID
        var track: Track
        var startTimestamp: Int
        var scrobbledAt: Date
        var source: Source
        var lovedOnLastFM: Bool?
    }

    static let shared = ScrobbleLogStore()

    @Published private(set) var entries: [Entry] = []

    private let logger = Logger(subsystem: "FastScrobbler", category: "ScrobbleLogStore")
    private let maxEntries = 50

    private init() {
        load()
    }

    func record(
        track: Track,
        startTimestamp: Int,
        scrobbledAt: Date = Date(),
        source: Source,
        lovedOnLastFM: Bool = false
    ) {
        let entry = Entry(
            id: UUID(),
            track: track,
            startTimestamp: startTimestamp,
            scrobbledAt: scrobbledAt,
            source: source,
            lovedOnLastFM: lovedOnLastFM
        )

        if entries.contains(where: { $0.startTimestamp == startTimestamp && $0.track.dedupeKey == track.dedupeKey }) {
            return
        }

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func containsSimilar(track: Track, around startTimestamp: Int, toleranceSeconds: Int) -> Bool {
        let tol = max(0, toleranceSeconds)
        return entries.contains(where: {
            $0.track.dedupeKey == track.dedupeKey && abs($0.startTimestamp - startTimestamp) <= tol
        })
    }

    private func load() {
        let fm = FileManager.default
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

            var map: [String: Entry] = [:]
            for e in sharedEntries {
                map["\(e.startTimestamp)|\(e.track.dedupeKey)"] = e
            }
            for e in legacyEntries {
                let key = "\(e.startTimestamp)|\(e.track.dedupeKey)"
                if let existing = map[key] {
                    if e.scrobbledAt > existing.scrobbledAt {
                        map[key] = e
                    }
                } else {
                    map[key] = e
                }
            }

            var merged = Array(map.values)
            merged.sort(by: { $0.scrobbledAt > $1.scrobbledAt })
            if merged.count > maxEntries {
                merged.removeLast(merged.count - maxEntries)
            }
            entries = merged

            // Persist into the shared container so app + extensions share the same dedupe history.
            do {
                let data = try JSONEncoder().encode(merged)
                try fm.createDirectory(at: sharedURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try data.write(to: sharedURL, options: [.atomic])
            } catch {
                logger.warning("failed to persist merged scrobble log: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            entries = readEntries(from: legacyURL)
        }
    }

    private func save() {
        let url = fileURL()
        do {
            let data = try JSONEncoder().encode(entries)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.warning("failed to persist scrobble log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL() -> URL {
        sharedFileURL() ?? legacyFileURL()
    }

    private func sharedFileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("FastScrobblerShared", isDirectory: true)
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
}
