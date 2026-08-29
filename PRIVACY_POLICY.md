# Privacy Policy for FastScrobbler

**Effective date:** August 23, 2026

FastScrobbler is an iOS and macOS app for scrobbling Apple Music / Music app plays to Last.fm and ListenBrainz.

## Summary

- FastScrobbler does **not** run a developer-owned backend service.
- The app sends track metadata to **Last.fm** and/or **ListenBrainz** only after you connect your account(s) and use scrobbling features, including Shortcuts and Control Center widgets.
- If you enable **iCloud Sync**, FastScrobbler stores certain app data in your iCloud account so it can sync across your devices.
- If you enable **Scrobble Recently Played from Apple Music API** on iOS, FastScrobbler requests your recently played tracks from Apple Music.
- FastScrobbler uses **Firebase Crashlytics** to receive basic crash diagnostics and stability data from the app.
- FastScrobbler does **not**:
  - collect your listening data, Last.fm session key, or ListenBrainz user token
  - use advertising identifiers
  - track you across apps and websites

## Information the app accesses

### Apple Music / Media Library (on-device)

With your permission, FastScrobbler reads Apple Music / Media Library data to identify the current track and, if enabled, import recent plays for scrobbling. This can include:

- Track metadata (artist, title, album)
- Album artist (when available)
- Track duration
- Playback timestamps (e.g., "last played" time)
- Local media identifiers (e.g., persistent IDs)

FastScrobbler uses this information to determine what to submit to Last.fm or ListenBrainz. Local media identifiers are used only on-device.

### Apple Music API recent tracks (optional, iOS)

If you enable the optional "Scrobble Recently Played from Apple Music API" feature, FastScrobbler uses Apple Music / MusicKit APIs to request your recently played Apple Music tracks from Apple. This can include:

- Track metadata (artist, title, album)
- Apple Music catalog identifiers
- Approximate recency / ordering of recent plays exposed by Apple

Apple does not provide exact playback timestamps through this feature, so FastScrobbler estimates a timestamp when submitting the scrobble to Last.fm or ListenBrainz.

### Music app automation (macOS)

On macOS, FastScrobbler uses Apple Events (Automation) to read now-playing metadata from the Music app. This can include:

- Track metadata (artist, title, album)
- Track duration and playback position

If Automation permission is denied, the macOS app cannot read what is playing or scrobble it.

### Apple Music favorites (optional, on-device)

FastScrobbler can infer whether the current track is favorited in Apple Music, for example through the "Favorite Songs" playlist. If "Love Apple Music favourites on Last.fm" is enabled, the app may use that on-device favorite status to send a `track.love` request to Last.fm after scrobbling.

### Last.fm account connection

When you connect Last.fm, FastScrobbler uses a system web authentication session to complete Last.fm sign-in and obtain a Last.fm session key for your account.

### ListenBrainz account connection

When you connect ListenBrainz, you provide your ListenBrainz API User Token within the app. FastScrobbler validates this token directly against ListenBrainz to identify your username and authorize future submissions.

## Information the app stores (on your device)

FastScrobbler stores the following data locally:

- **Last.fm session key**: stored locally in shared app preferences so the app and its extensions can submit requests to Last.fm.
- **Last.fm username**: stored locally (UserDefaults) after it is fetched from Last.fm.
- **ListenBrainz user token**: stored locally in shared app preferences so the app and its extensions can submit requests to ListenBrainz.
- **ListenBrainz username**: stored locally (UserDefaults) after it is fetched from ListenBrainz.
- **Retry backlog** (queued scrobbles): stored locally so scrobbles can be retried when the network is available (including timestamps used for scrobbling).
- **Recent scrobble log**: stored locally to show recent activity in the app.
- **App settings**: such as scrobble threshold and metadata preferences, stored locally.
- **Listening history import state (iOS)**: stored locally to avoid re-importing the same plays (may include local media identifiers and play counts).
- **Apple Music API import state (iOS)**: stored locally for the optional recent-tracks importer (for example recent Apple Music track identifiers, import timestamps, and duplicate-prevention state).

FastScrobbler does not intentionally store your full music library; it stores only what is needed for queued scrobbles and recent history.

Some data may be stored in an app group container so the iOS app and its extensions, such as Live Activities and Control Center widgets, can share the same on-device state.

### Optional iCloud Sync

If you enable iCloud Sync on iOS, FastScrobbler stores certain app data in your iCloud account so it can sync across your devices signed into the same Apple ID. This may include:

- App settings and preferences
- Queued scrobbles / retry backlog
- Recent scrobble log
- Listening history import state used to avoid duplicate imports

FastScrobbler does not sync your Last.fm session key or ListenBrainz user token to iCloud through this feature.

## Information the app shares

### Last.fm

When you use FastScrobbler with Last.fm connected, the app sends requests directly from your device to Last.fm’s API. Depending on the feature, those requests may include:

- Artist and track title
- Album (if available)
- Track duration (if available)
- A timestamp representing when playback started / occurred (for scrobbles)

Last.fm also receives standard network information, such as your IP address, as part of providing its service. Your use of Last.fm is governed by Last.fm’s own terms and privacy policy.

### ListenBrainz

When you use FastScrobbler with ListenBrainz connected, the app sends requests directly from your device to the ListenBrainz API (`api.listenbrainz.org`). These requests include:

- Artist name and track title
- Album title (if available)
- Track duration (if available)
- A timestamp representing when playback occurred (for scrobbles / listens)

ListenBrainz also receives standard network information, such as your IP address, as part of providing its service. Your use of ListenBrainz is governed by the MetaBrainz Foundation / ListenBrainz privacy terms.

### Apple

FastScrobbler uses Apple system frameworks and services, including AuthenticationServices, MusicKit / Apple Music APIs, Background Tasks, Widgets, Live Activities, StoreKit, and optional iCloud Sync. Apple may receive standard device, account, purchase, and service information as part of operating iOS/macOS and these services.

If you enable Scrobble Recently Played from Apple Music API, Apple receives the request for your recent Apple Music plays.

If you enable iCloud Sync, Apple stores the synced FastScrobbler data in your iCloud account.

### Firebase Crashlytics

FastScrobbler uses Firebase Crashlytics, a Google service, to collect basic crash diagnostics and basic app stability information. This may include:

- Crash reports and stack traces
- Device model, OS version, and app version/build number
- Timestamps, session counts, and whether the app was in the foreground or background

Crash reports may still contain incidental technical context about app state at the time of a crash.

## What FastScrobbler does NOT do

- **FastScrobbler does not use Firebase for behavioral analytics, advertising, or cross-app tracking.**
- **FastScrobbler does not send your music listening data, Apple Music library contents, Last.fm session key, or ListenBrainz user token to the developer.**
- **FastScrobbler does not sell your personal information.**

### Advertising

- FastScrobbler does not show ads.
- FastScrobbler does not use the advertising identifier (IDFA).
- FastScrobbler does not use third-party advertising or cross-app tracking SDKs.

## Data retention and deletion

- You can disconnect from Last.fm or ListenBrainz within the app, which removes the locally stored session key or user token.
- Queued scrobbles remain on-device until they are successfully submitted or until you remove the app.
- To remove locally stored app data on a device, delete FastScrobbler from that device.
- If you enabled iCloud Sync, deleting the app does not necessarily remove the copy stored in iCloud. To remove that copy, turn off iCloud Sync in the app and use the app’s "Delete iCloud Data" option.

Scrobbles or listens already submitted to Last.fm or ListenBrainz are stored by those services under their own policies. You can manage or delete them directly through Last.fm or ListenBrainz.

## Security

FastScrobbler uses HTTPS when communicating with Last.fm, ListenBrainz (`api.listenbrainz.org`), Apple Music APIs, and Firebase services. The Last.fm session key and ListenBrainz user token are stored locally in shared app preferences.

## Children’s privacy

FastScrobbler is not directed to children and does not knowingly collect personal information from children.

## Changes to this policy

If this policy changes, the "Effective date" above will be updated.

## Contact

For questions about this policy, contact the developer or community at **r/FastScrobbler on Reddit**.
