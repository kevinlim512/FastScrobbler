import Foundation

@MainActor
final class PermissionStatusStore: ObservableObject {
    @Published private(set) var mediaLibraryStatus: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var automationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined

    private var monitoringTask: Task<Void, Never>?

    func startMonitoring(observer: AppleMusicNowPlayingObserver) {
        monitoringTask?.cancel()
        monitoringTask = Task { @MainActor in
            await refreshNow(observer: observer)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                await refreshNow(observer: observer)
            }
        }
    }

    func refreshNow(observer: AppleMusicNowPlayingObserver) async {
        mediaLibraryStatus = MPMediaLibrary.authorizationStatus()
        automationStatus = await observer.refreshAuthorizationStatus()
    }
}

@MainActor
final class AppModel {
    static let shared = AppModel()

    private enum Keys {
        static let lastBacklogFlushAt = "FastScrobbler.AppModel.lastBacklogFlushAt"
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
        static let lastEnteredBackgroundAt = "FastScrobbler.AppModel.lastEnteredBackgroundAt"
        static let storageMigrationVersion = "FastScrobbler.StorageMaintenance.migrationVersion"
    }

    let auth: LastFMAuthManager
    let listenBrainzAuth: ListenBrainzAuthManager
    let observer: AppleMusicNowPlayingObserver
    let engine: ScrobbleEngine
    let backlog: ScrobbleBacklog
    let scrobbleLog: ScrobbleLogStore
    let permissions: PermissionStatusStore

    private var startTask: Task<Void, Never>?

    private init() {
        let auth = LastFMAuthManager()
        let listenBrainzAuth = ListenBrainzAuthManager()
        let observer = AppleMusicNowPlayingObserver()
        self.auth = auth
        self.listenBrainzAuth = listenBrainzAuth
        self.observer = observer
        let permissions = PermissionStatusStore()
        self.permissions = permissions
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
        startTask?.cancel()
        startTask = Task { @MainActor in
            await self.performStart()
        }
    }

    private func performStart() async {
        await runStorageMaintenanceIfNeeded()
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

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
            UserDefaults.standard.removeObject(forKey: Keys.lastEnteredBackgroundAt)
            await flushBacklogIfNeeded()
            BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        }

        // Foreground transitions can leave Timers paused or invalidated.
        engine.start()

        // Ensure the app immediately re-sync state on foreground transitions (Timers pause while backgrounded).
        await engine.tickAsync()
    }

    func prepareForBackground() {
        let backgroundedAt = Date()
        UserDefaults.standard.set(backgroundedAt, forKey: Keys.lastEnteredBackgroundAt)
        LiveActivityManager.shared.recordEnteredBackground(at: backgroundedAt)
        observer.stop()
        engine.pauseForBackground()
    }

    func backgroundTick() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

        observer.refreshOnceIfAuthorized()
        if auth.sessionKey != nil || listenBrainzAuth.isConnected {
            let result = await backlog.flush(sessionKey: auth.sessionKey, listenBrainzToken: listenBrainzAuth.userToken)
            for item in result.sentItems {
                scrobbleLog.record(
                    track: item.track,
                    startTimestamp: item.startTimestamp,
                    scrobbledAt: item.scrobbledAt,
                    source: scrobbleLogSource(for: item.origin),
                    lovedOnLastFM: item.lovedOnLastFM
                )
            }
        }
        await engine.tickAsync()
    }

    func periodicFlush() async {
        guard auth.sessionKey != nil || listenBrainzAuth.isConnected else { return }
        await flushBacklogIfNeeded()
    }

    func runStorageMaintenanceNow() async {
        await backlog.cleanupNow()
        scrobbleLog.cleanupNow()
    }

    func collectStorageUsageSnapshot() async -> StorageUsageSnapshot {
        StorageUsageSnapshot(
            backlogCount: await backlog.pendingCount(),
            backlogBytes: await backlog.storageSizeBytes(),
            scrobbleLogCount: scrobbleLog.entries.count,
            scrobbleLogBytes: scrobbleLog.storageSizeBytes(),
            playbackHistoryStateBytes: 0,
            recentTracksStateBytes: 0
        )
    }

    @discardableResult
    private func flushBacklogIfNeeded(sessionKey: String? = nil, force: Bool = false) async -> ScrobbleBacklog.FlushResult {
        let pending = await backlog.pendingCount()
        guard pending > 0 else {
            return ScrobbleBacklog.FlushResult(sentCount: 0, skippedCount: 0, remainingCount: pending, sentItems: [])
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
        for item in result.sentItems {
            scrobbleLog.record(
                track: item.track,
                startTimestamp: item.startTimestamp,
                scrobbledAt: item.scrobbledAt,
                source: scrobbleLogSource(for: item.origin),
                lovedOnLastFM: item.lovedOnLastFM
            )
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
}
