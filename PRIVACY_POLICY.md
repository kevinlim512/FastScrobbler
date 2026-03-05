# Privacy Policy for FastScrobbler

**Effective date:** February 26, 2026

FastScrobbler is an iOS and macOS app that helps you submit (“scrobble”) your Apple Music / Music app listening activity to your Last.fm account. This policy explains what information the app accesses, stores, and shares.

## Summary

- FastScrobbler does **not** operate any developer-run backend service.
- The app sends track metadata to **Last.fm** only when you explicitly connect your Last.fm account and use the app’s scrobbling features (including Shortcuts / Control Center widgets).
- FastScrobbler does **not** use third-party analytics SDKs and does **not** track you across apps and websites.

## Information the app accesses

### Apple Music / Media Library (on-device)

With your permission, FastScrobbler can access Apple Music (Media Library) information to identify what is playing and (optionally) import recent playback history for scrobbling. This may include:

- Track metadata (artist, title, album)
- Album artist (when available)
- Track duration
- Playback timestamps (e.g., “last played” time)
- Local media identifiers (e.g., persistent IDs)

FastScrobbler uses this information to determine what to submit to Last.fm. Local media identifiers are used only on-device.

### Music app automation (macOS)

On macOS, FastScrobbler reads now-playing metadata from the Music app using Apple Events (Automation). This may include:

- Track metadata (artist, title, album)
- Track duration and playback position

If you deny Automation permission, the macOS app cannot read what’s playing and cannot scrobble.

### Apple Music favorites (optional, on-device)

FastScrobbler can infer whether the current track is favorited in Apple Music (for example via the “Favorite Songs” playlist). If you enable the “Love Apple Music favourites on Last.fm” setting, FastScrobbler may use this on-device favorite status to decide whether to also send a `track.love` request to Last.fm after scrobbling.

### Last.fm account connection

When you connect to Last.fm, FastScrobbler uses Apple’s authentication flow to obtain a Last.fm session key that authorizes scrobbling on your behalf.

## Information the app stores (on your device)

FastScrobbler stores certain data locally to make the app work reliably:

- **Last.fm session key**: stored in Apple Keychain services (iOS/macOS).
- **Last.fm username**: stored locally (UserDefaults) after it is fetched from Last.fm.
- **Retry backlog** (queued scrobbles): stored locally so scrobbles can be retried when the network is available (including timestamps used for scrobbling).
- **Recent scrobble log**: stored locally to show recent activity in the app.
- **App settings**: such as scrobble threshold and metadata preferences, stored locally.
- **Listening history import state (iOS)**: stored locally to avoid re-importing the same plays (may include local media identifiers and play counts).

FastScrobbler does not intentionally store your full music library; it stores only what is needed for queued scrobbles and recent history.

Some data may be stored in an app group container so the iOS app and its extensions (Live Activity / Control Center widgets) can share the same on-device state.

## Information the app shares

### Last.fm

When you use FastScrobbler, the app sends requests to Last.fm’s API. Depending on the feature used, the app may send:

- Artist and track title
- Album (if available)
- Track duration (if available)
- A timestamp representing when playback started / occurred (for scrobbles)

These requests are made directly from your device to Last.fm. Last.fm will also receive standard network information such as your IP address as part of providing its service.

Your use of Last.fm is also governed by Last.fm’s own terms and privacy policy.

### Apple

FastScrobbler uses Apple system frameworks (for example: AuthenticationServices, Background Tasks, Widgets, Live Activities). Apple may receive standard device/service information as part of operating iOS/macOS. FastScrobbler does not send your music listening data to any developer-run server.

### No sale of data

FastScrobbler does not sell your personal information.

## Tracking and advertising

- FastScrobbler does not show ads.
- FastScrobbler does not use the advertising identifier (IDFA).
- FastScrobbler does not use third-party analytics or tracking SDKs.

## Data retention and deletion

- You can disconnect from Last.fm within the app, which removes the locally stored Last.fm session key.
- Queued scrobbles remain on-device until they are successfully submitted or until you remove the app.
- To remove all locally stored app data, delete FastScrobbler from your device.

Scrobbles that have already been submitted to Last.fm are stored by Last.fm according to their policies; you can manage or delete them via Last.fm.

## Security

FastScrobbler uses HTTPS for communication with Last.fm and uses Apple Keychain services for storing the Last.fm session key.

## Children’s privacy

FastScrobbler is not directed to children and does not knowingly collect personal information from children.

## Changes to this policy

If this policy changes, the “Effective date” above will be updated.

## Contact

For questions about this policy, contact the developer via the project’s support channel (for example, the GitHub repository issues page where this app is distributed).
