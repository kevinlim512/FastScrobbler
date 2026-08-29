import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppModel {
    typealias ListeningHistoryScanResult = ListeningHistoryScanService.Result

    static let shared = AppModel()

    private enum Keys {
        static let lastBacklogFlushAt = "FastScrobbler.AppModel.lastBacklogFlushAt"
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
        static let lastEnteredBackgroundAt = "FastScrobbler.AppModel.lastEnteredBackgroundAt"
        static let storageMigrationVersion = "FastScrobbler.StorageMaintenance.migrationVersion"
    }

    private enum LiveBackgroundScrobbling {
        static let tickIntervalSeconds: TimeInterval = 4
        static let backlogFlushIntervalSeconds: TimeInterval = 30
        static let backgroundTimeSafetyMarginSeconds: TimeInterval = 2
        static let backgroundProjectionWindowSeconds: TimeInterval = 45
        static let inactivePlaybackToleranceSeconds: TimeInterval = 8
    }

    let auth: LastFMAuthManager
    let listenBrainzAuth: ListenBrainzAuthManager
    let observer: AppleMusicNowPlayingObserver
    let engine: ScrobbleEngine
    let backlog: ScrobbleBacklog
    let scrobbleLog: ScrobbleLogStore

    private var startTask: Task<Void, Never>?
    private var liveBackgroundScrobbleTask: Task<Void, Never>?
    private var isStartInFlight = false

    private init() {
        let auth = LastFMAuthManager()
        let listenBrainzAuth = ListenBrainzAuthManager()
        let observer = AppleMusicNowPlayingObserver()
        self.auth = auth
        self.listenBrainzAuth = listenBrainzAuth
        self.observer = observer
        let backlog = ScrobbleBacklog.shared
        self.backlog = backlog
        let scrobbleLog = ScrobbleLogStore.shared
        self.scrobbleLog = scrobbleLog
        self.engine = ScrobbleEngine(
            auth: auth,
            listenBrainzAuth: listenBrainzAuth,
            observer: observer,
            backlog: backlog,
            scrobbleLog: scrobbleLog
        )
    }

    func startIfNeeded() {
        guard !isStartInFlight else { return }
        isStartInFlight = true
        startTask = Task { @MainActor in
            defer {
                self.isStartInFlight = false
                self.startTask = nil
            }
            await self.performStart()
        }
    }

    private func performStart() async {
        AppSettings.migrateLegacyAppGroupSettingsIfNeeded()
        AppSettings.seedScrobbleAppleMusicAPIEnabledIfNeeded()
        AppSettings.seedScrobbleOnlyNonLibraryAppleMusicAPITracksIfNeeded()
        AppSettings.removeLegacyListeningHistoryScrobblingToggleIfNeeded()
        ProSettings.migrateLegacyAppGroupSettingsIfNeeded()
        await runStorageMaintenanceIfNeeded()
        await ICloudSyncCoordinator.shared.startIfNeeded()
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

        if #available(iOS 16.2, *) {
            await LiveActivityManager.shared.startIfPossible()
        }

        do {
            try await observer.start()
        } catch {
            await LiveActivityManager.shared.update(
                status: error.localizedDescription,
                track: nil,
                lastEventAt: Date(),
                isActivelyScrobbling: false,
                throttleSeconds: 0
            )
            return
        }
        guard !Task.isCancelled else { return }

        await backlog.cleanupNow()

        if auth.sessionKey == nil && !listenBrainzAuth.isConnected {
            await LiveActivityManager.shared.update(
                status: NSLocalizedString("Connect Last.fm or ListenBrainz to scrobble.", comment: ""),
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false,
                throttleSeconds: 0
            )
            return
        }

        if auth.sessionKey != nil || listenBrainzAuth.isConnected {
            if auth.sessionKey != nil {
                await auth.refreshUserInfoIfNeeded()
            }
            if listenBrainzAuth.isConnected {
                await listenBrainzAuth.refreshUserInfoIfNeeded()
            }

            let shouldRunForegroundScan = !engine.isUserPaused && !AppSettings.listeningHistoryRequireConfirmationEnabled()
            if shouldRunForegroundScan {
                await primeForegroundListeningHistoryScanIfNeeded()
            }

            let imported: Int
            let recentImported: Int
            if shouldRunForegroundScan {
                let scanResult = await scanListeningHistory(
                    allowExtendedLookback: false,
                    allowSubmissionWhilePaused: false,
                    bypassRecentTrackCooldown: true
                )
                imported = scanResult.importedCount
                recentImported = scanResult.importedRecentTrackCount
            } else {
                imported = 0
                recentImported = 0
            }
            UserDefaults.standard.removeObject(forKey: Keys.lastEnteredBackgroundAt)
            if !engine.isUserPaused {
                await flushBacklogIfNeeded(sessionKey: auth.sessionKey, force: imported > 0 || recentImported > 0)
            }
            BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        }

        // Foreground transitions can leave Timers paused or invalidated.
        if !engine.isUserPaused {
            engine.start()

            // Ensure the app immediately re-sync state on foreground transitions (Timers pause while backgrounded).
            await engine.tickAsync()
        }
    }

    func handleSceneDidBecomeActive() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

        if #available(iOS 16.2, *) {
            await LiveActivityManager.shared.handleAppBecameActive()
        }
    }

    func handleWillEnterForeground() {
        stopLiveBackgroundScrobbleLoop()
        BackgroundTaskManager.shared.endLiveScrobbleGracePeriod()
        observer.resumePolling()
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.clearEnteredBackground()
        }
    }

    func prepareForBackground() {
        let backgroundedAt = Date()
        UserDefaults.standard.set(backgroundedAt, forKey: Keys.lastEnteredBackgroundAt)
        LiveActivityManager.shared.recordEnteredBackground(at: backgroundedAt)
        stopLiveBackgroundScrobbleLoop()

        // Schedule BGAppRefreshTask and BGProcessingTask immediately so iOS gets maximum lead time
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()

        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected
        let shouldKeepLiveScrobbling =
            UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) &&
            hasAnyAccount &&
            !engine.isUserPaused &&
            engine.isRunning &&
            observer.isRunning &&
            observer.track != nil &&
            observer.playbackState == .playing

        if shouldKeepLiveScrobbling {
            let started = BackgroundTaskManager.shared.startLiveScrobbleGracePeriod { [weak self] in
                await self?.finishBackgroundGracePeriodIfNeeded()
            }
            if !started {
                observer.suspendPolling()
                engine.pauseForBackground()
            } else {
                observer.suspendPolling()
                engine.pauseForBackground()
                Task { @MainActor [weak self] in
                    await self?.performImmediateBackgroundScrobbleCheck()
                }
                startLiveBackgroundScrobbleLoop()
            }
        } else {
            observer.suspendPolling()
            engine.pauseForBackground()
        }

        Task { @MainActor in
            if #available(iOS 16.2, *) {
                await LiveActivityManager.shared.scheduleDismissalAfterAppClosed(backgroundedAt: backgroundedAt)
            }
        }
    }

    func finishBackgroundGracePeriodIfNeeded() async {
        guard UserDefaults.standard.object(forKey: Keys.lastEnteredBackgroundAt) != nil else { return }

        stopLiveBackgroundScrobbleLoop()
        await engine.tickAsync()

        // Persist last known playback snapshot if a track was playing when grace expired
        if let track = observer.track, observer.playbackState == .playing {
            let snapshot: [String: Any] = [
                "dedupeKey": track.dedupeKey,
                "title": track.title,
                "artist": track.artist,
                "playbackTimeSeconds": observer.playbackTimeSeconds,
                "snapshotAt": Date()
            ]
            UserDefaults.standard.set(snapshot, forKey: "FastScrobbler.AppModel.lastGracePlaybackSnapshot")
        }

        engine.pauseForBackground()
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
    }

    private func performImmediateBackgroundScrobbleCheck() async {
        guard shouldContinueLiveBackgroundScrobbling() else { return }

        observer.refreshOnceIfAuthorized()
        await engine.tickAsync()
        BackgroundTaskManager.shared.recordLiveScrobbleGraceProjectionAttempt()
        _ = await engine.attemptProjectedBackgroundScrobble(
            maxProjectionSeconds: LiveBackgroundScrobbling.backgroundProjectionWindowSeconds
        )
    }

    private func startLiveBackgroundScrobbleLoop() {
        stopLiveBackgroundScrobbleLoop()

        liveBackgroundScrobbleTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var lastBacklogFlushAt = Date.distantPast
            var inactivePlaybackStartedAt: Date?

            while !Task.isCancelled {
                self.observer.refreshOnceIfAuthorized()

                let now = Date()
                if self.shouldContinueLiveBackgroundScrobbling() {
                    inactivePlaybackStartedAt = nil
                } else {
                    let inactiveStartedAt = inactivePlaybackStartedAt ?? now
                    inactivePlaybackStartedAt = inactiveStartedAt
                    guard now.timeIntervalSince(inactiveStartedAt) < LiveBackgroundScrobbling.inactivePlaybackToleranceSeconds else {
                        break
                    }
                }

                await self.engine.tickAsync()
                BackgroundTaskManager.shared.recordLiveScrobbleGraceProjectionAttempt()
                _ = await self.engine.attemptProjectedBackgroundScrobble(
                    maxProjectionSeconds: LiveBackgroundScrobbling.backgroundProjectionWindowSeconds
                )

                let hasAnyAccount = self.auth.sessionKey != nil || self.listenBrainzAuth.isConnected
                if now.timeIntervalSince(lastBacklogFlushAt) >= LiveBackgroundScrobbling.backlogFlushIntervalSeconds,
                   hasAnyAccount {
                    await self.flushBacklogIfNeeded()
                    lastBacklogFlushAt = now
                }

                let remainingBackgroundTime = BackgroundTaskManager.shared.liveScrobbleBackgroundTimeRemaining
                if remainingBackgroundTime.isFinite,
                   remainingBackgroundTime <= LiveBackgroundScrobbling.backgroundTimeSafetyMarginSeconds {
                    await BackgroundTaskManager.shared.expireLiveScrobbleGracePeriodBecauseBackgroundTimeIsNearlyExhausted(
                        remaining: remainingBackgroundTime
                    )
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(LiveBackgroundScrobbling.tickIntervalSeconds * 1_000_000_000))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await BackgroundTaskManager.shared.expireLiveScrobbleGracePeriodBecausePlaybackIsNoLongerActive()
        }
    }

    private func stopLiveBackgroundScrobbleLoop() {
        liveBackgroundScrobbleTask?.cancel()
        liveBackgroundScrobbleTask = nil
    }

    private func shouldContinueLiveBackgroundScrobbling() -> Bool {
        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected
        return UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) &&
            hasAnyAccount &&
            !engine.isUserPaused &&
            engine.isRunning &&
            observer.isRunning &&
            observer.track != nil &&
            observer.playbackState == .playing
    }

    // Scheduled BG tasks are recovery-only: import missed plays and flush backlog
    // without resuming the live scrobble engine's in-memory session.
    func performScheduledBackgroundRecovery() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }
        let recoveryCutoffDate = AppSettings.listeningHistoryResumeRecoveryCutoffDate()

        if !AppSettings.listeningHistoryRequireConfirmationEnabled() {
            _ = await PlaybackHistoryImporter.shared.importIntoBacklog(
                backlog: backlog,
                scrobbleLog: scrobbleLog,
                recoveryCutoffDate: recoveryCutoffDate
            )
            if !engine.isUserPaused {
                _ = await AppleMusicRecentTracksImporter.shared.importIntoBacklog(
                    backlog: backlog,
                    scrobbleLog: scrobbleLog,
                    allowAuthorizationPrompt: false,
                    recoveryCutoffDate: recoveryCutoffDate
                )
            }
        }

        if !engine.isUserPaused, (auth.sessionKey != nil || listenBrainzAuth.isConnected) {
            let result = await backlog.flush(sessionKey: auth.sessionKey, listenBrainzToken: listenBrainzAuth.userToken)
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
                AppReviewManager.shared.recordSuccessfulScrobble()
            }
        }
    }

    /// Imports plays from Apple Music listening history (when supported) and flushes the backlog if signed in.
    @discardableResult
    func runUserInitiatedListeningHistoryScan(
        maxItems: Int = 200,
        allowExtendedLookback: Bool = false,
        allowSubmissionWhilePaused: Bool = false,
        bypassRecentTrackCooldown: Bool = false
    ) async -> ListeningHistoryScanResult {
        let shouldPrimeForegroundScan = !engine.isUserPaused
        if shouldPrimeForegroundScan {
            await primeForegroundListeningHistoryScanIfNeeded()
        }

        return await performListeningHistoryScan(
            maxItems: maxItems,
            allowExtendedLookback: allowExtendedLookback,
            allowSubmissionWhilePaused: allowSubmissionWhilePaused,
            bypassRecentTrackCooldown: bypassRecentTrackCooldown,
            deliveryMode: AppSettings.listeningHistoryRequireConfirmationEnabled() ? .queueForConfirmation : .autoSubmit,
            retryEmptyPlaybackHistoryImportOnce: true,
            beforePlaybackHistoryRetry: shouldPrimeForegroundScan ? { [weak self] in
                await self?.primeForegroundListeningHistoryScanIfNeeded()
            } : nil
        )
    }

    /// Imports plays from Apple Music listening history (when supported) and flushes the backlog if signed in.
    @discardableResult
    func scanListeningHistory(
        maxItems: Int = 200,
        allowExtendedLookback: Bool = false,
        allowSubmissionWhilePaused: Bool = false,
        bypassRecentTrackCooldown: Bool = false
    ) async -> ListeningHistoryScanResult {
        await performListeningHistoryScan(
            maxItems: maxItems,
            allowExtendedLookback: allowExtendedLookback,
            allowSubmissionWhilePaused: allowSubmissionWhilePaused,
            bypassRecentTrackCooldown: bypassRecentTrackCooldown,
            retryEmptyPlaybackHistoryImportOnce: false,
            beforePlaybackHistoryRetry: nil
        )
    }

    private func performListeningHistoryScan(
        maxItems: Int,
        allowExtendedLookback: Bool,
        allowSubmissionWhilePaused: Bool,
        bypassRecentTrackCooldown: Bool,
        deliveryMode: ListeningHistoryScanService.DeliveryMode = .autoSubmit,
        retryEmptyPlaybackHistoryImportOnce: Bool,
        beforePlaybackHistoryRetry: (() async -> Void)?
    ) async -> ListeningHistoryScanResult {
        await ListeningHistoryScanService.scan(
            backlog: backlog,
            scrobbleLog: scrobbleLog,
            sessionKey: auth.sessionKey,
            listenBrainzToken: listenBrainzAuth.userToken,
            maxItems: maxItems,
            allowExtendedLookback: allowExtendedLookback,
            bypassRecentTrackCooldown: bypassRecentTrackCooldown,
            recoveryCutoffDate: AppSettings.listeningHistoryResumeRecoveryCutoffDate(),
            isUserPaused: engine.isUserPaused,
            pauseBehavior: allowSubmissionWhilePaused ? .allowSubmissionWhilePaused : .respectPause,
            deliveryMode: deliveryMode,
            retryEmptyPlaybackHistoryImportOnce: retryEmptyPlaybackHistoryImportOnce,
            beforePlaybackHistoryRetry: beforePlaybackHistoryRetry
        ) {
            AppReviewManager.shared.recordSuccessfulScrobble()
        }
    }

    private func primeForegroundListeningHistoryScanIfNeeded() async {
        guard !engine.isUserPaused else { return }

        // Build the active playback session before any foreground recovery import runs so
        // the recent-tracks importer can suppress the current live play.
        observer.refreshOnceIfAuthorized()
        engine.start()
        await engine.tickAsync()
    }

    func handleListeningHistoryRequireConfirmationChanged(isEnabled: Bool) async {
        guard !isEnabled else { return }
        await submitPendingListeningHistoryReviewItems()
        _ = await runUserInitiatedListeningHistoryScan(allowExtendedLookback: true)
    }

    func handleAppleMusicAPIScrobblingChanged(isEnabled: Bool) async {
        guard !isEnabled else { return }
        await backlog.removeAll(origin: .recentlyPlayed)
        AppleMusicRecentTracksImporter.shared.resetState()
    }

    func periodicFlush() async {
        guard auth.sessionKey != nil || listenBrainzAuth.isConnected else { return }
        await flushBacklogIfNeeded()
    }

    @discardableResult
    func submitPendingListeningHistoryReviewItems(ids: Set<UUID>? = nil) async -> Int {
        guard auth.sessionKey != nil || listenBrainzAuth.isConnected else { return 0 }

        let pendingEntries: [ListeningHistoryReviewStore.Entry]
        if let ids, !ids.isEmpty {
            pendingEntries = ListeningHistoryReviewStore.shared.dequeueForSubmission(ids: ids)
        } else {
            pendingEntries = ListeningHistoryReviewStore.shared.dequeueAllForSubmission()
        }
        guard !pendingEntries.isEmpty else { return 0 }

        let preventDuplicates = ProSettings.preventDuplicateScrobblesEnabled()
        var enqueuedCount = 0

        for entry in pendingEntries {
            if preventDuplicates, await reviewEntryWouldDuplicateExistingScrobble(entry) {
                continue
            }

            await backlog.enqueue(
                track: entry.track,
                startTimestamp: entry.startTimestamp,
                origin: entry.origin,
                wasAppleMusicFavorite: entry.wasAppleMusicFavorite,
                allowExactDuplicates: !preventDuplicates
            )
            enqueuedCount += 1
        }

        if enqueuedCount > 0 {
            await flushBacklogIfNeeded(force: true)
        }

        return enqueuedCount
    }

    func runStorageMaintenanceNow() async {
        await backlog.cleanupNow()
        scrobbleLog.cleanupNow()
        PlaybackHistoryImporter.shared.prunePersistedStateNow()
        AppleMusicRecentTracksImporter.shared.prunePersistedStateNow()
    }

    func collectStorageUsageSnapshot() async -> StorageUsageSnapshot {
        StorageUsageSnapshot(
            backlogCount: await backlog.pendingCount(),
            backlogBytes: await backlog.storageSizeBytes(),
            scrobbleLogCount: scrobbleLog.entries.count,
            scrobbleLogBytes: scrobbleLog.storageSizeBytes(),
            playbackHistoryStateBytes: PlaybackHistoryImporter.shared.storageSizeBytes(),
            recentTracksStateBytes: AppleMusicRecentTracksImporter.shared.storageSizeBytes()
        )
    }

    @discardableResult
    func flushBacklogIfNeeded(sessionKey: String? = nil, force: Bool = false) async -> ScrobbleBacklog.FlushResult {
        guard !engine.isUserPaused else {
            let pending = await backlog.pendingCount()
            return ScrobbleBacklog.FlushResult(
                sentCount: 0,
                skippedCount: 0,
                remainingCount: pending,
                sentItems: []
            )
        }

        let pending = await backlog.pendingCount()
        guard pending > 0 else {
            return ScrobbleBacklog.FlushResult(sentCount: 0, skippedCount: 0, remainingCount: 0, sentItems: [])
        }

        let now = Date()
        if !force {
            let lastFlush = UserDefaults.standard.object(forKey: Keys.lastBacklogFlushAt) as? Date
            if let lastFlush, now.timeIntervalSince(lastFlush) < 60 {
                return ScrobbleBacklog.FlushResult(
                    sentCount: 0,
                    skippedCount: 0,
                    remainingCount: pending,
                    sentItems: []
                )
            }
        }

        UserDefaults.standard.set(now, forKey: Keys.lastBacklogFlushAt)

        let sk = sessionKey ?? auth.sessionKey
        let lbt = listenBrainzAuth.userToken
        let result = await backlog.flush(sessionKey: sk, listenBrainzToken: lbt)
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
            AppReviewManager.shared.recordSuccessfulScrobble()
        }
        return result
    }

    private func runStorageMaintenanceIfNeeded() async {
        let currentMigrationVersion = 1
        let storedVersion = AppGroup.userDefaults.integer(forKey: Keys.storageMigrationVersion)
        guard storedVersion < currentMigrationVersion else { return }
        await runStorageMaintenanceNow()
        AppGroup.userDefaults.set(currentMigrationVersion, forKey: Keys.storageMigrationVersion)
    }

    private func scrobbleLogSource(for origin: ScrobbleBacklog.Origin?) -> ScrobbleLogStore.Source {
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

    private func reviewEntryWouldDuplicateExistingScrobble(_ entry: ListeningHistoryReviewStore.Entry) async -> Bool {
        let weakStartToleranceSeconds: Int
        switch entry.origin {
        case .recentlyPlayed:
            let durationSeconds = entry.track.durationSeconds.map { max(0, Int($0.rounded(.up))) } ?? 0
            weakStartToleranceSeconds = max(6 * 60, durationSeconds + 4 * 60)
        case .live, .manual, .playbackHistory:
            weakStartToleranceSeconds = 0
        }

        let backlogDuplicateLevel = await backlog.recoveryDuplicateMatch(
            track: entry.track,
            startTimestamp: entry.startTimestamp,
            playedAt: entry.playedAt,
            exactStartToleranceSeconds: RecoveryDuplicateMatcher.balancedExactStartToleranceSeconds,
            playedAtToleranceSeconds: RecoveryDuplicateMatcher.balancedPlayedAtToleranceSeconds,
            weakStartToleranceSeconds: weakStartToleranceSeconds
        )?.level ?? .none

        let logDuplicateLevel = scrobbleLog.recoveryDuplicateMatch(
            track: entry.track,
            startTimestamp: entry.startTimestamp,
            playedAt: entry.playedAt,
            exactStartToleranceSeconds: RecoveryDuplicateMatcher.balancedExactStartToleranceSeconds,
            playedAtToleranceSeconds: RecoveryDuplicateMatcher.balancedPlayedAtToleranceSeconds,
            weakStartToleranceSeconds: weakStartToleranceSeconds
        )?.level ?? .none

        return max(backlogDuplicateLevel, logDuplicateLevel) == .strongDuplicate
    }
}

@MainActor
final class AppReviewManager {
    static let shared = AppReviewManager()

    private enum Keys {
        static let firstLaunchAt = "FastScrobbler.Review.firstLaunchAt"
        static let lastCountedSessionAt = "FastScrobbler.Review.lastCountedSessionAt"
        static let engagedSessionCount = "FastScrobbler.Review.engagedSessionCount"
        static let successfulScrobbleCount = "FastScrobbler.Review.successfulScrobbleCount"
        static let lastPromptedVersion = "FastScrobbler.Review.lastPromptedVersion"
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    private let defaults = UserDefaults.standard
    private let minimumDaysSinceFirstLaunch: TimeInterval = 7 * 24 * 60 * 60
    private let minimumSessionSpacing: TimeInterval = 4 * 60 * 60
    private let minimumEngagedSessions = 4
    private let minimumSuccessfulScrobbles = 10

    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6759501541?action=write-review")!

    private init() {
        if defaults.object(forKey: Keys.firstLaunchAt) == nil {
            defaults.set(Date(), forKey: Keys.firstLaunchAt)
        }
    }

    #if canImport(UIKit)
    func recordAppDidBecomeActive(in windowScene: UIWindowScene) {
        if defaults.object(forKey: Keys.firstLaunchAt) == nil {
            defaults.set(Date(), forKey: Keys.firstLaunchAt)
        }

        guard defaults.bool(forKey: Keys.hasSeenSetup) else { return }

        let now = Date()
        if let lastCountedSessionAt = defaults.object(forKey: Keys.lastCountedSessionAt) as? Date {
            if now.timeIntervalSince(lastCountedSessionAt) >= minimumSessionSpacing {
                defaults.set(now, forKey: Keys.lastCountedSessionAt)
                defaults.set(defaults.integer(forKey: Keys.engagedSessionCount) + 1, forKey: Keys.engagedSessionCount)
            }
        } else {
            defaults.set(now, forKey: Keys.lastCountedSessionAt)
            defaults.set(1, forKey: Keys.engagedSessionCount)
        }

        requestReviewIfEligible(in: windowScene, now: now)
    }
    #endif

    func recordSuccessfulScrobble() {
        defaults.set(defaults.integer(forKey: Keys.successfulScrobbleCount) + 1, forKey: Keys.successfulScrobbleCount)
    }

    #if canImport(UIKit)
    private func requestReviewIfEligible(in windowScene: UIWindowScene, now: Date) {
        guard let firstLaunchAt = defaults.object(forKey: Keys.firstLaunchAt) as? Date else { return }
        guard now.timeIntervalSince(firstLaunchAt) >= minimumDaysSinceFirstLaunch else { return }
        guard defaults.integer(forKey: Keys.engagedSessionCount) >= minimumEngagedSessions else { return }
        guard defaults.integer(forKey: Keys.successfulScrobbleCount) >= minimumSuccessfulScrobbles else { return }

        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let currentVersion, !currentVersion.isEmpty else { return }
        guard defaults.string(forKey: Keys.lastPromptedVersion) != currentVersion else { return }

        defaults.set(currentVersion, forKey: Keys.lastPromptedVersion)
        SKStoreReviewController.requestReview(in: windowScene)
    }
    #endif
}
