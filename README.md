# FastScrobbler

FastScrobbler is a lightweight scrobbler for Apple Music that sends:

- `track.updateNowPlaying` (shows as “currently playing” on Last.fm)
- `track.scrobble` once you’ve listened long enough (threshold is configurable)

It comprises:
- An iOS app (`FastScrobbler/`)
- A macOS menu bar app (`FastScrobblerMac/`)
- iOS extensions (Live Activity + iOS 18 Control Center widgets)

## App Store

**Download on the iOS and macOS App Store:**
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
- **Manual “Scrobble Now”**: scrobble the current track immediately from the app.
- **Pause/Resume scrobbling**: stops all sending while paused.
- **Offline / failure tolerant**: queues scrobbles locally and retries with exponential-ish backoff.
- **Listening History import (iOS)**: scans the device’s Apple Music “Playback History” playlist and imports missed plays (best-effort; this device only).
- **Apple Music favourites → Last.fm love (optional)**: when enabled, favouriting a song in Apple Music can trigger `track.love` after scrobbling.
- **Scrobble metadata controls**:
  - Use **Album Artist** as scrobble artist (when available, except compilation albums).
  - Strip “`- EP`” / “`- Single`” suffixes from album names.
  - **Remove brackets from song titles when scrobbling**: remove all parenthetical / bracketed title segments, or only segments whose contents match configurable keywords (case-insensitive whole-word matching).
- **Live Activity (iOS 16.1+)**: shows scrobbling status on Lock Screen / Dynamic Island.
- **Shortcuts (iOS)**:
  - **Send Now Playing** (updates Last.fm “currently playing”)
  - **Scrobble Song** (immediate scrobble)
- **Control Center buttons (iOS 18+)**: Control Widgets that run the same actions without opening the app.
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
  - App: iOS 16.6+
  - Live Activity extension: iOS 16.1+
  - Control Widgets extensions: iOS 18.0+
- macOS target:
  - Menu bar app: macOS 13.5+

## Permissions / OS prompts

- **iOS**: Media Library / Apple Music permission is used to read now-playing metadata and (optionally) Playback History and favorites status.
- **macOS**: Automation (Apple Events) permission is used to read now-playing metadata from the Music app.

## Build & run (from source)

1. Create a Last.fm API app and copy your **API key** + **shared secret**.
2. Create your local secrets file:
   - Copy `FastScrobbler/LastFMSecrets_Template.swift` → `FastScrobbler/LastFMSecrets.swift`
   - Fill in `LastFMSecrets.apiKey` and `LastFMSecrets.apiSecret`
   - Keep it uncommitted (it’s in `.gitignore`)
3. Open `FastScrobbler.xcodeproj` and set your signing team / bundle identifiers.
4. App Group + Keychain access groups (recommended for extensions):
   - All targets are configured to use an App Group (`group.com.kevin.FastScrobbler`) and a Keychain access group via entitlements (`*.entitlements`).
   - If you change bundle IDs / team, make sure:
     - The App Group identifier exists in your developer account and matches the entitlements.
     - The Keychain access group matches your Team ID.
   - This repo’s `FastScrobbler/LastFM/KeychainStore.swift` includes a hard-coded access group string; you’ll likely need to update it for your Team ID if you want app+extensions Keychain sharing.
     - Alternative: replace it with `FastScrobbler/LastFM/KeychainStore_template.swift` and provide the access group via Info.plist.

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

- Background scrobbling is **best-effort**. iOS can suspend apps aggressively; FastScrobbler uses `BGAppRefreshTask` / `BGProcessingTask`, but always-on behavior is not guaranteed.
- Scrobbling requires a track duration. If Apple Music doesn’t provide a duration, FastScrobbler can still send **Now Playing**, but may not auto-scrobble.
- Listening History import uses the device’s “Playback History” playlist; it’s best-effort and intentionally avoids importing plays synced from other devices.
- Live Activities, Shortcuts, and Control Center widgets may update with a delay (iOS can throttle background/intent execution).

## Troubleshooting

- **No track detected (iOS)**: make sure Apple Music is playing and Media Library permission is granted.
- **No scrobbles while locked/backgrounded (iOS)**: keep the app open occasionally; ensure Background App Refresh is enabled.
- **Issue scrobbling looped songs**: ensure that "Prevent duplicate scrobbles" is turned off in the app's settings 
- **macOS shows “permission” errors**: enable Automation permission for Music in System Settings.
- **Auth callback issues**: `LastFMSecrets.callbackScheme` must match `CFBundleURLTypes` in `FastScrobbler/Info.plist`.

## Privacy

- FastScrobbler has no developer-run backend.
- Network traffic goes directly from your device to Last.fm (`ws.audioscrobbler.com`) after you connect your account.
- More details: `PRIVACY_POLICY.md`.

## Project layout

- iOS app: `FastScrobbler/`
- macOS app: `FastScrobblerMac/`
- Live Activity widget extension: `FastScrobblerLiveActivity/`
- iOS 18 Control Center widgets: `FastScrobblerNowPlayingControl/`, `FastScrobblerScrobbleControl/`

## Pro upgrade (In‑App Purchase)

- The app expects a **non-consumable** IAP with product ID `com.kevin.FastScrobbler.pro` (see `FastScrobbler/Models/Track.swift` and `FastScrobbler/Pro.swift`).
- **Don’t set price in code.** Pricing is configured in **App Store Connect** for the IAP product.

## License

You may view and modify the code for personal use. Redistribution or publishing this software or derivatives on the Apple App Store or any commercial marketplace is prohibited without explicit permission.
