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
        let url = fileURL()
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            entries = []
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
