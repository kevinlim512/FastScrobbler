import Foundation

func runManualCooldownTests() {
    // ─── 1d: Manual scrobble rate-limit logic ─────────────────────────────────────

    section("1d · Manual scrobble rate limit — 0.5-second cooldown")

    // Simulate the guard condition used in ScrobbleEngine.scrobbleNow:
    //   if let last = lastManualScrobbleAttemptAt, now.timeIntervalSince(last) < 0.5 { return }
    func shouldAllowScrobble(last: Date?, now: Date) -> Bool {
        if let last = last, now.timeIntervalSince(last) < 0.5 { return false }
        return true
    }

    let t0 = Date()
    expect("first tap always allowed (nil last)", shouldAllowScrobble(last: nil, now: t0))
    expect("tap 0.2s after is blocked", !shouldAllowScrobble(last: t0, now: t0.addingTimeInterval(0.2)))
    expect("tap 0.49s after is blocked", !shouldAllowScrobble(last: t0, now: t0.addingTimeInterval(0.49)))
    expect("tap exactly 0.5s after is allowed", shouldAllowScrobble(last: t0, now: t0.addingTimeInterval(0.5)))
    expect("tap 5s after is allowed", shouldAllowScrobble(last: t0, now: t0.addingTimeInterval(5)))
}
