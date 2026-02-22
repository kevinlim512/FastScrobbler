import ActivityKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = true

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @Environment(\.openURL) private var openURL

    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Last.fm")
                    Spacer()
                    if auth.sessionKey != nil {
                        Text("Connected")
                            .foregroundColor(.green)
                    } else {
                        Text("Not connected")
                            .foregroundColor(.secondary)
                    }
                }

                if auth.sessionKey != nil {
                    HStack {
                        Text("Username")
                        Spacer()
                        Text(auth.username ?? "Loading…")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }

                Button {
                    if let url = auth.profileURL {
                        openURL(url)
                    }
                } label: {
                    Label("View Profile", systemImage: "person.circle")
                }
                .disabled(auth.profileURL == nil)

                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("Log Out", systemImage: "power")
                }
                .disabled(auth.sessionKey == nil)
            }

            Section("Live Activity") {
                Toggle("Show Live Activity", isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { isEnabled in
                        if isEnabled {
                            LiveActivityManager.shared.startIfPossible()
                        } else {
                            Task { @MainActor in
                                await LiveActivityManager.shared.stop()
                            }
                        }
                    }

                if #available(iOS 16.1, *) {
                    if !ActivityAuthorizationInfo().areActivitiesEnabled {
                        Text("Live Activities are disabled in iOS Settings for FastScrobbler.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Shows scrobbling status on your Lock Screen and Dynamic Island.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await auth.refreshUserInfoIfNeeded()
        }
        .fullScreenCover(isPresented: $isShowingLogoutConfirmation) {
            LogoutConfirmationView {
                performLogout()
            }
        }
    }

    private func performLogout() {
        auth.disconnect()
        engine.setUserPaused(false)
        engine.stop()
    }
}

private struct LogoutConfirmationView: View {
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Log out of Last.fm?")
                    .font(.title2.weight(.semibold))

                Text("You’ll need to log in again to scrobble.")
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out", role: .destructive) {
                        confirm()
                        dismiss()
                    }
                }
            }
        }
    }
}
