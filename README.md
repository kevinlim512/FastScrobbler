# FastScrobbler

FastScrobbler is a lightweight scrobbler for Apple Music that sends:

- `track.updateNowPlaying` (shows as "currently playing" on Last.fm)
- `track.scrobble` once you’ve listened long enough (threshold is configurable)
- recovery scrobbles for missed plays, including Apple Music recent tracks from all your devices when available

It comprises:
- An iOS app (`FastScrobbler/`)
- A macOS menu bar app (`FastScrobblerMac/`)
- iOS extensions (Live Activity + iOS 18 Control Center widgets)

## App Store

**Download on the App Store for iOS and macOS:**
https://apps.apple.com/sg/app/fastscrobbler-for-last-fm/id6759501541

## iOS Screenshots

<p align="center">
  <img src="Screenshots/iPhone 1.PNG" width="180" alt="FastScrobbler main screen" />
  <img src="Screenshots/iPhone 2.PNG" width="180" alt="FastScrobbler settings screen" />
  <img src="Screenshots/iPhone 3.PNG" width="180" alt="FastScrobbler setup screen" />
</p>

## Mac Screenshots

<p align="center">
  <img src="Screenshots/Mac 1.png" height="240" alt="FastScrobbler main screen" />
  <img src="Screenshots/Mac 2.png" height="240" alt="FastScrobbler settings screen" />
  <img src="Screenshots/Mac 3.png" height="240" alt="FastScrobbler setup screen" />
</p>

## Features

- **Now Playing → Last.fm**: sends now playing as soon as playback is detected.
- **Auto-scrobble with threshold**: scrobbles after 10% / 25% / 50% / 75% of track duration (default 50%).
- **Manual "Scrobble Now"**: scrobble the current track immediately from the app.
- **Manual Scrobble**: submit a scrobble for any track by entering artist, song, album, and an optional custom timestamp (up to two weeks in the past). Includes a log of the last 30 manual scrobbles.
- **Scrobble Again from the log**: re-submit a previous scrobble directly from the scrobble log.
- **Pause/Resume scrobbling**: stops all sending while paused.
- **Offline / failure tolerant**: queues scrobbles locally and retries with exponential-ish backoff.
- **Duplicate protection**: avoids sending the same playback session to Last.fm more than once within a short time window.
- **Listening History import (iOS)**: uses the Apple Music app's Listening History functionality as a recovery backlog for plays missed while the app was suspended.
- **Apple Music API recovery import (iOS, experimental)**: can import up to 30 recently played Apple Music tracks, including non-library tracks. This is the path that lets FastScrobbler recover and scrobble plays from all your devices signed into the same Apple Music account. Apple does not provide exact playback timestamps here, so FastScrobbler estimates them when submitting.
- **Manual History Scan (iOS)**: run an on-demand scan for missed plays. Extended scans can check the past 7 days instead of the default 36 hours.
- **Apple Music favourites → Last.fm love (optional)**: when enabled, favouriting a song in Apple Music can trigger `track.love` after scrobbling.
- **Scrobble metadata controls**:
  - Use **Album Artist** as scrobble artist (when available, except compilation albums).
  - **Scrobble only the first credited artist** when a track has multiple credited artists.
  - **Remove brackets from song and album titles when scrobbling**: remove all parenthetical / bracketed title segments, or only segments whose contents match configurable keywords (case-insensitive whole-word matching).
  - **Text Replacement**: define find-and-replace rules applied to artist, song, and/or album fields before scrobbling. Rules support exact text matching and can be scoped to specific fields. Built-in rules for stripping `- Single` / `- EP` are included.
- **Live Activity (iOS 16.1+)**: shows scrobbling status on Lock Screen / Dynamic Island.
- **Shortcuts (iOS)**:
  - **Send Now Playing** (updates Last.fm "currently playing")
  - **Scrobble Song** (immediate scrobble)
  - **Manual Scrobble** (opens the Manual Scrobble screen)
  - **Scan History** (checks for missed plays to scrobble)
- **Control Center buttons (iOS 18+)**: Control Widgets for **Send Now Playing**, **Scrobble Song**, **Manual Scrobble**, and **Scan History**.
- **Theme support (iOS)**: System / Light / Dark appearance selection.
- **macOS menu bar UI**: no dock icon/windows; click the menu bar icon to open the popover UI.
- **Start at login (macOS)**: optional toggle in Settings.

## Language Support

FastScrobbler currently supports:

- English
- Chinese (Simplified)
- French
- Japanese
- Spanish

These localisations are included across the iOS app, macOS app, and Control Center widgets.

## Requirements

- Xcode (recent) and an Apple Developer signing setup
- Recommended: a physical iPhone with the Apple Music app installed
- iOS targets:
  - App: iOS 17.6+
  - Live Activity extension: iOS 16.1+
  - Control Widgets extensions: iOS 18.0+
- macOS target:
  - Menu bar app: macOS 14.6+

## Source availability

This repository does **not** include the full production implementation. In particular, these files are intentionally omitted from the published source:

- `FastScrobbler/Scrobble/ScrobbleEngine.swift`
- `FastScrobbler/NowPlaying/PlaybackHistoryImporter.swift`
- `FastScrobbler/NowPlaying/AppleMusicNowPlayingObserver.swift`
- `FastScrobbler/NowPlaying/AppleMusicRecentTracksImporter.swift`

As a result, the repository is not a complete drop-in build of the App Store app without providing your own replacements for those files.

## Permissions / OS prompts

- **iOS**: Media Library / Apple Music permission is used to read now-playing metadata and (optionally) Listening History and favorites status.
- **macOS**: Automation (Apple Events) permission is used to read now-playing metadata from the Music app.

## Build & run (from source)

1. Create a Last.fm API app and copy your **API key** + **shared secret**.
2. Create your local secrets file:
   - Copy `FastScrobbler/LastFMSecrets_Template.swift` → `FastScrobbler/LastFMSecrets.swift`
   - Fill in `LastFMSecrets.apiKey` and `LastFMSecrets.apiSecret`
   - Keep it uncommitted (it’s in `.gitignore`)
3. Add Firebase config for Crashlytics:
   - Register `com.kevin.FastScrobbler` as an Apple app in Firebase and enable Crashlytics (and Google Analytics if you want breadcrumb logs).
   - Replace the placeholder `GoogleService-Info.plist` at the repo root with the real file downloaded from Firebase.
   - Keep the filename exactly `GoogleService-Info.plist`.
4. Open `FastScrobbler.xcodeproj` and set your signing team / bundle identifiers.
5. App Group (required for extensions):
   - All targets are configured to use an App Group (`group.com.kevin.FastScrobbler`) via entitlements (`*.entitlements`).
   - If you change bundle IDs / team, make sure:
     - The App Group identifier exists in your developer account and matches the entitlements.
   - The Last.fm session key is stored in shared App Group preferences so the app and extensions can access it without Keychain prompts.
6. MusicKit (required for Apple Music API access):
   - Enable the MusicKit service for the iOS and macOS app IDs in Certificates, Identifiers & Profiles.
   - Regenerate/download provisioning profiles after enabling it. Do not add MusicKit token keys manually to `*.entitlements`; Xcode will reject unsupported entitlement keys.

### Run on iOS

- Build/run the `FastScrobbler` scheme on a device.
- First launch checklist:
  - Allow **Media Library** access.
  - Sign in to Last.fm in **Settings**.
  - Start playing music in Apple Music.
- Optional:
  - Enable **Live Activities** in iOS Settings for FastScrobbler.
  - Add the app’s **Shortcuts** actions and (iOS 18+) **Control Center** widgets.

### Run on macOS

- Build/run the `FastScrobblerMac` scheme (menu bar app).
- On first launch, macOS may prompt for permission to control Music. If you deny it, re-enable it in:
  - **System Settings → Privacy & Security → Automation → FastScrobbler → Music**

## iOS constraints / gotchas

- Background scrobbling is **best-effort**. FastScrobbler keeps live scrobbling running for a short period immediately after the app is backgrounded, then falls back to `BGAppRefreshTask` / `BGProcessingTask`. iOS can still suspend the app earlier than requested, so always-on behavior is not guaranteed.
- Scrobbling requires a track duration. If Apple Music doesn’t provide a duration, FastScrobbler can still send **Now Playing**, but may not auto-scrobble.
- Listening History import is a backup path for missed plays and only works for songs added to your library.
- Apple Music API recovery can import recent Apple Music plays from all your devices, but it is experimental, limited to recent tracks Apple exposes, and uses estimated timestamps because Apple does not provide exact playback times.
- Live Activities, Shortcuts, and Control Center widgets may update with a delay (iOS can throttle background/intent execution).

## Troubleshooting

- **No track detected (iOS)**: make sure Apple Music is playing and Media Library permission is granted.
- **No scrobbles while locked/backgrounded (iOS)**: the app can continue live scrobbling for a few minutes after you background it, but longer background time is still best-effort. Ensure Background App Refresh is enabled.
- Looped or restarted tracks are counted automatically; each playback must still reach the scrobble threshold on its own.
- **macOS shows "permission" errors**: enable Automation permission for Music in System Settings.
- **Auth callback issues**: `LastFMSecrets.callbackScheme` must match `CFBundleURLTypes` in `FastScrobbler/Info.plist`.

## Privacy

- FastScrobbler has no developer-run backend.
- The app sends scrobble requests directly to Last.fm (`ws.audioscrobbler.com`) after you connect your account.
- If Crashlytics is configured, the app also sends crash diagnostics and related metadata to Firebase / Google.

### Privacy Policy

For more details, see the [Privacy Policy](https://github.com/kevinlim512/FastScrobbler/blob/main/PRIVACY_POLICY.md).

## Project layout

- iOS app: `FastScrobbler/`
- macOS app: `FastScrobblerMac/`
- Live Activity widget extension: `FastScrobblerLiveActivity/`
- iOS 18 Control Center widgets: `FastScrobblerNowPlayingControl/`, `FastScrobblerScrobbleControl/`, `FastScrobblerManualScrobbleControl/`, `FastScrobblerListeningHistoryControl/`

## Pro upgrade (In‑App Purchase)

- The app expects a **non-consumable** IAP with product ID `com.kevin.FastScrobbler.pro` (see `FastScrobbler/Models/Track.swift` and `FastScrobbler/Pro.swift`).
- **Don’t set price in code.** Pricing is configured in **App Store Connect** for the IAP product.

## Star History

<a href="https://www.star-history.com/?repos=kevinlim512%2FFastScrobbler&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kevinlim512/FastScrobbler&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kevinlim512/FastScrobbler&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=kevinlim512/FastScrobbler&type=date&legend=top-left" />
 </picture>
</a>

## License

You may view and modify the code for personal use. Redistribution or publishing this software or derivatives on the Apple App Store or any commercial marketplace is prohibited without explicit permission.

© 2026 Kevin Lim
