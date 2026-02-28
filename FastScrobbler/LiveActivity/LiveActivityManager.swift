import ActivityKit
import Foundation
import OSLog

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    static let enabledDefaultsKey = "FastScrobbler.LiveActivity.enabled"
    static let backgroundedAtDefaultsKey = "FastScrobbler.LiveActivity.backgroundedAt"
    static let maxBackgroundSeconds: TimeInterval = 30 * 60

    private let logger = Logger(subsystem: "FastScrobbler", category: "LiveActivity")
    private var activity: Activity<ScrobblingActivityAttributes>?
    private var lastUpdateAt: Date?

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

        let dismissalAt = backgroundedAt.addingTimeInterval(Self.maxBackgroundSeconds)
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

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    private func contentLastEventAt(for activity: Activity<ScrobblingActivityAttributes>) -> Date {
        activity.content.state.lastEventAt
    }

    func startIfPossible() {
        guard isEnabled else {
            Task { @MainActor in
                await self.stop()
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let existing = Activity<ScrobblingActivityAttributes>.activities
        let activeExisting = existing.filter { $0.activityState == .active }
        let shouldCleanUpExistingAfterRequest = !existing.isEmpty && activeExisting.isEmpty
        if let mostRecent = activeExisting.max(by: { a, b in
            contentLastEventAt(for: a) < contentLastEventAt(for: b)
        }) {
            activity = mostRecent
            Task { @MainActor in
                await self.endAllActivities(except: mostRecent.id)
            }
            return
        }

        let attrs = ScrobblingActivityAttributes()
        let state = ScrobblingActivityAttributes.ContentState(
            status: "Starting…",
            artist: nil,
            title: nil,
            lastEventAt: Date(),
            isActivelyScrobbling: true
        )

        do {
            activity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: Self.maxBackgroundSeconds)),
                pushType: nil
            )
            if shouldCleanUpExistingAfterRequest, let activity {
                Task { @MainActor in
                    await self.endAllActivities(except: activity.id)
                }
            }
        } catch {
            logger.warning("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            activity = nil
        }
    }

    func stop() async {
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
        guard isEnabled else {
            await stop()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await stop()
            return
        }

        let now = Date()
        if await endAllActivitiesIfBackgroundedTooLong(now: now) { return }

        if let lastUpdateAt, now.timeIntervalSince(lastUpdateAt) < throttleSeconds { return }
        self.lastUpdateAt = now

        let state = ScrobblingActivityAttributes.ContentState(
            status: status,
            artist: track?.artist,
            title: track?.title,
            lastEventAt: lastEventAt,
            isActivelyScrobbling: isActivelyScrobbling
        )

        if let backgroundedAt = UserDefaults.standard.object(forKey: Self.backgroundedAtDefaultsKey) as? Date {
            // When the app is no longer open, mark the Live Activity content as stale after 30 minutes.
            // Avoid `end()` here: ended activities can disappear from Dynamic Island immediately.
            let dismissalAt = backgroundedAt.addingTimeInterval(Self.maxBackgroundSeconds)

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
            startIfPossible()
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
