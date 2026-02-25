# FastScrobbler

FastScrobbler is an iOS app (plus a macOS menu bar app) that reads Apple Music (the Music app) now-playing metadata and submits it to Last.fm:

- `track.updateNowPlaying` immediately (shows as “currently playing”)
- `track.scrobble` once enough of the track has played (best-effort; see iOS constraints below)

## Features

- Observes Apple Music now playing via `MPMusicPlayerController.systemMusicPlayer`
- Live Activity (Lock Screen + Dynamic Island) showing scrobbling status (iOS 16.1+)
- Backfills missed plays from Apple Music “Use Listening History” / Playback History (best-effort)
- Shortcuts actions:
  - **Send Now Playing**
  - **Scrobble Song**
- Control Center buttons for the same actions (iOS 18.0+ Control Widgets targets)
- Offline / failure tolerance: scrobbles can be queued and retried later (backlog)

## Requirements

- Xcode (recent version) and an Apple developer signing setup
- A physical iPhone for reliable iOS Music app integration
- iOS:
  - App target: iOS 16.6+
  - Live Activity target: iOS 16.1+
  - Control Center widget targets: iOS 18.0+
- macOS:
  - App target: macOS 13.0+

## Setup

1. Create a Last.fm API account/app and copy the **API key** + **shared secret**.
2. Create your local secrets file:
   - If `FastScrobbler/LastFMSecrets.swift` doesn’t exist, copy `FastScrobbler/LastFMSecrets_Template.swift` to `FastScrobbler/LastFMSecrets.swift`
   - Fill in `apiKey` and `apiSecret` (and avoid committing this file)
3. Keychain access group (optional, for sharing auth between app + extensions):
   - This repo includes `FastScrobbler/LastFM/KeychainStore_template.swift` (safe to commit) which reads `KEYCHAIN_ACCESS_GROUP` from each target’s Info.plist.
   - If you set a shared access group, also add it to each target’s `keychain-access-groups` entitlement.
4. Open `FastScrobbler.xcodeproj` in Xcode and set your signing team / bundle IDs as needed.
5. Choose what to build:
   - iOS: select the `FastScrobbler` scheme and build/run on device.
   - macOS: select the `FastScrobblerMac` scheme and build/run on “My Mac”.

## macOS build notes

- The macOS target (`FastScrobblerMac/`) runs as a **menu bar app** (no Dock icon / no windows).
- CLI build (optional): `xcodebuild -scheme FastScrobblerMac -destination 'platform=macOS' build`
- On first launch, macOS will prompt for permission to control the Music app (Apple Events). If you deny it, re-enable it in **System Settings → Privacy & Security → Automation**.
- Some iOS-only features don’t apply on macOS (e.g. Live Activities, Control Center widgets, Apple Music playback-history backfill).

## Usage

### iOS

1. Open FastScrobbler and grant **Media Library** permission when prompted.
2. Tap **Log In** to connect your Last.fm account (uses `ASWebAuthenticationSession`).
3. Start playing music in Apple Music.
4. Optional:
   - Enable **Live Activities** in iOS Settings for FastScrobbler.
   - Add the app’s **Shortcuts** actions and (on iOS 18+) **Control Center** buttons.

### macOS

1. Run the `FastScrobblerMac` target (a menu bar icon appears).
2. If prompted, allow Automation permission to control the Music app.
3. Tap **Log In** to connect your Last.fm account.
4. Start playing music in the Music app.

## iOS constraints / gotchas

- Background scrobbling is **best-effort**. iOS can suspend apps aggressively; this project uses background task scheduling (`BGAppRefreshTask` / `BGProcessingTask`), but you should not expect always-on behavior.
- When the app resumes, it can backfill missed plays using the local Apple Music “Playback History” playlist (if available).
- Scrobbling requires a track duration. If Apple Music doesn’t provide a duration for an item, FastScrobbler can still send **Now Playing**, but may not scrobble automatically.
- Live Activities don’t always update immediately after running a Shortcut or tapping a Control Center button (iOS can throttle widget/intent execution).

## Privacy & storage notes

- Last.fm session keys are stored in the iOS Keychain.
- Recent scrobbles and the retry backlog are persisted locally (Application Support / App Group container).
- Network requests go to Last.fm’s API (`ws.audioscrobbler.com`).

## Privacy Policy

For App Store submission and a more complete description of data handling, see `PRIVACY_POLICY.md`.

## Troubleshooting

- **“No track detected”**: make sure Apple Music is playing, and Media Library permission is granted for FastScrobbler.
- **No scrobbles while locked/backgrounded**: keep the app opened occasionally; ensure Background App Refresh is enabled; iOS may still delay execution.
- **Auth callback issues**: `LastFMSecrets.callbackScheme` must match `CFBundleURLTypes` in `FastScrobbler/Info.plist`.

## Development notes

- The app target lives in `FastScrobbler/`.
- Extensions:
  - Live Activity widget: `FastScrobblerLiveActivity/`
  - iOS 18 Control Widgets: `FastScrobblerNowPlayingControl/`, `FastScrobblerScrobbleControl/`

## In-App Purchases (Pro)

This project uses StoreKit 2 for a single “Pro” unlock.

- Product id: `com.kevin.FastScrobbler.pro` (see `FastScrobbler/Pro.swift`)

### Test locally (no App Store Connect)

1. In Xcode: **File → New → File… → StoreKit Configuration File**.
2. Add a **Non-Consumable** product with id `com.kevin.FastScrobbler.pro` and a price.
3. Edit scheme: **Product → Scheme → Edit Scheme… → Run → Options → StoreKit Configuration** and select that `.storekit` file.
4. Run the app; the “Buy” button should use the local StoreKit test environment.

### Test “real” purchase flow (Sandbox / TestFlight)

1. In App Store Connect, create the In‑App Purchase (Non‑Consumable) with id `com.kevin.FastScrobbler.pro`.
2. Ensure your Paid Apps / Agreements and Banking/Tax are active (otherwise products won’t load).
3. Add the product to your app version as needed, then upload a build and test via **TestFlight** with a sandbox tester Apple ID.
4. Use the paywall in the app; **Restore Purchases** calls `AppStore.sync()`.
