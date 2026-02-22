# FastScrobbler

FastScrobbler is an iOS app that reads Apple Music (the Music app) now-playing metadata and submits it to Last.fm:

- `track.updateNowPlaying` immediately (shows as “currently playing”)
- `track.scrobble` once enough of the track has played (best-effort; see iOS constraints below)

## Features

- Observes Apple Music now playing via `MPMusicPlayerController.systemMusicPlayer`
- Live Activity (Lock Screen + Dynamic Island) showing scrobbling status (iOS 16.1+)
- Shortcuts actions:
  - **Send Now Playing**
  - **Scrobble Song**
- Control Center buttons for the same actions (iOS 18.0+ Control Widgets targets)
- Offline / failure tolerance: scrobbles can be queued and retried later (backlog)

## Requirements

- Xcode (recent version) and an Apple developer signing setup
- A physical iPhone for reliable Music app integration
- iOS:
  - App target: iOS 16.6+
  - Live Activity target: iOS 16.1+
  - Control Center widget targets: iOS 18.0+

## Setup

1. Create a Last.fm API account/app and copy the **API key** + **shared secret**.
2. Create your local secrets file:
   - If `FastScrobbler/LastFMSecrets.swift` doesn’t exist, copy `FastScrobbler/LastFMSecrets_Template.swift` to `FastScrobbler/LastFMSecrets.swift`
   - Fill in `apiKey` and `apiSecret` (and avoid committing this file)
3. Keychain access group (optional, for sharing auth between app + extensions):
   - This repo includes `FastScrobbler/LastFM/KeychainStore_template.swift` (safe to commit) which reads `KEYCHAIN_ACCESS_GROUP` from each target’s Info.plist.
   - If you set a shared access group, also add it to each target’s `keychain-access-groups` entitlement.
4. Open `FastScrobbler.xcodeproj` in Xcode and set your signing team / bundle IDs as needed.
5. Build and run on device.

## Usage

1. Open FastScrobbler and grant **Media Library** permission when prompted.
2. Tap **Log In** to connect your Last.fm account (uses `ASWebAuthenticationSession`).
3. Start playing music in Apple Music.
4. Optional:
   - Enable **Live Activities** in iOS Settings for FastScrobbler.
   - Add the app’s **Shortcuts** actions and (on iOS 18+) **Control Center** buttons.

## iOS constraints / gotchas

- Background scrobbling is **best-effort**. iOS can suspend apps aggressively; this project uses background task scheduling (`BGAppRefreshTask` / `BGProcessingTask`), but you should not expect always-on behavior.
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
