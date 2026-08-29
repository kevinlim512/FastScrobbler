import Foundation
import OSLog

@MainActor
enum ListeningHistoryScanService {
    enum DeliveryMode: Sendable, Equatable {
        case autoSubmit
        case queueForConfirmation
    }

    enum PauseBehavior {
        case respectPause
        case allowSubmissionWhilePaused
    }

    struct Result {
        let deliveryMode: DeliveryMode
        let importedCount: Int
        let importedRecentTrackCount: Int
        let flushedPlaybackHistoryCount: Int
        let flushedRecentTrackCount: Int
        let queuedPlaybackHistoryCount: Int
        let queuedRecentTrackCount: Int
        let pendingReviewCount: Int
        let skippedDuplicateCount: Int
        let recentTracksAuthorizationUnavailable: Bool
        let recentTracksStatus: AppleMusicRecentTracksImporter.ImportStatus

        var totalImportedCount: Int {
            importedCount + importedRecentTrackCount
        }

        var totalFlushedCount: Int {
            flushedPlaybackHistoryCount + flushedRecentTrackCount
        }

        var totalQueuedCount: Int {
            queuedPlaybackHistoryCount + queuedRecentTrackCount
        }

        var requiresConfirmation: Bool {
            deliveryMode == .queueForConfirmation
        }
    }

    private enum Limits {
        static let maxImports = 1000
        static let maxFlushBatches = 80
        static let emptyPlaybackHistoryRetryDelayNanoseconds: UInt64 = 1_500_000_000
    }

    private enum Keys {
        static let lastBacklogFlushAt = "FastScrobbler.AppModel.lastBacklogFlushAt"
    }

    private struct PlaybackHistoryImportSummary {
        let importedCount: Int
        let skippedDuplicateCount: Int
        let newestObservedPlayedAt: Date?
        let reviewEntries: [ListeningHistoryReviewStore.Entry]
    }

    private static let logger = Logger(subsystem: "FastScrobbler", category: "ListeningHistoryScanService")

    @discardableResult
    static func scan(
        backlog: ScrobbleBacklog,
        scrobbleLog: ScrobbleLogStore,
        sessionKey: String?,
        listenBrainzToken: String? = nil,
        maxItems: Int = 200,
        allowExtendedLookback: Bool = false,
        bypassRecentTrackCooldown: Bool = false,
        recoveryCutoffDate: Date? = nil,
        isUserPaused: Bool = false,
        pauseBehavior: PauseBehavior = .respectPause,
        deliveryMode: DeliveryMode = .autoSubmit,
        reviewStore: ListeningHistoryReviewStore? = nil,
        retryEmptyPlaybackHistoryImportOnce: Bool = false,
        beforePlaybackHistoryRetry: (() async -> Void)? = nil,
        recordSuccessfulScrobble: (() -> Void)? = nil
    ) async -> Result {
        let reviewStore = reviewStore ?? ListeningHistoryReviewStore.shared

        let extendedLookback = allowExtendedLookback && AppSettings.extendedListeningHistoryScanEnabled()
        let playbackHistorySummary = await importPlaybackHistory(
            backlog: backlog,
            scrobbleLog: scrobbleLog,
            maxItems: maxItems,
            extendedLookback: extendedLookback,
            deliveryMode: deliveryMode,
            recoveryCutoffDate: recoveryCutoffDate
        )
        var totalImported = playbackHistorySummary.importedCount
        var totalSkippedDuplicates = playbackHistorySummary.skippedDuplicateCount
        var playbackHistoryRetryRan = false
        var newestObservedPlayedAt = playbackHistorySummary.newestObservedPlayedAt
        var playbackHistoryReviewEntries = playbackHistorySummary.reviewEntries

        logger.info(
            "listening-history playback scan first pass: imported=\(playbackHistorySummary.importedCount, privacy: .public) skippedDuplicates=\(playbackHistorySummary.skippedDuplicateCount, privacy: .public) newestObservedPlayedAt=\(String(describing: playbackHistorySummary.newestObservedPlayedAt), privacy: .public)"
        )

        if shouldRetryEmptyPlaybackHistoryImport(
            retryEmptyPlaybackHistoryImportOnce: retryEmptyPlaybackHistoryImportOnce,
            isUserPaused: isUserPaused,
            firstPass: playbackHistorySummary
        ) {
            playbackHistoryRetryRan = true
            try? await Task.sleep(nanoseconds: Limits.emptyPlaybackHistoryRetryDelayNanoseconds)
            if Task.isCancelled {
                logger.info("listening-history playback scan retry canceled before re-run")
                playbackHistoryRetryRan = false
            } else {
                await beforePlaybackHistoryRetry?()

                let retrySummary = await importPlaybackHistory(
                    backlog: backlog,
                    scrobbleLog: scrobbleLog,
                    maxItems: maxItems,
                    extendedLookback: extendedLookback,
                    deliveryMode: deliveryMode,
                    recoveryCutoffDate: recoveryCutoffDate
                )
                totalImported += retrySummary.importedCount
                totalSkippedDuplicates += retrySummary.skippedDuplicateCount
                newestObservedPlayedAt = maxOptionalDate(newestObservedPlayedAt, retrySummary.newestObservedPlayedAt)
                playbackHistoryReviewEntries.append(contentsOf: retrySummary.reviewEntries)

                logger.info(
                    "listening-history playback scan retry: imported=\(retrySummary.importedCount, privacy: .public) skippedDuplicates=\(retrySummary.skippedDuplicateCount, privacy: .public) newestObservedPlayedAt=\(String(describing: retrySummary.newestObservedPlayedAt), privacy: .public)"
                )
            }
        }

        let recentImportResult: AppleMusicRecentTracksImporter.ImportResult
        switch deliveryMode {
        case .autoSubmit:
            recentImportResult = await AppleMusicRecentTracksImporter.shared.importIntoBacklog(
                backlog: backlog,
                scrobbleLog: scrobbleLog,
                maxItems: maxItems > 0 ? min(maxItems, 30) : 0,
                bypassCooldown: bypassRecentTrackCooldown,
                recoveryCutoffDate: recoveryCutoffDate
            )
        case .queueForConfirmation:
            recentImportResult = await AppleMusicRecentTracksImporter.shared.collectReviewEntries(
                backlog: backlog,
                scrobbleLog: scrobbleLog,
                maxItems: maxItems > 0 ? min(maxItems, 30) : 0,
                bypassCooldown: bypassRecentTrackCooldown,
                recoveryCutoffDate: recoveryCutoffDate
            )
        }
        totalSkippedDuplicates += recentImportResult.skippedDuplicateCount
        let queuedPlaybackHistoryCount: Int
        let queuedRecentTrackCount: Int
        let pendingReviewCount: Int

        switch deliveryMode {
        case .autoSubmit:
            queuedPlaybackHistoryCount = 0
            queuedRecentTrackCount = 0
            pendingReviewCount = reviewStore.pendingCount()
        case .queueForConfirmation:
            queuedPlaybackHistoryCount = reviewStore.upsert(playbackHistoryReviewEntries)
            queuedRecentTrackCount = reviewStore.upsert(recentImportResult.reviewEntries)
            pendingReviewCount = reviewStore.pendingCount()
        }

        logger.info(
            "listening-history scan complete: deliveryMode=\(String(describing: deliveryMode), privacy: .public) playbackImported=\(totalImported, privacy: .public) recentImported=\(recentImportResult.importedCount, privacy: .public) queuedPlayback=\(queuedPlaybackHistoryCount, privacy: .public) queuedRecent=\(queuedRecentTrackCount, privacy: .public) skippedDuplicates=\(totalSkippedDuplicates, privacy: .public) retryRan=\(playbackHistoryRetryRan, privacy: .public) newestObservedPlayedAt=\(String(describing: newestObservedPlayedAt), privacy: .public)"
        )

        if deliveryMode == .queueForConfirmation {
            return Result(
                deliveryMode: deliveryMode,
                importedCount: totalImported,
                importedRecentTrackCount: recentImportResult.importedCount,
                flushedPlaybackHistoryCount: 0,
                flushedRecentTrackCount: 0,
                queuedPlaybackHistoryCount: queuedPlaybackHistoryCount,
                queuedRecentTrackCount: queuedRecentTrackCount,
                pendingReviewCount: pendingReviewCount,
                skippedDuplicateCount: totalSkippedDuplicates,
                recentTracksAuthorizationUnavailable: recentImportResult.isAuthorizationUnavailable,
                recentTracksStatus: recentImportResult.status
            )
        }

        let shouldSuppressFlushWhilePaused = isUserPaused && pauseBehavior == .respectPause
        let hasAccount = (sessionKey?.isEmpty == false) || (listenBrainzToken?.isEmpty == false)
        guard hasAccount, !shouldSuppressFlushWhilePaused else {
            return Result(
                deliveryMode: deliveryMode,
                importedCount: totalImported,
                importedRecentTrackCount: recentImportResult.importedCount,
                flushedPlaybackHistoryCount: 0,
                flushedRecentTrackCount: 0,
                queuedPlaybackHistoryCount: queuedPlaybackHistoryCount,
                queuedRecentTrackCount: queuedRecentTrackCount,
                pendingReviewCount: pendingReviewCount,
                skippedDuplicateCount: totalSkippedDuplicates,
                recentTracksAuthorizationUnavailable: recentImportResult.isAuthorizationUnavailable,
                recentTracksStatus: recentImportResult.status
            )
        }

        var totalFlushedPlaybackHistoryCount = 0
        var totalFlushedRecentTrackCount = 0
        for _ in 0..<Limits.maxFlushBatches {
            if Task.isCancelled { break }

            let flushResult = await flushBacklog(
                backlog: backlog,
                scrobbleLog: scrobbleLog,
                sessionKey: sessionKey,
                listenBrainzToken: listenBrainzToken,
                recordSuccessfulScrobble: recordSuccessfulScrobble
            )
            let flushedPlaybackHistoryCount = flushResult.sentItems.reduce(into: 0) { count, item in
                if item.origin == .playbackHistory {
                    count += 1
                }
            }
            let flushedRecentTrackCount = flushResult.sentItems.reduce(into: 0) { count, item in
                if item.origin == .recentlyPlayed {
                    count += 1
                }
            }

            guard flushedPlaybackHistoryCount > 0 || flushedRecentTrackCount > 0 else { break }
            totalFlushedPlaybackHistoryCount += flushedPlaybackHistoryCount
            totalFlushedRecentTrackCount += flushedRecentTrackCount
        }

        return Result(
            deliveryMode: deliveryMode,
            importedCount: totalImported,
            importedRecentTrackCount: recentImportResult.importedCount,
            flushedPlaybackHistoryCount: totalFlushedPlaybackHistoryCount,
            flushedRecentTrackCount: totalFlushedRecentTrackCount,
            queuedPlaybackHistoryCount: queuedPlaybackHistoryCount,
            queuedRecentTrackCount: queuedRecentTrackCount,
            pendingReviewCount: pendingReviewCount,
            skippedDuplicateCount: totalSkippedDuplicates,
            recentTracksAuthorizationUnavailable: recentImportResult.isAuthorizationUnavailable,
            recentTracksStatus: recentImportResult.status
        )
    }

    private static func flushBacklog(
        backlog: ScrobbleBacklog,
        scrobbleLog: ScrobbleLogStore,
        sessionKey: String?,
        listenBrainzToken: String?,
        recordSuccessfulScrobble: (() -> Void)?
    ) async -> ScrobbleBacklog.FlushResult {
        let pending = await backlog.pendingCount()
        guard pending > 0 else {
            return ScrobbleBacklog.FlushResult(sentCount: 0, skippedCount: 0, remainingCount: 0, sentItems: [])
        }

        AppGroup.userDefaults.set(Date(), forKey: Keys.lastBacklogFlushAt)

        let result = await backlog.flush(sessionKey: sessionKey, listenBrainzToken: listenBrainzToken)
        let preventDuplicates = ProSettings.preventDuplicateScrobblesEnabled()
        for item in result.sentItems {
            scrobbleLog.record(
                track: item.track,
                startTimestamp: item.startTimestamp,
                scrobbledAt: item.scrobbledAt,
                source: scrobbleLogSource(for: item.origin),
                lovedOnLastFM: item.lovedOnLastFM,
                allowExactDuplicates: !preventDuplicates
            )
            recordSuccessfulScrobble?()
        }
        return result
    }

    private static func scrobbleLogSource(for origin: ScrobbleBacklog.Origin?) -> ScrobbleLogStore.Source {
        switch origin {
        case .playbackHistory:
            return .playbackHistory
        case .recentlyPlayed:
            return .recentlyPlayed
        case .manual:
            return .manual
        case .live, .none:
            return .backlog
        }
    }

    private static func importPlaybackHistory(
        backlog: ScrobbleBacklog,
        scrobbleLog: ScrobbleLogStore,
        maxItems: Int,
        extendedLookback: Bool,
        deliveryMode: DeliveryMode,
        recoveryCutoffDate: Date?
    ) async -> PlaybackHistoryImportSummary {
        guard maxItems > 0 else {
            return PlaybackHistoryImportSummary(importedCount: 0, skippedDuplicateCount: 0, newestObservedPlayedAt: nil, reviewEntries: [])
        }

        var totalImported = 0
        var totalSkippedDuplicates = 0
        var newestObservedPlayedAt: Date?
        var reviewEntries: [ListeningHistoryReviewStore.Entry] = []

        while totalImported < Limits.maxImports {
            if Task.isCancelled { break }

            let batchLimit = min(maxItems, Limits.maxImports - totalImported)
            let importResult: PlaybackHistoryImporter.ImportResult
            switch deliveryMode {
            case .autoSubmit:
                importResult = await PlaybackHistoryImporter.shared.importIntoBacklogDetailed(
                    backlog: backlog,
                    scrobbleLog: scrobbleLog,
                    maxItems: batchLimit,
                    mode: .recentBackfill(extendedLookback: extendedLookback),
                    recoveryCutoffDate: recoveryCutoffDate
                )
            case .queueForConfirmation:
                importResult = await PlaybackHistoryImporter.shared.collectReviewEntries(
                    backlog: backlog,
                    scrobbleLog: scrobbleLog,
                    maxItems: batchLimit,
                    mode: .recentBackfill(extendedLookback: extendedLookback),
                    recoveryCutoffDate: recoveryCutoffDate
                )
            }
            let imported = importResult.importedCount
            totalSkippedDuplicates += importResult.skippedDuplicateCount
            newestObservedPlayedAt = maxOptionalDate(newestObservedPlayedAt, importResult.newestObservedPlayedAt)
            reviewEntries.append(contentsOf: importResult.reviewEntries)

            guard imported > 0 else { break }
            totalImported += imported
        }

        return PlaybackHistoryImportSummary(
            importedCount: totalImported,
            skippedDuplicateCount: totalSkippedDuplicates,
            newestObservedPlayedAt: newestObservedPlayedAt,
            reviewEntries: reviewEntries
        )
    }

    private static func shouldRetryEmptyPlaybackHistoryImport(
        retryEmptyPlaybackHistoryImportOnce: Bool,
        isUserPaused: Bool,
        firstPass: PlaybackHistoryImportSummary
    ) -> Bool {
        retryEmptyPlaybackHistoryImportOnce &&
            !isUserPaused &&
            firstPass.importedCount == 0 &&
            firstPass.skippedDuplicateCount == 0
    }

    private static func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case (nil, nil):
            return nil
        }
    }
}
