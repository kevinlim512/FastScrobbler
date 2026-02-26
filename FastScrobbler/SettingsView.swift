#if os(iOS)
import ActivityKit
#endif
#if os(macOS)
import ServiceManagement
#endif
import SwiftUI

struct SettingsView: View {
    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = false
    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = true
    @AppStorage(ProSettings.Keys.stripEpAndSingleSuffixFromAlbum, store: AppGroup.userDefaults) private var stripEpAndSingleSuffixFromAlbum = false

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum ActiveAlert: Identifiable {
        case logoutConfirmation
        case listeningHistoryScanResult(message: String)

        var id: String {
            switch self {
            case .logoutConfirmation:
                return "logoutConfirmation"
            case .listeningHistoryScanResult(let message):
                return "listeningHistoryScanResult-\(message)"
            }
        }
    }

    @State private var activeAlert: ActiveAlert?
    @State private var isSigningInToLastFM = false
    @State private var lastFMLoginErrorText: String?
#if os(iOS)
    @State private var isScanningListeningHistory = false
#endif
#if os(macOS)
    @State private var startAtLoginEnabled = StartAtLoginManager.isEnabled
    @State private var startAtLoginErrorText: String?
#endif
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

                    macGeneralCard
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
                Section("Live Activity (Beta)") {
                    Toggle("Show Live Activity (Beta)", isOn: $liveActivityEnabled)
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

                    Text("Beta feature: shows scrobbling status on your Lock Screen and Dynamic Island.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif

                Section("Scrobble Controls") {
                    Toggle("Love Apple Music favourites on Last.fm", isOn: $loveOnFavoriteEnabled)
                    scrobbleThresholdSlider()
                    Toggle("Use album artist when scrobbling", isOn: $useAlbumArtistForScrobbling)
                    Toggle("Remove “- EP” / “- Single” from album name", isOn: $stripEpAndSingleSuffixFromAlbum)
                }

#if os(iOS)
                Section("Listening History") {
                    Button {
                        Task { await scanListeningHistoryTapped() }
                    } label: {
                        Label(
                            isScanningListeningHistory ? "Scanning…" : "Scan Listening History",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .foregroundStyle(auth.sessionKey != nil ? .primary : .secondary)
                    }
                    .disabled(auth.sessionKey == nil || isScanningListeningHistory)

                    Text("Imports plays from Apple Music Playback History (this device only).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif

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

                    let canViewProfile = (auth.sessionKey != nil && auth.profileURL != nil)
                    Button {
                        if let url = auth.profileURL {
                            openURL(url)
                        }
                    } label: {
                        Label("View Profile", systemImage: "person.circle")
                            .foregroundStyle(canViewProfile ? .primary : .secondary)
                    }
                    .disabled(!canViewProfile)

                    if auth.sessionKey != nil {
                        Button(role: .destructive) {
                            activeAlert = .logoutConfirmation
                        } label: {
                            Label("Sign Out", systemImage: "power")
                        }
                    } else {
                        Button {
                            Task { await connectTapped() }
                        } label: {
                            Label(isSigningInToLastFM ? "Signing In…" : "Sign In", systemImage: "person.crop.circle")
                        }
                        .disabled(isSigningInToLastFM)
                    }
                }
            }
#endif
        }
        .task {
            await auth.refreshUserInfoIfNeeded()
#if os(macOS)
            startAtLoginEnabled = StartAtLoginManager.isEnabled
#endif
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .logoutConfirmation:
                Alert(
                    title: Text("Sign Out of Last.fm?"),
                    message: Text("You’ll need to sign in again to scrobble."),
                    primaryButton: .destructive(Text("Sign Out"), action: performLogout),
                    secondaryButton: .cancel()
                )
            case .listeningHistoryScanResult(let message):
                Alert(
                    title: Text("Listening History"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .alert("Couldn't sign in to Last.fm", isPresented: Binding(
            get: { lastFMLoginErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    lastFMLoginErrorText = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastFMLoginErrorText ?? "")
        }
    }

#if os(macOS)
    private var macGeneralCard: some View {
        let requiresApproval = (StartAtLoginManager.status == .requiresApproval)
        return VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.title3.weight(.semibold))

            Toggle("Start at login", isOn: $startAtLoginEnabled)
                .onChange(of: startAtLoginEnabled) { isEnabled in
                    Task { @MainActor in
                        do {
                            try StartAtLoginManager.setEnabled(isEnabled)
                        } catch {
                            startAtLoginErrorText = error.localizedDescription
                        }
                        startAtLoginEnabled = StartAtLoginManager.isEnabled
                    }
                }

            Text(requiresApproval ? "Requires approval in System Settings → Login Items." : "Launches FastScrobbler when you sign in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .alert("Couldn't update Start at Login", isPresented: Binding(
            get: { startAtLoginErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    startAtLoginErrorText = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startAtLoginErrorText ?? "")
        }
    }

    private var macScrobbleControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scrobble Controls")
                .font(.title3.weight(.semibold))

            Toggle("Love Apple Music favourites on Last.fm", isOn: $loveOnFavoriteEnabled)
            scrobbleThresholdSlider()
            Toggle("Use album artist when scrobbling", isOn: $useAlbumArtistForScrobbling)
            Toggle("Remove “- EP” / “- Single” from album name", isOn: $stripEpAndSingleSuffixFromAlbum)
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
                .disabled(auth.sessionKey == nil || auth.profileURL == nil)

                if auth.sessionKey == nil {
                    Button {
                        Task { await connectTapped() }
                    } label: {
                        Label(isSigningInToLastFM ? "Signing In…" : "Sign In", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(.blue)
                    .disabled(isSigningInToLastFM)
                } else {
                    Button(role: .destructive) {
                        activeAlert = .logoutConfirmation
                    } label: {
                        Label("Sign Out", systemImage: "power")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(.red)
                }
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

#if os(iOS)
    @MainActor
    private func scanListeningHistoryTapped() async {
        guard auth.sessionKey != nil else { return }
        guard !isScanningListeningHistory else { return }
        isScanningListeningHistory = true
        defer { isScanningListeningHistory = false }

        let imported = await AppModel.shared.scanListeningHistory()
        if imported > 0 {
            activeAlert = .listeningHistoryScanResult(message: "Imported \(imported) play\(imported == 1 ? "" : "s").")
        } else {
            activeAlert = .listeningHistoryScanResult(message: "No new plays found. Listening History only imports plays from this device.")
        }
    }
#endif

    @MainActor
    private func connectTapped() async {
        guard !isSigningInToLastFM else { return }
        isSigningInToLastFM = true
        lastFMLoginErrorText = nil
        defer { isSigningInToLastFM = false }

        do {
            try await auth.connect()
            engine.start()
        } catch {
            if error is CancellationError { return }
            lastFMLoginErrorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private func scrobbleThresholdSlider() -> some View {
        let percentText = ProSettings.scrobbleThresholdPercentText(index: scrobbleThresholdIndex)
        let sliderValue = Binding<Double>(
            get: { Double(scrobbleThresholdIndex) },
            set: { scrobbleThresholdIndex = Int($0.rounded()) }
        )

        VStack(alignment: .leading, spacing: 6) {
            Text("Scrobble at \(percentText) of duration")
            Slider(value: sliderValue, in: 0...Double(ProSettings.scrobbleThresholdOptions.count - 1), step: 1)
            sliderStepMarkers(
                count: ProSettings.scrobbleThresholdOptions.count,
                activeIndex: scrobbleThresholdIndex,
                locked: false
            )
            HStack {
                Text("10%")
                Spacer()
                Text("75%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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

#if os(macOS)
    private enum StartAtLoginManager {
        static var status: SMAppService.Status {
            SMAppService.mainApp.status
        }

        static var isEnabled: Bool {
            switch status {
            case .enabled, .requiresApproval:
                return true
            default:
                return false
            }
        }

        static func setEnabled(_ enabled: Bool) throws {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
#endif
}

private struct LogoutConfirmationView: View {
    let confirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign Out of Last.fm?")
                    .font(.title2.weight(.semibold))

                Text("You’ll need to sign in again to scrobble.")
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
                    Button("Sign Out", role: .destructive) {
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
                    Button("Sign Out", role: .destructive) {
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
