import Foundation

@MainActor
final class AppModel {
    static let shared = AppModel()

    private enum Keys {
        static let lastBacklogFlushAt = "FastScrobbler.AppModel.lastBacklogFlushAt"
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
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

        LiveActivityManager.shared.clearEnteredBackground()
        LiveActivityManager.shared.startIfPossible()
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
            let imported = await PlaybackHistoryImporter.shared.importIntoBacklog(backlog: backlog)
            await flushBacklogIfNeeded(sessionKey: sessionKey, force: imported > 0)
        }

        // Foreground transitions can leave Timers paused or invalidated.
        engine.start()

        // Ensure we immediately re-sync state on foreground transitions (Timers pause while backgrounded).
        await engine.tickAsync()
    }

    func prepareForBackground() {
        // In normal (non-debugger) conditions, iOS will suspend the app quickly.
        // Stop timers/observers so behavior is consistent and energy-friendly.
        LiveActivityManager.shared.recordEnteredBackground()
        observer.stop()
        engine.pauseForBackground()
    }

    func backgroundTick() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) else { return }

        observer.refreshOnceIfAuthorized()
        _ = await PlaybackHistoryImporter.shared.importIntoBacklog(backlog: backlog)
        if let sessionKey = auth.sessionKey {
            let result = await backlog.flush(sessionKey: sessionKey)
            for item in result.sentItems {
                scrobbleLog.record(
                    track: item.track,
                    startTimestamp: item.startTimestamp,
                    scrobbledAt: item.scrobbledAt,
                    source: .backlog
                )
            }
        }
        await engine.tickAsync()
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
                source: .backlog
            )
        }
    }
}
