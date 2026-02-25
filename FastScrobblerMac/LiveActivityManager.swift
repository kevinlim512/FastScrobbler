import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    static let enabledDefaultsKey = "FastScrobbler.LiveActivity.enabled"
    static let backgroundedAtDefaultsKey = "FastScrobbler.LiveActivity.backgroundedAt"

    private init() {}

    func recordEnteredBackground(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.backgroundedAtDefaultsKey)
    }

    func clearEnteredBackground() {
        UserDefaults.standard.removeObject(forKey: Self.backgroundedAtDefaultsKey)
    }

    func startIfPossible() {}

    func stop() async {}

    func update(
        status: String,
        track: Track?,
        lastEventAt: Date,
        isActivelyScrobbling: Bool,
        throttleSeconds: TimeInterval = 0
    ) async {}
}

