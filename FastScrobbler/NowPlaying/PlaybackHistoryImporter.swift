import Foundation
import MediaPlayer
import OSLog

@MainActor
final class PlaybackHistoryImporter {
    enum ImportKeys {
        static let lastImportAt = "FastScrobbler.PlaybackHistoryImporter.lastImportAt"
        static let stateData = "FastScrobbler.PlaybackHistoryImporter.stateData"
    }

    private enum Constants {
        static let maxImportLookbackDays = 7
        static let exactDuplicateToleranceSeconds = 10
        static let playedAtMatchToleranceSeconds = 45
    }

    static let shared = PlaybackHistoryImporter()

    private let logger = Logger(subsystem: "FastScrobbler", category: "PlaybackHistoryImporter")

    private init() {}

    private struct ImportState: Codable {
        var lastImportAt: Date?
        var playCountByPersistentID: [UInt64: Int]
        var lastSeenPlayedAtByPersistentID: [UInt64: Date]

        init(lastImportAt: Date? = nil) {
            self.lastImportAt = lastImportAt
            playCountByPersistentID = [:]
            lastSeenPlayedAtByPersistentID = [:]
        }
    }

    func importIntoBacklog(backlog: ScrobbleBacklog, scrobbleLog: ScrobbleLogStore, maxItems: Int = 50) async -> Int {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return 0 }

        let favoritesIndex = AppleMusicFavorites.buildIndex()
        let preventDuplicates = ProSettings.preventDuplicateScrobblesEnabled()
        let allowAllDevicesListeningHistory = ProSettings.scrobbleListeningHistoryFromAllDevicesEnabled()
        let dedupeToleranceSeconds = preventDuplicates ? Constants.exactDuplicateToleranceSeconds : 0
        let playedAtMatchToleranceSeconds = preventDuplicates ? Constants.playedAtMatchToleranceSeconds : 0

        var state = loadState()
        if state.lastImportAt == nil {
            // Migrate from legacy key if present.
            state.lastImportAt = AppGroup.userDefaults.object(forKey: ImportKeys.lastImportAt) as? Date
        }

        let priorLastImportAt = state.lastImportAt
        let cutoff = state.lastImportAt ?? Date(timeIntervalSinceNow: -24 * 60 * 60)
        let fetchCutoff: Date = {
            // Keep listening-history scans bounded even if the import cursor is stale.
            // This avoids re-walking a large library just to re-check older plays that are
            // very likely already scrobbled.
            let lookback = Date(timeIntervalSinceNow: -Double(Constants.maxImportLookbackDays) * 24 * 60 * 60)
            return max(cutoff, lookback)
        }()

        let candidates = fetchCandidatesPlayed(after: fetchCutoff)
        guard !candidates.isEmpty else {
            // Persist migrated state even if nothing new was found.
            saveState(state)
            return 0
        }

        let sorted = candidates.sorted(by: { $0.playedAt < $1.playedAt })

        var importedCount = 0
        var newestPlayedAt: Date?

        for c in sorted {
            guard importedCount < maxItems else { break }
            let item = c.item
            let playedAt = c.playedAt
            let pid = item.persistentID
            let previousSeenPlayedAt = state.lastSeenPlayedAtByPersistentID[pid]
            let playCutoff: Date = {
                if allowAllDevicesListeningHistory {
                    return max(fetchCutoff, previousSeenPlayedAt ?? fetchCutoff)
                }
                return cutoff
            }()
            guard playedAt > playCutoff else { continue }

            let artist = item.artist ?? ""
            let title = item.title ?? ""
            guard !artist.isEmpty, !title.isEmpty else { continue }

            let duration = item.playbackDuration
            let track = Track(
                artist: artist,
                title: title,
                album: item.albumTitle,
                albumArtist: item.albumArtist,
                durationSeconds: duration > 0 ? duration : nil,
                persistentID: item.persistentID
            )
            let wasAppleMusicFavorite = AppleMusicFavorites.isFavorited(item, index: favoritesIndex)

            let playCount = item.playCount
            let previousPlayCount = state.playCountByPersistentID[pid]
            let delta: Int = {
                guard let previousPlayCount else { return 1 }
                let d = playCount - previousPlayCount
                if d > 0 { return d }
                // Sometimes `playCount` doesn't move in lock-step with `lastPlayedDate`. If the app sees a new play time,
                // treat it as a single play even if the count didn't increment (or reset).
                return 1
            }()

            let durationForStartTimestamp: TimeInterval? = {
                guard let d = track.durationSeconds, d > 0, d <= 60 * 60 else { return nil }
                return d
            }()

            let spacingForInference: TimeInterval? = {
                if let d = durationForStartTimestamp {
                    if preventDuplicates {
                        guard d >= 30 else { return nil }
                        return d
                    }
                    guard d >= 5 else { return nil }
                    return d
                }

                // When duplicate prevention is OFF, infer multiple consecutive plays even when duration metadata
                // isn't reliable/available by spacing them out within the observed time window.
                guard !preventDuplicates, delta > 1 else { return nil }
                let windowStart = max(previousSeenPlayedAt ?? playCutoff, playCutoff)
                let window = playedAt.timeIntervalSince(windowStart)
                if window <= 0 { return 5 }
                let candidate = window / Double(delta)
                return min(max(candidate, 5), 60)
            }()

            // Cap how many plays the app infers from the playCount delta to avoid spamming on library sync anomalies.
            let maxPlaysByTimeWindow: Int = {
                guard let spacing = spacingForInference else { return 1 }
                let window = playedAt.timeIntervalSince(playCutoff)
                if window <= 0 { return 1 }
                return max(1, Int((window / spacing).rounded(.down)) + 1)
            }()

            let playsToImport = min(max(delta, 1), min(maxPlaysByTimeWindow, 5))

            let scrobbleTrack = track.applyingProScrobblePreferences()

            for idx in stride(from: playsToImport - 1, through: 0, by: -1) {
                guard importedCount < maxItems else { break }

                let inferredPlayedAt: Date = {
                    guard let spacing = spacingForInference else { return playedAt }
                    return playedAt.addingTimeInterval(-spacing * Double(idx))
                }()
                guard inferredPlayedAt > playCutoff else { continue }

                let startTimestamp: Int = {
                    // The Music app writes listening history at (or after) track end.
                    // Use end time minus duration when available to approximate the start timestamp.
                    if let d = durationForStartTimestamp {
                        let startAt = inferredPlayedAt.addingTimeInterval(-d)
                        return Int(startAt.timeIntervalSince1970.rounded(.down))
                    }
                    return Int(inferredPlayedAt.timeIntervalSince1970.rounded(.down))
                }()

                let backlogHasExactDuplicate = await backlog.containsSimilar(
                    track: scrobbleTrack,
                    around: startTimestamp,
                    toleranceSeconds: dedupeToleranceSeconds
                )
                let backlogHasPlaybackHistoryMatch = await backlog.containsPlaybackHistoryMatch(
                    track: scrobbleTrack,
                    playedAt: inferredPlayedAt,
                    endTimestampToleranceSeconds: playedAtMatchToleranceSeconds
                )
                let logHasExactDuplicate = scrobbleLog.containsSimilar(
                    track: scrobbleTrack,
                    around: startTimestamp,
                    toleranceSeconds: dedupeToleranceSeconds
                )
                let logHasPlaybackHistoryMatch = scrobbleLog.containsPlaybackHistoryMatch(
                    track: scrobbleTrack,
                    playedAt: inferredPlayedAt,
                    endTimestampToleranceSeconds: playedAtMatchToleranceSeconds
                )

                let isDuplicate =
                    backlogHasExactDuplicate ||
                    backlogHasPlaybackHistoryMatch ||
                    logHasExactDuplicate ||
                    logHasPlaybackHistoryMatch

                if !isDuplicate {
                    await backlog.enqueue(
                        track: scrobbleTrack,
                        startTimestamp: startTimestamp,
                        origin: .playbackHistory,
                        wasAppleMusicFavorite: wasAppleMusicFavorite
                    )
                    importedCount += 1
                }
            }

            state.playCountByPersistentID[pid] = playCount
            state.lastSeenPlayedAtByPersistentID[pid] = playedAt

            newestPlayedAt = max(newestPlayedAt ?? playedAt, playedAt)
        }

        if let newestPlayedAt {
            if let priorLastImportAt {
                state.lastImportAt = max(priorLastImportAt, newestPlayedAt)
            } else {
                state.lastImportAt = newestPlayedAt
            }
            AppGroup.userDefaults.set(state.lastImportAt, forKey: ImportKeys.lastImportAt) // legacy / debugging
        }

        pruneState(&state)
        saveState(state)
        return importedCount
    }

    private struct Candidate {
        var item: MPMediaItem
        var playedAt: Date
    }

    private func fetchCandidatesPlayed(after cutoff: Date) -> [Candidate] {
        // Listening history import is based on each item's `lastPlayedDate`.
        let items = MPMediaQuery.songs().items ?? []

        guard !items.isEmpty else { return [] }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(64)

        for item in items {
            guard let playedAt = item.lastPlayedDate else { continue }
            guard playedAt > cutoff else { continue }
            candidates.append(Candidate(item: item, playedAt: playedAt))
        }

        if candidates.isEmpty { return [] }

        // Keep the working set bounded; the app only needs the most recent plays.
        let hardLimit = 500
        if candidates.count > hardLimit {
            candidates.sort(by: { $0.playedAt > $1.playedAt })
            candidates = Array(candidates.prefix(hardLimit))
        }

        return candidates
    }

    private func loadState() -> ImportState {
        guard let data = AppGroup.userDefaults.data(forKey: ImportKeys.stateData) else {
            return ImportState()
        }
        do {
            return try JSONDecoder().decode(ImportState.self, from: data)
        } catch {
            return ImportState()
        }
    }

    private func saveState(_ state: ImportState) {
        do {
            let data = try JSONEncoder().encode(state)
            AppGroup.userDefaults.set(data, forKey: ImportKeys.stateData)
        } catch {
            logger.warning("failed to persist import state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneState(_ state: inout ImportState) {
        // Keep state bounded to avoid unbounded growth in UserDefaults.
        let cutoff = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
        state.lastSeenPlayedAtByPersistentID = state.lastSeenPlayedAtByPersistentID.filter { _, lastSeen in
            lastSeen >= cutoff
        }
        let allowedIDs = Set(state.lastSeenPlayedAtByPersistentID.keys)
        state.playCountByPersistentID = state.playCountByPersistentID.filter { allowedIDs.contains($0.key) }

        let maxEntries = 3000
        if state.lastSeenPlayedAtByPersistentID.count > maxEntries {
            let newest = state.lastSeenPlayedAtByPersistentID
                .sorted(by: { $0.value > $1.value })
                .prefix(maxEntries)
            let keepIDs = Set(newest.map { $0.key })
            state.lastSeenPlayedAtByPersistentID = state.lastSeenPlayedAtByPersistentID.filter { keepIDs.contains($0.key) }
            state.playCountByPersistentID = state.playCountByPersistentID.filter { keepIDs.contains($0.key) }
        }
    }
}
