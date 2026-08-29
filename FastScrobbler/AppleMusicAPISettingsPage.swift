import SwiftUI

struct AppleMusicAPISettingsPage: View {
    @AppStorage(AppSettings.Keys.scrobbleAppleMusicAPIEnabled, store: AppGroup.userDefaults) private var scrobbleAppleMusicAPIEnabled = true
    @AppStorage(AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks, store: AppGroup.userDefaults) private var scrobbleOnlyNonLibraryAppleMusicAPITracks = true

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("Scrobble Recently Played from Apple Music API", isOn: $scrobbleAppleMusicAPIEnabled)
                            .onValueChange(of: scrobbleAppleMusicAPIEnabled) { isEnabled in
                                Task {
                                    await AppModel.shared.handleAppleMusicAPIScrobblingChanged(isEnabled: isEnabled)
                                }
                            }
                    }
                    .padding(.bottom, 16)

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(localized("Retrieves up to 30 recently played songs via the Apple Music API, then adds them to the Listening History review list. Plays are recorded even when FastScrobbler is in the background.\n\nNote: playback timestamps aren’t provided by the API, so FastScrobbler assigns an estimated timestamp when the scrobble is submitted. Songs are recorded regardless of playback duration.\n\nWhen \"Auto-scrobble Listening History\" is off, Recently Played API songs are added to the Listening History review list instead of being submitted automatically."))
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 16)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle(localized("Only scrobble non-library songs"), isOn: $scrobbleOnlyNonLibraryAppleMusicAPITracks)
                            .disabled(!scrobbleAppleMusicAPIEnabled)
                            .foregroundStyle(scrobbleAppleMusicAPIEnabled ? .primary : .secondary)
                            .tint(Color.accentColor)
                    }
                    .padding(.bottom, 16)

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(localized("Best-effort filter: FastScrobbler checks for recently played API songs that are present in your library, and skips them. If FastScrobbler can't confirm a match, the song will be scrobbled.\n\nRecommended to reduce duplicates between Listening History and Recently Played API scans."))
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
