import Foundation

func runListeningHistoryScanTests() {
    enum SimFlushOrigin {
        case live
        case playbackHistory
        case recentlyPlayed
        case manual
    }

    enum RecentTracksStatus {
        case authorizationUnavailable
        case seeded
        case fetchFailed
        case other
    }

    // ─── Listening History scan orchestration ────────────────────────────────────

    section("Listening History scan · One-press orchestration")

    func simulateListeningHistoryScan(
        importBatches: [Int],
        skippedDuplicateBatches: [Int] = [],
        flushBatches: [[SimFlushOrigin]],
        importBatchSize: Int = 200,
        maxImports: Int = 2000,
        maxFlushBatches: Int = 80
    ) -> (imported: Int, skippedDuplicates: Int, flushedPlaybackHistory: Int, importCalls: Int, flushCalls: Int) {
        var totalImported = 0
        var totalSkippedDuplicates = 0
        var importCalls = 0
        var importIndex = 0

        if importBatchSize > 0 {
            while totalImported < maxImports {
                let batchLimit = min(importBatchSize, maxImports - totalImported)
                guard batchLimit > 0 else { break }

                let requestedBatch = importIndex < importBatches.count ? importBatches[importIndex] : 0
                let skippedDuplicates = importIndex < skippedDuplicateBatches.count ? skippedDuplicateBatches[importIndex] : 0
                importIndex += 1
                importCalls += 1

                let imported = min(requestedBatch, batchLimit)
                totalSkippedDuplicates += skippedDuplicates
                guard imported > 0 else { break }
                totalImported += imported
            }
        }

        var totalFlushedPlaybackHistory = 0
        var flushCalls = 0
        var flushIndex = 0

        while flushCalls < maxFlushBatches {
            let origins = flushIndex < flushBatches.count ? flushBatches[flushIndex] : []
            flushIndex += 1
            flushCalls += 1

            let flushedPlaybackHistory = origins.filter { $0 == .playbackHistory }.count
            guard flushedPlaybackHistory > 0 else { break }
            totalFlushedPlaybackHistory += flushedPlaybackHistory
        }

        return (totalImported, totalSkippedDuplicates, totalFlushedPlaybackHistory, importCalls, flushCalls)
    }

    let multiBatchScan = simulateListeningHistoryScan(
        importBatches: [200, 200, 75, 0],
        flushBatches: [
            Array(repeating: .playbackHistory, count: 25),
            Array(repeating: .playbackHistory, count: 25),
            []
        ]
    )
    expectEqual("imports accumulate across batches until zero", multiBatchScan.imported, 475)
    expectEqual("no duplicate skips defaults to zero", multiBatchScan.skippedDuplicates, 0)
    expectEqual("import loop includes final zero batch call", multiBatchScan.importCalls, 4)
    expectEqual("flushes accumulate playback-history batches until zero", multiBatchScan.flushedPlaybackHistory, 50)
    expectEqual("flush loop includes final zero batch call", multiBatchScan.flushCalls, 3)

    let cappedImportScan = simulateListeningHistoryScan(
        importBatches: Array(repeating: 200, count: 20),
        flushBatches: []
    )
    expectEqual("import loop stops at max import cap", cappedImportScan.imported, 2000)
    expectEqual("import cap avoids one extra zero-probe call", cappedImportScan.importCalls, 10)

    let cappedFlushScan = simulateListeningHistoryScan(
        importBatches: [0],
        flushBatches: Array(repeating: Array(repeating: .playbackHistory, count: 25), count: 100)
    )
    expectEqual("flush loop stops at max flush batch cap", cappedFlushScan.flushedPlaybackHistory, 2000)
    expectEqual("flush cap stops after configured batch count", cappedFlushScan.flushCalls, 80)

    let blockedFlushScan = simulateListeningHistoryScan(
        importBatches: [50, 0],
        flushBatches: [
            [.live, .manual],
            Array(repeating: .playbackHistory, count: 25)
        ]
    )
    expectEqual("flush loop stops when a batch sends no playback-history items", blockedFlushScan.flushedPlaybackHistory, 0)
    expectEqual("blocked flush stops without probing later batches", blockedFlushScan.flushCalls, 1)

    let duplicateScan = simulateListeningHistoryScan(
        importBatches: [10, 0],
        skippedDuplicateBatches: [2, 7],
        flushBatches: []
    )
    expectEqual("scan accumulates duplicate skips from import batches", duplicateScan.skippedDuplicates, 9)

    section("Listening History scan · foreground startup ordering")

    enum ForegroundAction: String, Equatable {
        case startEngine
        case tickEngine
        case scanListeningHistory
        case flushBacklog
        case scheduleBackgroundProcessing
    }

    func foregroundStartupActions(isUserPaused: Bool) -> [ForegroundAction] {
        var actions: [ForegroundAction] = []

        if !isUserPaused {
            actions.append(.startEngine)
            actions.append(.tickEngine)
            actions.append(.scanListeningHistory)
            actions.append(.flushBacklog)
        }

        actions.append(.scheduleBackgroundProcessing)

        if !isUserPaused {
            actions.append(.startEngine)
            actions.append(.tickEngine)
        }

        return actions
    }

    func firstIndex(of action: ForegroundAction, in actions: [ForegroundAction]) -> Int? {
        actions.firstIndex(of: action)
    }

    let standardForegroundStart = foregroundStartupActions(isUserPaused: false)
    expect(
        "foreground startup primes the live session before scanning listening history",
        (firstIndex(of: .tickEngine, in: standardForegroundStart) ?? .max) <
            (firstIndex(of: .scanListeningHistory, in: standardForegroundStart) ?? .max)
    )
    expect(
        "foreground startup scans listening history before flushing backlog",
        (firstIndex(of: .scanListeningHistory, in: standardForegroundStart) ?? .max) <
            (firstIndex(of: .flushBacklog, in: standardForegroundStart) ?? .max)
    )
    expect(
        "foreground startup uses the unified scan path",
        standardForegroundStart.contains(.scanListeningHistory)
    )

    let pausedForegroundStart = foregroundStartupActions(isUserPaused: true)
    expect(
        "paused startup does not scan listening history",
        !pausedForegroundStart.contains(.scanListeningHistory)
    )
    expect(
        "paused startup does not submit backlog",
        !pausedForegroundStart.contains(.flushBacklog)
    )

    section("Listening History scan · user-triggered orchestration")

    enum UserInitiatedEntryPoint: CaseIterable {
        case homeRefresh
        case settingsScan
        case shortcutScan
    }

    enum UserInitiatedAction: String, Equatable {
        case refreshObserver
        case startEngine
        case tickEngine
        case runSharedScan
    }

    func userInitiatedScanActions(entryPoint: UserInitiatedEntryPoint, isUserPaused: Bool) -> [UserInitiatedAction] {
        var actions: [UserInitiatedAction] = []

        if !isUserPaused, entryPoint != .shortcutScan {
            actions.append(.refreshObserver)
            actions.append(.startEngine)
            actions.append(.tickEngine)
        }

        actions.append(.runSharedScan)
        return actions
    }

    for entryPoint in UserInitiatedEntryPoint.allCases {
        let actions = userInitiatedScanActions(entryPoint: entryPoint, isUserPaused: false)
        let expected: [UserInitiatedAction] = entryPoint == .shortcutScan
            ? [.runSharedScan]
            : [.refreshObserver, .startEngine, .tickEngine, .runSharedScan]
        expectEqual("user-triggered scan path is correct for \(entryPoint)", actions, expected)
    }

    for entryPoint in UserInitiatedEntryPoint.allCases {
        let actions = userInitiatedScanActions(entryPoint: entryPoint, isUserPaused: true)
        expectEqual(
            "paused user-triggered scans skip live priming for \(entryPoint)",
            actions,
            [.runSharedScan]
        )
    }

    section("Listening History scan · confirmation mode")

    func foregroundStartupActions(
        isUserPaused: Bool,
        requireConfirmation: Bool
    ) -> [ForegroundAction] {
        var actions: [ForegroundAction] = []

        if !isUserPaused, !requireConfirmation {
            actions.append(.startEngine)
            actions.append(.tickEngine)
            actions.append(.scanListeningHistory)
        }

        if !isUserPaused {
            actions.append(.flushBacklog)
        }

        actions.append(.scheduleBackgroundProcessing)

        if !isUserPaused {
            actions.append(.startEngine)
            actions.append(.tickEngine)
        }

        return actions
    }

    let confirmationForegroundStart = foregroundStartupActions(isUserPaused: false, requireConfirmation: true)
    expect(
        "confirmation mode skips automatic foreground listening-history scans",
        !confirmationForegroundStart.contains(.scanListeningHistory)
    )
    expect(
        "confirmation mode still flushes existing backlog on foreground start",
        confirmationForegroundStart.contains(.flushBacklog)
    )

    enum ScheduledRecoveryAction: Equatable {
        case importPlaybackHistory
        case importRecentTracks
        case flushBacklog
    }

    func scheduledRecoveryActions(
        isUserPaused: Bool,
        requireConfirmation: Bool,
        signedIn: Bool
    ) -> [ScheduledRecoveryAction] {
        var actions: [ScheduledRecoveryAction] = []

        if !requireConfirmation {
            actions.append(.importPlaybackHistory)
            if !isUserPaused {
                actions.append(.importRecentTracks)
            }
        }

        if !isUserPaused, signedIn {
            actions.append(.flushBacklog)
        }

        return actions
    }

    expectEqual(
        "scheduled recovery skips both listening-history sources in confirmation mode",
        scheduledRecoveryActions(isUserPaused: false, requireConfirmation: true, signedIn: true),
        [.flushBacklog]
    )
    expectEqual(
        "scheduled recovery keeps current import behavior when confirmation is off",
        scheduledRecoveryActions(isUserPaused: false, requireConfirmation: false, signedIn: true),
        [.importPlaybackHistory, .importRecentTracks, .flushBacklog]
    )

    func confirmationQueueResult(
        playbackQueued: Int,
        recentQueued: Int,
        existingPending: Int,
        skippedDuplicates: Int
    ) -> (queuedTotal: Int, pendingTotal: Int, flushedTotal: Int, skippedDuplicates: Int) {
        (
            queuedTotal: playbackQueued + recentQueued,
            pendingTotal: existingPending + playbackQueued + recentQueued,
            flushedTotal: 0,
            skippedDuplicates: skippedDuplicates
        )
    }

    let confirmationQueue = confirmationQueueResult(
        playbackQueued: 3,
        recentQueued: 2,
        existingPending: 4,
        skippedDuplicates: 1
    )
    expectEqual("confirmation mode reports newly queued items", confirmationQueue.queuedTotal, 5)
    expectEqual("confirmation mode preserves existing pending items in the queue", confirmationQueue.pendingTotal, 9)
    expectEqual("confirmation mode does not auto-submit queued items", confirmationQueue.flushedTotal, 0)
    expectEqual("confirmation mode still reports duplicate skips", confirmationQueue.skippedDuplicates, 1)

    func shortcutScanOpensApp(requireConfirmation: Bool) -> Bool {
        let _ = requireConfirmation
        return true
    }

    expect("shortcut scan opens the app when confirmation mode is on", shortcutScanOpensApp(requireConfirmation: true))
    expect("shortcut scan opens the app when confirmation mode is off", shortcutScanOpensApp(requireConfirmation: false))

    enum ShortcutScanPresentation: Equatable {
        case openHomeAlert
        case openHomeReview
    }

    func shortcutScanPresentation(requireConfirmation: Bool) -> ShortcutScanPresentation {
        requireConfirmation ? .openHomeReview : .openHomeAlert
    }

    expectEqual(
        "shortcut scan opens the Home review list when confirmation mode is on",
        shortcutScanPresentation(requireConfirmation: true),
        .openHomeReview
    )
    expectEqual(
        "shortcut scan opens Home and shows the result alert when confirmation mode is off",
        shortcutScanPresentation(requireConfirmation: false),
        .openHomeAlert
    )

    enum SimHomeTab: Equatable {
        case home
        case settings
    }

    enum PendingLaunchRequest: Equatable {
        case openReviewOnly
        case scanAndOpenReview
        case scanAndShowResult
    }

    struct PendingLaunchRequestState: Equatable {
        let requestConsumed: Bool
        let selectedTab: SimHomeTab
        let isShowingReview: Bool
        let isShowingResultAlert: Bool
    }

    func consumePendingLaunchRequest(
        request: PendingLaunchRequest?,
        pendingReviewCount: Int = 0,
        hasSeenSetup: Bool,
        isShowingSetup: Bool,
        isShowingWhatsNew: Bool,
        currentTab: SimHomeTab,
        isShowingReview: Bool,
        isShowingResultAlert: Bool
    ) -> PendingLaunchRequestState {
        guard let request else {
            return PendingLaunchRequestState(
                requestConsumed: false,
                selectedTab: currentTab,
                isShowingReview: isShowingReview,
                isShowingResultAlert: isShowingResultAlert
            )
        }
        guard hasSeenSetup, !isShowingSetup, !isShowingWhatsNew else {
            return PendingLaunchRequestState(
                requestConsumed: false,
                selectedTab: currentTab,
                isShowingReview: isShowingReview,
                isShowingResultAlert: isShowingResultAlert
            )
        }

        return PendingLaunchRequestState(
            requestConsumed: true,
            selectedTab: .home,
            isShowingReview: request == .openReviewOnly || (request == .scanAndOpenReview && pendingReviewCount > 0),
            isShowingResultAlert: request == .scanAndShowResult || (request == .scanAndOpenReview && pendingReviewCount == 0)
        )
    }

    expectEqual(
        "pending scan-and-open-review request switches back to Home and presents the review sheet",
        consumePendingLaunchRequest(
            request: .scanAndOpenReview,
            pendingReviewCount: 3,
            hasSeenSetup: true,
            isShowingSetup: false,
            isShowingWhatsNew: false,
            currentTab: .settings,
            isShowingReview: false,
            isShowingResultAlert: true
        ),
        PendingLaunchRequestState(
            requestConsumed: true,
            selectedTab: .home,
            isShowingReview: true,
            isShowingResultAlert: false
        )
    )
    expectEqual(
        "pending listening-history launch request waits until setup and Whats New are out of the way",
        consumePendingLaunchRequest(
            request: .scanAndShowResult,
            pendingReviewCount: 0,
            hasSeenSetup: true,
            isShowingSetup: false,
            isShowingWhatsNew: true,
            currentTab: .settings,
            isShowingReview: false,
            isShowingResultAlert: false
        ),
        PendingLaunchRequestState(
            requestConsumed: false,
            selectedTab: .settings,
            isShowingReview: false,
            isShowingResultAlert: false
        )
    )
    expectEqual(
        "pending scan-and-show-result request clears stale alerts and shows the new result on Home",
        consumePendingLaunchRequest(
            request: .scanAndShowResult,
            pendingReviewCount: 0,
            hasSeenSetup: true,
            isShowingSetup: false,
            isShowingWhatsNew: false,
            currentTab: .settings,
            isShowingReview: true,
            isShowingResultAlert: true
        ),
        PendingLaunchRequestState(
            requestConsumed: true,
            selectedTab: .home,
            isShowingReview: false,
            isShowingResultAlert: true
        )
    )
    expectEqual(
        "pending scan-and-open-review request falls back to the existing no-new-plays alert when nothing is queued",
        consumePendingLaunchRequest(
            request: .scanAndOpenReview,
            pendingReviewCount: 0,
            hasSeenSetup: true,
            isShowingSetup: false,
            isShowingWhatsNew: false,
            currentTab: .settings,
            isShowingReview: true,
            isShowingResultAlert: false
        ),
        PendingLaunchRequestState(
            requestConsumed: true,
            selectedTab: .home,
            isShowingReview: false,
            isShowingResultAlert: true
        )
    )
    expectEqual(
        "consumed listening-history launch request does not reopen on later checks",
        consumePendingLaunchRequest(
            request: nil,
            pendingReviewCount: 0,
            hasSeenSetup: true,
            isShowingSetup: false,
            isShowingWhatsNew: false,
            currentTab: .home,
            isShowingReview: false,
            isShowingResultAlert: false
        ),
        PendingLaunchRequestState(
            requestConsumed: false,
            selectedTab: .home,
            isShowingReview: false,
            isShowingResultAlert: false
        )
    )

    enum ReviewLeadingAction: Equatable {
        case close
        case selectAll
        case deselectAll
    }

    func reviewLeadingAction(selectedCount: Int, totalCount: Int) -> ReviewLeadingAction {
        if selectedCount == 0 { return .close }
        if totalCount > 0, selectedCount == totalCount { return .deselectAll }
        return .selectAll
    }

    expectEqual("review screen shows Close with no selection", reviewLeadingAction(selectedCount: 0, totalCount: 5), .close)
    expectEqual("review screen shows Select All with a partial selection", reviewLeadingAction(selectedCount: 2, totalCount: 5), .selectAll)
    expectEqual("review screen shows Deselect All when everything is selected", reviewLeadingAction(selectedCount: 5, totalCount: 5), .deselectAll)

    func reviewDeleteButtonTitle(selectedCount: Int) -> String {
        selectedCount > 0 ? "Delete Selected (\(selectedCount))" : "Delete Selected"
    }

    func reviewSubmitButtonTitle(selectedCount: Int) -> String {
        selectedCount > 0 ? "Submit Selected (\(selectedCount))" : "Submit All"
    }

    func reviewCanDelete(selectedCount: Int) -> Bool {
        selectedCount > 0
    }

    expectEqual("review screen shows Delete Selected with no selection", reviewDeleteButtonTitle(selectedCount: 0), "Delete Selected")
    expectEqual("review screen shows Submit All with no selection", reviewSubmitButtonTitle(selectedCount: 0), "Submit All")
    expectEqual("review screen shows Delete Selected count for partial selection", reviewDeleteButtonTitle(selectedCount: 2), "Delete Selected (2)")
    expectEqual("review screen shows Submit Selected count for partial selection", reviewSubmitButtonTitle(selectedCount: 2), "Submit Selected (2)")
    expect("review screen disables delete with no selection", !reviewCanDelete(selectedCount: 0))
    expect("review screen enables delete for partial selection", reviewCanDelete(selectedCount: 2))

    func pendingQueueAfterDelete(totalCount: Int, selectedCount: Int) -> Int {
        max(0, totalCount - selectedCount)
    }

    expectEqual("deleting selected items removes only those items from the pending queue", pendingQueueAfterDelete(totalCount: 6, selectedCount: 2), 4)

    func pendingQueueAfterSubmit(totalCount: Int, selectedCount: Int) -> Int {
        selectedCount > 0 ? max(0, totalCount - selectedCount) : 0
    }

    expectEqual("submitting selected items leaves unselected rows pending", pendingQueueAfterSubmit(totalCount: 6, selectedCount: 2), 4)
    expectEqual("submitting all items drains the pending queue", pendingQueueAfterSubmit(totalCount: 6, selectedCount: 0), 0)

    func pendingQueueWhenConfirmationChanges(existingPending: Int, requireConfirmation: Bool) -> Int {
        requireConfirmation ? existingPending : 0
    }

    expectEqual("turning confirmation off submits the pending review queue", pendingQueueWhenConfirmationChanges(existingPending: 5, requireConfirmation: false), 0)
    expectEqual("keeping confirmation on preserves the pending review queue", pendingQueueWhenConfirmationChanges(existingPending: 5, requireConfirmation: true), 5)

    section("Listening History scan · empty-result retry")

    func simulateRetryablePlaybackHistoryScan(
        firstPassImported: Int,
        firstPassSkippedDuplicates: Int,
        retryImported: Int,
        retrySkippedDuplicates: Int = 0,
        isUserPaused: Bool,
        retryEnabled: Bool
    ) -> (totalImported: Int, totalSkippedDuplicates: Int, retryRan: Bool, importPasses: Int) {
        var totalImported = firstPassImported
        var totalSkippedDuplicates = firstPassSkippedDuplicates
        var retryRan = false
        var importPasses = 1

        let shouldRetry =
            retryEnabled &&
            !isUserPaused &&
            firstPassImported == 0 &&
            firstPassSkippedDuplicates == 0

        if shouldRetry {
            retryRan = true
            importPasses += 1
            totalImported += retryImported
            totalSkippedDuplicates += retrySkippedDuplicates
        }

        return (totalImported, totalSkippedDuplicates, retryRan, importPasses)
    }

    let delayedMetadataRecovery = simulateRetryablePlaybackHistoryScan(
        firstPassImported: 0,
        firstPassSkippedDuplicates: 0,
        retryImported: 3,
        isUserPaused: false,
        retryEnabled: true
    )
    expect("empty first pass triggers exactly one retry", delayedMetadataRecovery.retryRan)
    expectEqual("retry imports late library plays", delayedMetadataRecovery.totalImported, 3)
    expectEqual("retry performs exactly two playback-history import passes", delayedMetadataRecovery.importPasses, 2)

    let noRetryAfterSuccess = simulateRetryablePlaybackHistoryScan(
        firstPassImported: 2,
        firstPassSkippedDuplicates: 0,
        retryImported: 5,
        isUserPaused: false,
        retryEnabled: true
    )
    expect("successful first pass skips retry", !noRetryAfterSuccess.retryRan)
    expectEqual("successful first pass keeps original import count", noRetryAfterSuccess.totalImported, 2)

    let noRetryAfterDuplicates = simulateRetryablePlaybackHistoryScan(
        firstPassImported: 0,
        firstPassSkippedDuplicates: 2,
        retryImported: 4,
        isUserPaused: false,
        retryEnabled: true
    )
    expect("duplicate-only first pass skips retry", !noRetryAfterDuplicates.retryRan)
    expectEqual("duplicate-only first pass preserves skipped duplicate count", noRetryAfterDuplicates.totalSkippedDuplicates, 2)

    let noRetryWhilePaused = simulateRetryablePlaybackHistoryScan(
        firstPassImported: 0,
        firstPassSkippedDuplicates: 0,
        retryImported: 4,
        isUserPaused: true,
        retryEnabled: true
    )
    expect("paused scans do not retry empty playback-history results", !noRetryWhilePaused.retryRan)

    // ─── Listening History scan cutoff ───────────────────────────────────────────

    section("Listening History scan · First-scan lookback")

    enum PlaybackHistoryImportMode {
        case newPlaysOnly
        case recentBackfill
    }

    func playbackHistoryFetchCutoff(
        now: Int,
        lastImportAt: Int?,
        mode: PlaybackHistoryImportMode,
        extendedLookback: Bool = false,
        maxStandardLookbackHours: Int = 36,
        maxRecentBackfillLookbackDays: Int = 7
    ) -> Int {
        let standardLookback = now - maxStandardLookbackHours * 60 * 60
        let recentBackfillLookback = now - maxRecentBackfillLookbackDays * 24 * 60 * 60
        let lookback: Int = {
            switch mode {
            case .newPlaysOnly:
                return standardLookback
            case .recentBackfill:
                return extendedLookback ? recentBackfillLookback : standardLookback
            }
        }()
        let cutoff = lastImportAt ?? lookback

        if mode == .recentBackfill { return lookback }
        guard lastImportAt != nil else { return max(cutoff, lookback) }
        return lookback
    }

    let now = 1_000_000
    expectEqual(
        "automatic import uses 36-hour lookback cap",
        playbackHistoryFetchCutoff(now: now, lastImportAt: now - 2 * 60 * 60, mode: .newPlaysOnly),
        now - 36 * 60 * 60
    )
    expectEqual(
        "manual standard scan uses 36-hour lookback",
        playbackHistoryFetchCutoff(now: now, lastImportAt: nil, mode: .recentBackfill),
        now - 36 * 60 * 60
    )
    expectEqual(
        "manual extended scan uses 7-day lookback",
        playbackHistoryFetchCutoff(now: now, lastImportAt: nil, mode: .recentBackfill, extendedLookback: true),
        now - 7 * 24 * 60 * 60
    )
    expectEqual(
        "manual standard scan keeps 36-hour lookback even with an existing cursor",
        playbackHistoryFetchCutoff(now: now, lastImportAt: now - 2 * 60 * 60, mode: .recentBackfill),
        now - 36 * 60 * 60
    )
    expectEqual(
        "manual extended scan keeps 7-day lookback even with an existing cursor",
        playbackHistoryFetchCutoff(now: now, lastImportAt: now - 2 * 60 * 60, mode: .recentBackfill, extendedLookback: true),
        now - 7 * 24 * 60 * 60
    )

    func shouldInitializeCursorWithoutImport(lastImportAt: Int?, mode: PlaybackHistoryImportMode) -> Bool {
        lastImportAt == nil && mode == .newPlaysOnly
    }

    expect(
        "automatic first import initializes cursor instead of backfilling",
        shouldInitializeCursorWithoutImport(lastImportAt: nil, mode: .newPlaysOnly)
    )
    expect(
        "manual first scan remains an explicit recent-history backfill",
        !shouldInitializeCursorWithoutImport(lastImportAt: nil, mode: .recentBackfill)
    )

    section("Listening History scan · Resume cutoff")

    enum ResumeCutoffEntryPoint: CaseIterable {
        case homeRefresh
        case settingsScan
        case shortcutScan
    }

    func filteredPlaybackHistoryPlayedAts(
        playedAts: [Int],
        recoveryCutoff: Int?
    ) -> [Int] {
        playedAts.filter { playedAt in
            guard let recoveryCutoff else { return true }
            return playedAt > recoveryCutoff
        }
    }

    func filteredRecentTrackPlayedAts(
        playedAts: [Int],
        recoveryCutoff: Int?
    ) -> [Int] {
        playedAts.filter { playedAt in
            guard let recoveryCutoff else { return true }
            return playedAt > recoveryCutoff
        }
    }

    func persistedPlaybackHistoryCursor(
        priorLastImportAt: Int?,
        newestImportedPlayedAt: Int?,
        recoveryCutoff: Int?
    ) -> Int? {
        if let newestImportedPlayedAt {
            return [priorLastImportAt, newestImportedPlayedAt, recoveryCutoff].compactMap { $0 }.max()
        }
        if let recoveryCutoff {
            return max(priorLastImportAt ?? recoveryCutoff, recoveryCutoff)
        }
        return priorLastImportAt
    }

    expectEqual(
        "resume cutoff filters playback-history plays at or before resume",
        filteredPlaybackHistoryPlayedAts(playedAts: [90, 100, 110], recoveryCutoff: 100),
        [110]
    )
    expectEqual(
        "resume cutoff filters recently played candidates at or before resume",
        filteredRecentTrackPlayedAts(playedAts: [95, 100, 105], recoveryCutoff: 100),
        [105]
    )

    for entryPoint in ResumeCutoffEntryPoint.allCases {
        expectEqual(
            "resume cutoff applies to \(entryPoint) scans",
            filteredPlaybackHistoryPlayedAts(playedAts: [80, 100, 120], recoveryCutoff: 100),
            [120]
        )
    }

    expectEqual(
        "playback-history cursor advances to the resume cutoff even with no post-resume imports",
        persistedPlaybackHistoryCursor(priorLastImportAt: 70, newestImportedPlayedAt: nil, recoveryCutoff: 100),
        100
    )

    // ─── Listening History scan dialog summary ───────────────────────────────────

    section("Listening History scan · Dialog summary")

    func listeningHistorySummary(importedCount: Int, skippedDuplicateCount: Int, flushedOrigins: [SimFlushOrigin]) -> String? {
        let flushedPlaybackHistoryCount = flushedOrigins.filter { $0 == .playbackHistory }.count
        guard importedCount > 0 || flushedPlaybackHistoryCount > 0 || skippedDuplicateCount > 0 else {
            return nil
        }
        return "Found \(importedCount); Submitted \(flushedPlaybackHistoryCount); Skipped \(skippedDuplicateCount)"
    }

    func listeningHistoryEmptyStateMessage(recentTracksStatus: RecentTracksStatus) -> String {
        switch recentTracksStatus {
        case .authorizationUnavailable:
            return "No new library plays found. Apple Music recent tracks could not be checked because Music access is disabled."
        case .seeded:
            return "Apple Music recent tracks were initialized from your current history. Future scans will only import newer plays."
        case .fetchFailed:
            return "No new library plays found. Apple Music recent tracks could not be checked because the Apple Music API request failed."
        case .other:
            return "No new plays found. Scrobbling from Listening History only works for songs added to your Library."
        }
    }

    func pausedScanResult(importedCount: Int, importedRecentTrackCount: Int, skippedDuplicateCount: Int) -> (flushedPlaybackHistory: Int, flushedRecentTracks: Int, skippedDuplicates: Int) {
        (flushedPlaybackHistory: 0, flushedRecentTracks: 0, skippedDuplicates: skippedDuplicateCount)
    }

    func pausedExplicitScanResult(
        importedCount: Int,
        importedRecentTrackCount: Int,
        skippedDuplicateCount: Int
    ) -> (flushedPlaybackHistory: Int, flushedRecentTracks: Int, skippedDuplicates: Int) {
        (
            flushedPlaybackHistory: importedCount,
            flushedRecentTracks: importedRecentTrackCount,
            skippedDuplicates: skippedDuplicateCount
        )
    }

    expectEqual(
        "summary reports flushed playback-history plays separately",
        listeningHistorySummary(importedCount: 0, skippedDuplicateCount: 0, flushedOrigins: [.playbackHistory, .playbackHistory]),
        "Found 0; Submitted 2; Skipped 0"
    )
    expectEqual(
        "summary reports imports when no playback-history items were flushed",
        listeningHistorySummary(importedCount: 3, skippedDuplicateCount: 0, flushedOrigins: []),
        "Found 3; Submitted 0; Skipped 0"
    )
    expectEqual(
        "summary ignores non-playback-history flushes",
        listeningHistorySummary(importedCount: 0, skippedDuplicateCount: 0, flushedOrigins: [.live, .manual, .recentlyPlayed]),
        nil
    )
    expectEqual(
        "summary includes duplicate skips",
        listeningHistorySummary(importedCount: 0, skippedDuplicateCount: 5, flushedOrigins: []),
        "Found 0; Submitted 0; Skipped 5"
    )
    expectEqual(
        "mixed flush origins count only playback-history submissions",
        listeningHistorySummary(importedCount: 4, skippedDuplicateCount: 1, flushedOrigins: [.live, .playbackHistory, .manual, .playbackHistory]),
        "Found 4; Submitted 2; Skipped 1"
    )
    let pausedResult = pausedScanResult(importedCount: 3, importedRecentTrackCount: 2, skippedDuplicateCount: 1)
    expectEqual("paused scan suppresses playback-history flushes", pausedResult.flushedPlaybackHistory, 0)
    expectEqual("paused scan suppresses recent-track flushes", pausedResult.flushedRecentTracks, 0)
    expectEqual("paused scan still reports duplicate skips", pausedResult.skippedDuplicates, 1)
    let pausedExplicitResult = pausedExplicitScanResult(importedCount: 3, importedRecentTrackCount: 2, skippedDuplicateCount: 1)
    expectEqual("paused explicit scan flushes playback-history items", pausedExplicitResult.flushedPlaybackHistory, 3)
    expectEqual("paused explicit scan flushes recent-track items", pausedExplicitResult.flushedRecentTracks, 2)
    expectEqual("paused explicit scan still reports duplicate skips", pausedExplicitResult.skippedDuplicates, 1)
    expectEqual(
        "empty-state auth message remains specific",
        listeningHistoryEmptyStateMessage(recentTracksStatus: .authorizationUnavailable),
        "No new library plays found. Apple Music recent tracks could not be checked because Music access is disabled."
    )
    expectEqual(
        "empty-state seeded message explains first-run behavior",
        listeningHistoryEmptyStateMessage(recentTracksStatus: .seeded),
        "Apple Music recent tracks were initialized from your current history. Future scans will only import newer plays."
    )
    expectEqual(
        "empty-state fetch-failed message is distinct",
        listeningHistoryEmptyStateMessage(recentTracksStatus: .fetchFailed),
        "No new library plays found. Apple Music recent tracks could not be checked because the Apple Music API request failed."
    )
}
