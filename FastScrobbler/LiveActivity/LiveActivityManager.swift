import ActivityKit
import Foundation
import OSLog

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    static let enabledDefaultsKey = "FastScrobbler.LiveActivity.enabled"
    static let compactModeDefaultsKey = "FastScrobbler.LiveActivity.compactModeEnabled"
    static let backgroundedAtDefaultsKey = "FastScrobbler.LiveActivity.backgroundedAt"
    static let maxBackgroundSeconds: TimeInterval = 30 * 60
    static let playbackStoppedDismissalDelay: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: "FastScrobbler", category: "LiveActivity")
    private var activity: Activity<ScrobblingActivityAttributes>?
    private var lastUpdateAt: Date?
    private var playbackStoppedAt: Date?
    private var playbackStoppedTimer: Timer?
    private var lastStatus: String?
    private var lastTrack: Track?
    private var lastEventAtParam: Date?
    private var lastIsActivelyScrobbling: Bool?

    private init() {}

    func handleAppBecameActive(now: Date = Date()) async {
        guard let backgroundedAt = UserDefaults.standard.object(forKey: Self.backgroundedAtDefaultsKey) as? Date else {
            return
        }

        defer { clearEnteredBackground() }

        guard now.timeIntervalSince(backgroundedAt) >= Self.maxBackgroundSeconds else {
            return
        }

        logger.debug("app backgrounded >= 30 minutes; ending all Live Activities")
        await endAllActivities(except: nil)
        activity = nil
    }

    func recordEnteredBackground(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.backgroundedAtDefaultsKey)
    }

    func scheduleDismissalAfterAppClosed(backgroundedAt: Date = Date()) async {
        guard isEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let dismissalAt = max(backgroundedAt.addingTimeInterval(Self.maxBackgroundSeconds), Date().addingTimeInterval(60))
        let activities = Activity<ScrobblingActivityAttributes>.activities.filter { $0.activityState == .active }
        guard !activities.isEmpty else { return }

        for a in activities {
            let content = ActivityContent(state: a.content.state, staleDate: dismissalAt)
            await a.update(content)
        }
    }

    func clearEnteredBackground() {
        UserDefaults.standard.removeObject(forKey: Self.backgroundedAtDefaultsKey)
    }

    var isActive: Bool {
        cleanDeadActivityReference()
        return activity?.activityState == .active
    }

    var isCompactModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.compactModeDefaultsKey)
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    func refreshActiveActivity() {
        guard isEnabled, isActive else { return }
        let status = lastStatus ?? "Starting…"
        let track = lastTrack
        let lastEventAt = lastEventAtParam ?? Date()
        let isActivelyScrobbling = lastIsActivelyScrobbling ?? true
        Task {
            await update(
                status: status,
                track: track,
                lastEventAt: lastEventAt,
                isActivelyScrobbling: isActivelyScrobbling,
                throttleSeconds: 0
            )
        }
    }

    private func cleanDeadActivityReference() {
        if let current = activity, current.activityState != .active {
            activity = nil
        }
    }

    private func contentLastEventAt(for activity: Activity<ScrobblingActivityAttributes>) -> Date {
        activity.content.state.lastEventAt
    }

    func startIfPossible() async {
        guard isEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        cleanDeadActivityReference()
        guard activity == nil else { return }

        let existing = Activity<ScrobblingActivityAttributes>.activities
        let activeExisting = existing.filter { $0.activityState == .active }
        if let mostRecent = activeExisting.max(by: { a, b in
            contentLastEventAt(for: a) < contentLastEventAt(for: b)
        }) {
            activity = mostRecent
            await self.endAllActivities(except: mostRecent.id)
            return
        }

        if !existing.isEmpty {
            await self.endAllActivities(except: nil)
        }

        let attrs = ScrobblingActivityAttributes()
        let state = ScrobblingActivityAttributes.ContentState(
            status: "Starting…",
            artist: nil,
            title: nil,
            lastEventAt: Date(),
            isActivelyScrobbling: true,
            isCompact: isCompactModeEnabled
        )

        do {
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: Self.maxBackgroundSeconds)),
                pushType: nil
            )
        } catch {
            logger.warning("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
        }
    }

    func stop() async {
        playbackStoppedAt = nil
        playbackStoppedTimer?.invalidate()
        playbackStoppedTimer = nil
        await endAllActivities(except: nil)
        self.activity = nil
    }

    func update(
        status: String,
        track: Track?,
        lastEventAt: Date,
        isActivelyScrobbling: Bool,
        throttleSeconds: TimeInterval = 15
    ) async {
        cleanDeadActivityReference()

        guard isEnabled else {
            await stop()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await stop()
            return
        }

        lastStatus = status
        lastTrack = track
        lastEventAtParam = lastEventAt
        lastIsActivelyScrobbling = isActivelyScrobbling

        let now = Date()
        if await endAllActivitiesIfBackgroundedTooLong(now: now) { return }

        if isActivelyScrobbling {
            playbackStoppedAt = nil
            playbackStoppedTimer?.invalidate()
            playbackStoppedTimer = nil
        } else {
            if let stoppedAt = playbackStoppedAt {
                if now.timeIntervalSince(stoppedAt) >= Self.playbackStoppedDismissalDelay {
                    await stop()
                    return
                }
            } else {
                playbackStoppedAt = now
            }

            if playbackStoppedTimer == nil {
                playbackStoppedTimer = Timer.scheduledTimer(
                    withTimeInterval: Self.playbackStoppedDismissalDelay,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in await self?.stop() }
                }
            }
        }

        if let lastUpdateAt, now.timeIntervalSince(lastUpdateAt) < throttleSeconds { return }
        self.lastUpdateAt = now

        let state = ScrobblingActivityAttributes.ContentState(
            status: status,
            artist: track?.artist,
            title: track?.title,
            lastEventAt: lastEventAt,
            isActivelyScrobbling: isActivelyScrobbling,
            isCompact: isCompactModeEnabled
        )

        if let backgroundedAt = UserDefaults.standard.object(forKey: Self.backgroundedAtDefaultsKey) as? Date {
            // When the app is no longer open, mark the Live Activity content as stale after 30 minutes.
            // Avoid `end()` here: ended activities can disappear from Dynamic Island immediately.
            let dismissalAt = max(backgroundedAt.addingTimeInterval(Self.maxBackgroundSeconds), Date().addingTimeInterval(60))

            if activity == nil {
                let activeExisting = Activity<ScrobblingActivityAttributes>.activities.filter { $0.activityState == .active }
                activity = activeExisting.max(by: { a, b in
                    contentLastEventAt(for: a) < contentLastEventAt(for: b)
                })
            }
            guard let activity else { return }

            await activity.update(ActivityContent(state: state, staleDate: dismissalAt))
            return
        }

        if activity == nil {
            await startIfPossible()
        }
        guard let activity else { return }

        await activity.update(ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: Self.maxBackgroundSeconds)))
    }

    @discardableResult
    private func endAllActivitiesIfBackgroundedTooLong(now: Date = Date()) async -> Bool {
        guard let backgroundedAt = UserDefaults.standard.object(forKey: Self.backgroundedAtDefaultsKey) as? Date else {
            return false
        }
        guard now.timeIntervalSince(backgroundedAt) >= Self.maxBackgroundSeconds else {
            return false
        }

        logger.debug("app backgrounded >= 30 minutes; ending all Live Activities")
        await endAllActivities(except: nil)
        activity = nil
        return true
    }

    private func endAllActivities(except keepID: String?) async {
        let activities = Activity<ScrobblingActivityAttributes>.activities
        for a in activities {
            if let keepID, a.id == keepID { continue }
            await a.end(a.content, dismissalPolicy: .immediate)
        }
    }

}
