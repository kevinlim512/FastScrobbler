import Foundation
#if os(iOS)
import StoreKit
import UIKit
#endif

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

        await purgePlaybackHistoryBacklogIfNeeded()

        if auth.sessionKey == nil {
            await LiveActivityManager.shared.update(
                status: NSLocalizedString("Connect Last.fm to scrobble.", comment: ""),
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
        await purgePlaybackHistoryBacklogIfNeeded()
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
#if os(iOS)
                AppReviewManager.shared.recordSuccessfulScrobble()
#endif
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
        guard AppSettings.scrobbleListeningHistoryEnabled() else {
            await purgePlaybackHistoryBacklogIfNeeded()
            return 0
        }

        let imported = await PlaybackHistoryImporter.shared.importIntoBacklog(
            backlog: backlog,
            scrobbleLog: scrobbleLog,
            maxItems: maxItems
        )

        guard let sessionKey = auth.sessionKey else { return imported }
        await flushBacklogIfNeeded(sessionKey: sessionKey, force: true)
        return imported
    }

    func handleListeningHistoryScrobblingChanged(isEnabled: Bool) async {
        guard !isEnabled else { return }
        await backlog.removeAll(origin: .playbackHistory)
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
#if os(iOS)
            AppReviewManager.shared.recordSuccessfulScrobble()
#endif
        }
    }

    private func purgePlaybackHistoryBacklogIfNeeded() async {
        guard !AppSettings.scrobbleListeningHistoryEnabled() else { return }
        await backlog.removeAll(origin: .playbackHistory)
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

#if os(iOS)
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

    func recordSuccessfulScrobble() {
        defaults.set(defaults.integer(forKey: Keys.successfulScrobbleCount) + 1, forKey: Keys.successfulScrobbleCount)
    }

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
}
#endif
