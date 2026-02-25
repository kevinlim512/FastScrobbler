import Foundation

@MainActor
final class PlaybackHistoryImporter {
    enum ImportKeys {
        static let lastImportAt = "FastScrobbler.PlaybackHistoryImporter.lastImportAt"
    }

    static let shared = PlaybackHistoryImporter()

    private init() {}

    func importIntoBacklog(backlog: ScrobbleBacklog, scrobbleLog: ScrobbleLogStore? = nil, maxItems: Int = 50) async -> Int {
        // Not currently implemented on macOS.
        return 0
    }
}
