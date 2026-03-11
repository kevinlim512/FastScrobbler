import Foundation

@MainActor
final class AppModel {
    static let shared = AppModel()

    private enum Keys {
        static let lastBacklogFlushAt = "FastScrobbler.AppModel.lastBacklogFlushAt"
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
        static let lastEnteredBackgroundAt = "FastScrobbler.AppModel.lastEnteredBackgroundAt"
    }

    let auth: LastFMAuthManager
    let observer: AppleMusicNowPlayingObserver
    let engine: ScrobbleEngine
    let backlog: ScrobbleBacklog
    let scrobbleLog: ScrobbleLogStore

    private init() {
        let auth = LastFMAuthManager()
        let observer = AppleMusicNowPlayingObserver()
        self.auth = auth
        self.observer = observer
        let backlog = ScrobbleBacklog.shared
        self.backlog = backlog
        let scrobbleLog = ScrobbleLogStore.shared
        self.scrobbleLog = scrobbleLog
        self.engine = ScrobbleEngine(auth: auth, observer: observer, backlog: backlog, scrobbleLog: scrobbleLog)
    }

    func startIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

#if os(iOS)
        if #available(iOS 16.2, *) {
            await LiveActivityManager.shared.handleAppBecameActive()
            LiveActivityManager.shared.startIfPossible()
        }
#endif
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

        if auth.sessionKey == nil {
            await LiveActivityManager.shared.update(
                status: "Connect Last.fm to scrobble.",
                track: observer.track,
                lastEventAt: Date(),
                isActivelyScrobbling: false,
                throttleSeconds: 0
            )
            return
        }

        if let sessionKey = auth.sessionKey {
            await auth.refreshUserInfoIfNeeded()
            let imported = await PlaybackHistoryImporter.shared.importIntoBacklog(
                backlog: backlog,
                scrobbleLog: scrobbleLog,
                maxItems: 200
            )
            UserDefaults.standard.removeObject(forKey: Keys.lastEnteredBackgroundAt)
            await flushBacklogIfNeeded(sessionKey: sessionKey, force: imported > 0)
            BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        }

        // Foreground transitions can leave Timers paused or invalidated.
        engine.start()

        // Ensure the app immediately re-sync state on foreground transitions (Timers pause while backgrounded).
        await engine.tickAsync()
    }

    func prepareForBackground() {
        // In normal (non-debugger) conditions, iOS will suspend the app quickly.
        // Stop timers/observers so behavior is consistent and energy-friendly.
        let backgroundedAt = Date()
        UserDefaults.standard.set(backgroundedAt, forKey: Keys.lastEnteredBackgroundAt)
        LiveActivityManager.shared.recordEnteredBackground(at: backgroundedAt)
#if os(iOS)
        Task { @MainActor in
            if #available(iOS 16.2, *) {
                await LiveActivityManager.shared.scheduleDismissalAfterAppClosed(backgroundedAt: backgroundedAt)
            }
        }
#endif
        observer.stop()
        engine.pauseForBackground()
    }

    func backgroundTick() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

        observer.refreshOnceIfAuthorized()
        let imported = await PlaybackHistoryImporter.shared.importIntoBacklog(backlog: backlog, scrobbleLog: scrobbleLog)
        if let sessionKey = auth.sessionKey {
            let result = await backlog.flush(sessionKey: sessionKey)
            for item in result.sentItems {
                scrobbleLog.record(
                    track: item.track,
                    startTimestamp: item.startTimestamp,
                    scrobbledAt: item.scrobbledAt,
                    source: scrobbleLogSource(for: item.origin),
                    lovedOnLastFM: item.lovedOnLastFM
                )
            }
            if result.remainingCount > 0 || imported > 0 {
                BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
            }
        } else if imported > 0 {
            BackgroundTaskManager.shared.scheduleAppRefresh()
        }
        await engine.tickAsync()
    }

    /// Imports plays from Apple Music listening history (when supported) and flushes the backlog if signed in.
    @discardableResult
    func scanListeningHistory(maxItems: Int = 200) async -> Int {
        let imported = await PlaybackHistoryImporter.shared.importIntoBacklog(
            backlog: backlog,
            scrobbleLog: scrobbleLog,
            maxItems: maxItems
        )

        guard let sessionKey = auth.sessionKey else { return imported }
        await flushBacklogIfNeeded(sessionKey: sessionKey, force: true)
        return imported
    }

    private func flushBacklogIfNeeded(sessionKey: String, force: Bool = false) async {
        let pending = await backlog.pendingCount()
        guard pending > 0 else { return }

        let now = Date()
        if !force {
            let lastFlush = UserDefaults.standard.object(forKey: Keys.lastBacklogFlushAt) as? Date
            if let lastFlush, now.timeIntervalSince(lastFlush) < 60 {
                return
            }
        }

        UserDefaults.standard.set(now, forKey: Keys.lastBacklogFlushAt)

        let result = await backlog.flush(sessionKey: sessionKey)
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

    private func scrobbleLogSource(for origin: ScrobbleBacklog.Origin?) -> ScrobbleLogStore.Source {
        switch origin {
        case .playbackHistory:
            return .playbackHistory
        case .recentlyPlayed:
            return .recentlyPlayed
        case .live, .none:
            return .backlog
        }
    }
}
