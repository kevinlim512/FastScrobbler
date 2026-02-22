import ActivityKit
import Foundation
import OSLog

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    static let enabledDefaultsKey = "FastScrobbler.LiveActivity.enabled"
    static let backgroundedAtDefaultsKey = "FastScrobbler.LiveActivity.backgroundedAt"
    static let maxBackgroundSeconds: TimeInterval = 45 * 60

    private let logger = Logger(subsystem: "FastScrobbler", category: "LiveActivity")
    private var activity: Activity<ScrobblingActivityAttributes>?
    private var lastUpdateAt: Date?

    private init() {}

    func recordEnteredBackground(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.backgroundedAtDefaultsKey)
    }

    func clearEnteredBackground() {
        UserDefaults.standard.removeObject(forKey: Self.backgroundedAtDefaultsKey)
    }

    private var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    private func lastEventAt(for activity: Activity<ScrobblingActivityAttributes>) -> Date {
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
        if let mostRecent = existing.max(by: { a, b in
            lastEventAt(for: a) < lastEventAt(for: b)
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
                content: ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 60 * 30)),
                pushType: nil
            )
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

        if activity == nil {
            startIfPossible()
        }
        guard let activity else { return }

        if let lastUpdateAt, now.timeIntervalSince(lastUpdateAt) < throttleSeconds { return }
        self.lastUpdateAt = now

        let state = ScrobblingActivityAttributes.ContentState(
            status: status,
            artist: track?.artist,
            title: track?.title,
            lastEventAt: lastEventAt,
            isActivelyScrobbling: isActivelyScrobbling
        )

        await activity.update(ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 60 * 30)))
    }

    @discardableResult
    private func endAllActivitiesIfBackgroundedTooLong(now: Date = Date()) async -> Bool {
        guard let backgroundedAt = UserDefaults.standard.object(forKey: Self.backgroundedAtDefaultsKey) as? Date else {
            return false
        }
        guard now.timeIntervalSince(backgroundedAt) >= Self.maxBackgroundSeconds else {
            return false
        }

        logger.debug("app backgrounded >= 45 minutes; ending all Live Activities")
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
