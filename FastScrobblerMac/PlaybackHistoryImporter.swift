import Foundation

// Listening History import is not implemented for the macOS target.
@MainActor
final class PlaybackHistoryImporter {
    struct SyncState: Codable, Equatable {
        var lastImportAt: Date?
        var playCountByTrackID: [String: Int] = [:]
        var lastSeenPlayedAtByTrackID: [String: Date] = [:]
    }

    static let shared = PlaybackHistoryImporter()

    private init() {}

    func exportSyncState() -> SyncState {
        SyncState()
    }

    func mergeSyncState(_ incoming: SyncState) {}
}
