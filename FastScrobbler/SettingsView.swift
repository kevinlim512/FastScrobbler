#if os(iOS)
import ActivityKit
#endif
import SwiftUI

struct SettingsView: View {
    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = true
    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = true

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var pro: ProPurchaseManager
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingLogoutConfirmation = false
#if os(macOS)
    let onBack: (() -> Void)?

    init(onBack: (() -> Void)? = nil) {
        self.onBack = onBack
    }
#endif

    var body: some View {
        Group {
#if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.title.weight(.bold))

                    macScrobbleControlsCard
                    macAccountCard
                }
                .padding()
                .padding(.top, MacFloatingBarLayout.contentTopPadding)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topLeading) {
                MacFloatingCircleButton(
                    systemImage: "chevron.left",
                    help: "Back",
                    accessibilityLabel: "Back",
                    action: {
                        if let onBack {
                            onBack()
                        } else {
                            dismiss()
                        }
                    }
                )
                .padding(.top, 10)
                .padding(.leading, 10)
            }
#else
            Form {
#if os(iOS)
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
#endif

                Section("FastScrobbler Pro") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(pro.isPro ? "Upgraded" : "Not upgraded")
                            .foregroundStyle(pro.isPro ? .green : .secondary)
                    }

                    NavigationLink {
                        ProUpgradeView(showsCloseButton: false)
                            .navigationTitle("FastScrobbler Pro")
#if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
#endif
                    } label: {
                        proPillText(pro.isPro ? "View Pro features" : "Upgrade to Pro", isLarge: true)
                            .padding(.vertical, 2)
                    }

                    proOptionToggle(
                        title: "Love Apple Music favourites on Last.fm",
                        isOn: $loveOnFavoriteEnabled,
                        locked: !pro.isPro
                    )

                    proScrobbleThresholdSlider(locked: !pro.isPro)

                    proOptionToggle(
                        title: "Use album artist when scrobbling",
                        isOn: $useAlbumArtistForScrobbling,
                        locked: !pro.isPro
                    )
                }

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
            }
#endif
        }
        .task {
            await pro.startIfNeeded()
            await auth.refreshUserInfoIfNeeded()
        }
        .alert("Log out of Last.fm?", isPresented: $isShowingLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("You’ll need to log in again to scrobble.")
        }
    }

#if os(macOS)
    private var macScrobbleControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scrobble Controls")
                .font(.title3.weight(.semibold))

            proOptionToggle(
                title: "Love Apple Music favourites on Last.fm",
                isOn: $loveOnFavoriteEnabled,
                locked: false
            )

            proScrobbleThresholdSlider(locked: false)

            proOptionToggle(
                title: "Use album artist when scrobbling",
                isOn: $useAlbumArtistForScrobbling,
                locked: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var macAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Account")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(auth.sessionKey != nil ? "Connected" : "Not connected")
                    .foregroundStyle(auth.sessionKey != nil ? .green : .secondary)
            }

            if auth.sessionKey != nil {
                HStack {
                    Text("Username")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(auth.username ?? "Loading…")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.subheadline)
            }

            HStack(spacing: 12) {
                Button {
                    if let url = auth.profileURL {
                        openURL(url)
                    }
                } label: {
                    Label("View Profile", systemImage: "person.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .disabled(auth.profileURL == nil)

                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("Log Out", systemImage: "power")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .tint(.red)
                .disabled(auth.sessionKey == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }
#endif

    private func performLogout() {
        auth.disconnect()
        engine.setUserPaused(false)
        engine.stop()
    }

    private func proPillText(_ text: String, isLarge: Bool = false) -> some View {
        Text(text)
            .font((isLarge ? Font.callout : Font.caption).weight(.bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, isLarge ? 14 : 10)
            .padding(.vertical, isLarge ? 8 : 6)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func proOptionToggle(title: String, isOn: Binding<Bool>, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .disabled(locked)
            if locked {
                proPillText("Pro feature")
            }
        }
        .opacity(locked ? 0.55 : 1)
    }

    @ViewBuilder
    private func proScrobbleThresholdSlider(locked: Bool) -> some View {
        let percentText = ProSettings.scrobbleThresholdPercentText(index: scrobbleThresholdIndex)
        let sliderValue = Binding<Double>(
            get: { Double(scrobbleThresholdIndex) },
            set: { scrobbleThresholdIndex = Int($0.rounded()) }
        )

        VStack(alignment: .leading, spacing: 6) {
            Text("Scrobble at \(percentText) of duration")
            Slider(value: sliderValue, in: 0...Double(ProSettings.scrobbleThresholdOptions.count - 1), step: 1)
                .disabled(locked)
            sliderStepMarkers(
                count: ProSettings.scrobbleThresholdOptions.count,
                activeIndex: scrobbleThresholdIndex,
                locked: locked
            )
            HStack {
                Text("10%")
                Spacer()
                Text("75%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if locked {
                proPillText("Pro feature")
            }
        }
        .opacity(locked ? 0.55 : 1)
    }

    private func sliderStepMarkers(count: Int, activeIndex: Int, locked: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(markerColor(isActive: index == activeIndex, locked: locked))
                    .frame(width: 4, height: 4)
                if index != count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private func markerColor(isActive: Bool, locked: Bool) -> Color {
        if isActive {
            return Color.primary.opacity(locked ? 0.22 : 0.32)
        } else {
            return Color.primary.opacity(0.14)
        }
    }
}

private struct LogoutConfirmationView: View {
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Log out of Last.fm?")
                    .font(.title2.weight(.semibold))

                Text("You’ll need to log in again to scrobble.")
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Confirm")
            .toolbar {
#if os(iOS)
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
#else
                ToolbarItem {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem {
                    Button("Log Out", role: .destructive) {
                        confirm()
                        dismiss()
                    }
                }
#endif
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }
}
