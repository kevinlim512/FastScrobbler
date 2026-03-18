#if os(iOS)
import ActivityKit
#endif
#if os(macOS)
import ServiceManagement
#endif
import SwiftUI

struct SettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/kevinlim512/FastScrobbler")!
    private static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6759501541?action=write-review")!
#if os(macOS)
    private static let macSettingsButtonMinHeight: CGFloat = 34
#endif

    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = false
    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = false
    @AppStorage(ProSettings.Keys.stripEpAndSingleSuffixFromAlbum, store: AppGroup.userDefaults) private var stripEpAndSingleSuffixFromAlbum = false
    @AppStorage(ProSettings.Keys.preventDuplicateScrobblesEnabled, store: AppGroup.userDefaults) private var preventDuplicateScrobblesEnabled = true
    @AppStorage(ProSettings.Keys.scrobbleListeningHistoryFromAllDevicesEnabled, store: AppGroup.userDefaults) private var scrobbleListeningHistoryFromAllDevicesEnabled = false

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var pro: ProPurchaseManager
#if os(macOS)
    @EnvironmentObject private var appLanguage: AppLanguageStore
#endif
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum ActiveAlert: Identifiable {
        case logoutConfirmation
        case resetConfirmation
        case listeningHistoryScanResult(message: String)

        var id: String {
            switch self {
            case .logoutConfirmation:
                return "logoutConfirmation"
            case .resetConfirmation:
                return "resetConfirmation"
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
                    macSupportCard
                }
                .padding()
                .padding(.top, MacFloatingBarLayout.contentTopPadding)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topLeading) {
                if onBack != nil {
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
            }
#else
            Form {
#if os(iOS)
                Section("Live Activity (Beta)") {
                    Toggle("Show Live Activity (Beta)", isOn: $liveActivityEnabled)
                        .onValueChange(of: liveActivityEnabled) { isEnabled in
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
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Prevent duplicate scrobbles", isOn: $preventDuplicateScrobblesEnabled)
                        Text("Avoids sending the same track to Last.fm more than once within a short time window.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    scrobbleThresholdSlider()
                    Toggle(isOn: proLockedBoolBinding($loveOnFavoriteEnabled, unlockedDefault: false)) {
                        HStack {
                            Text("Love Apple Music favourites on Last.fm")
                                .foregroundStyle(pro.isPro ? .primary : .secondary)
                            Spacer()
                            ProFeatureBadge()
                        }
                    }
                    .disabled(!pro.isPro)
                    Toggle(isOn: proLockedBoolBinding($useAlbumArtistForScrobbling, unlockedDefault: false)) {
                        HStack {
                            Text("Replace song artist with album artist when scrobbling")
                                .foregroundStyle(pro.isPro ? .primary : .secondary)
                            Spacer()
                            ProFeatureBadge()
                        }
                    }
                    .disabled(!pro.isPro)
                    Toggle(isOn: proLockedBoolBinding($stripEpAndSingleSuffixFromAlbum, unlockedDefault: false)) {
                        HStack {
                            Text("Remove “- EP” / “- Single” from album name")
                                .foregroundStyle(pro.isPro ? .primary : .secondary)
                            Spacer()
                            ProFeatureBadge()
                        }
                    }
                    .disabled(!pro.isPro)
                }

#if os(iOS)
                Section("Listening History") {
                    let allDevicesEnabled = pro.isPro && scrobbleListeningHistoryFromAllDevicesEnabled

                    Button {
                        Task { await scanListeningHistoryTapped() }
                    } label: {
                        Label(
                            isScanningListeningHistory ? NSLocalizedString("Scanning…", comment: "") : NSLocalizedString("Scan Listening History", comment: ""),
                            systemImage: "clock.arrow.circlepath"
                        )
                        .foregroundStyle(auth.sessionKey != nil ? .primary : .secondary)
                    }
                    .padding(.vertical, 8)
                    .disabled(auth.sessionKey == nil || isScanningListeningHistory)

                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Imports plays from Apple Music Playback History (%@).", comment: ""),
                            allDevicesEnabled
                                ? NSLocalizedString("all devices", comment: "")
                                : NSLocalizedString("this device only", comment: "")
                        )
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: proLockedBoolBinding($scrobbleListeningHistoryFromAllDevicesEnabled, unlockedDefault: false)) {
                        HStack {
                            Text("Scrobble Listening History from all devices")
                                .foregroundStyle(pro.isPro ? .primary : .secondary)
                            Spacer()
                            ProFeatureBadge()
                        }
                    }
                    .disabled(!pro.isPro)
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
                            Text(auth.username ?? NSLocalizedString("Loading…", comment: ""))
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
                            Label(isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In", comment: ""), systemImage: "person.crop.circle")
                        }
                        .disabled(isSigningInToLastFM)
                    }
                }

                Section {
                    Button {
                        openURL(Self.writeReviewURL)
                    } label: {
                        Label("Rate FastScrobbler", systemImage: "star.bubble")
                    }

                    Button {
                        openURL(Self.repositoryURL)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    Button(role: .destructive) {
                        activeAlert = .resetConfirmation
                    } label: {
                        Label("Reset Settings", systemImage: "arrow.counterclockwise")
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
            case .resetConfirmation:
                Alert(
                    title: Text("Reset Settings?"),
                    message: Text("This resets settings back to their initial values (your Last.fm account stays connected)."),
                    primaryButton: .destructive(Text("Reset"), action: resetToInitialSettings),
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

            HStack(alignment: .center, spacing: -20) {
                Text("Language")
                Picker("Language", selection: $appLanguage.selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
            }
            .fixedSize()

            Toggle("Start at Login", isOn: $startAtLoginEnabled)
                .onValueChange(of: startAtLoginEnabled) { isEnabled in
                    Task { @MainActor in
                        do {
                            try StartAtLoginManager.setEnabled(isEnabled)
                        } catch {
                            startAtLoginErrorText = error.localizedDescription
                        }
                        startAtLoginEnabled = StartAtLoginManager.isEnabled
                    }
                }

            Text(
                requiresApproval
                    ? NSLocalizedString("Requires approval in System Settings → Login Items.", comment: "")
                    : NSLocalizedString("Launches FastScrobbler when you sign in.", comment: "")
            )
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

            Toggle("Prevent duplicate scrobbles", isOn: $preventDuplicateScrobblesEnabled)
            Text("Avoids sending the same track to Last.fm more than once within a short time window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            scrobbleThresholdSlider()
            Toggle(isOn: proLockedBoolBinding($loveOnFavoriteEnabled, unlockedDefault: false)) {
                HStack {
                    Text("Love Apple Music favourites on Last.fm")
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
            .disabled(!pro.isPro)
            Toggle(isOn: proLockedBoolBinding($useAlbumArtistForScrobbling, unlockedDefault: false)) {
                HStack {
                    Text("Replace song artist with album artist when scrobbling")
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
            .disabled(!pro.isPro)
            Toggle(isOn: proLockedBoolBinding($stripEpAndSingleSuffixFromAlbum, unlockedDefault: false)) {
                HStack {
                    Text("Remove “- EP” / “- Single” from album name")
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
            .disabled(!pro.isPro)
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
                Text(auth.sessionKey != nil ? NSLocalizedString("Connected", comment: "") : NSLocalizedString("Not connected", comment: ""))
                    .foregroundStyle(auth.sessionKey != nil ? .green : .secondary)
            }

            if auth.sessionKey != nil {
                HStack {
                    Text("Username")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(auth.username ?? NSLocalizedString("Loading…", comment: ""))
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
                        .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .disabled(auth.sessionKey == nil || auth.profileURL == nil)

                if auth.sessionKey == nil {
                    Button {
                        Task { await connectTapped() }
                    } label: {
                        Label(isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In", comment: ""), systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
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
                            .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
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

    private var macSupportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                macRateButton
                macGitHubButton
                macResetButton
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

    private func resetToInitialSettings() {
#if os(iOS)
        UserDefaults.standard.removeObject(forKey: LiveActivityManager.enabledDefaultsKey)
        liveActivityEnabled = false
        Task { @MainActor in
            await LiveActivityManager.shared.stop()
        }
#endif

        let defaults = AppGroup.userDefaults
        defaults.removeObject(forKey: ProSettings.Keys.loveOnFavoriteEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.scrobbleThresholdIndex)
        defaults.removeObject(forKey: ProSettings.Keys.useAlbumArtistForScrobbling)
        defaults.removeObject(forKey: ProSettings.Keys.stripEpAndSingleSuffixFromAlbum)
        defaults.removeObject(forKey: ProSettings.Keys.preventDuplicateScrobblesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.scrobbleListeningHistoryFromAllDevicesEnabled)

        loveOnFavoriteEnabled = false
        scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
        preventDuplicateScrobblesEnabled = true
        useAlbumArtistForScrobbling = false
        stripEpAndSingleSuffixFromAlbum = false
        scrobbleListeningHistoryFromAllDevicesEnabled = false

#if os(macOS)
        appLanguage.selection = .system
        Task { @MainActor in
            do {
                try StartAtLoginManager.setEnabled(false)
            } catch {
                startAtLoginErrorText = error.localizedDescription
            }
            startAtLoginEnabled = StartAtLoginManager.isEnabled
        }
#endif
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
            activeAlert = .listeningHistoryScanResult(
                message: String.localizedStringWithFormat(
                    NSLocalizedString("Imported %lld play(s).", comment: ""),
                    Int64(imported)
                )
            )
        } else {
            activeAlert = .listeningHistoryScanResult(
                message: NSLocalizedString(
                    "No new plays found. Scrobbling from Listening History only works for songs added to your Library.",
                    comment: ""
                )
            )
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
        let effectiveIndex = pro.isPro ? scrobbleThresholdIndex : ProSettings.defaultScrobbleThresholdIndex
        let percentText = ProSettings.scrobbleThresholdPercentText(index: effectiveIndex)
        let sliderValue = Binding<Double>(
            get: { Double(effectiveIndex) },
            set: {
                guard pro.isPro else { return }
                scrobbleThresholdIndex = Int($0.rounded())
            }
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scrobble at \(percentText) of duration")
                Spacer()
                ProFeatureBadge()
            }
            .foregroundStyle(pro.isPro ? .primary : .secondary)
            Slider(value: sliderValue, in: 0...Double(ProSettings.scrobbleThresholdOptions.count - 1), step: 1)
                .disabled(!pro.isPro)
            sliderStepMarkers(
                count: ProSettings.scrobbleThresholdOptions.count,
                activeIndex: effectiveIndex,
                locked: !pro.isPro
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

    private func proLockedBoolBinding(_ storage: Binding<Bool>, unlockedDefault: Bool) -> Binding<Bool> {
        Binding(
            get: { pro.isPro ? storage.wrappedValue : unlockedDefault },
            set: { newValue in
                guard pro.isPro else { return }
                storage.wrappedValue = newValue
            }
        )
    }

#if os(macOS)
    private var macRateButton: some View {
        Button {
            openURL(Self.writeReviewURL)
        } label: {
            Label("Rate FastScrobbler", systemImage: "star.bubble")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
    }

    private var macGitHubButton: some View {
        Button {
            openURL(Self.repositoryURL)
        } label: {
            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
    }

    private var macResetButton: some View {
        Button(role: .destructive) {
            activeAlert = .resetConfirmation
        } label: {
            Label("Reset Settings", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
        .tint(.red)
    }

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

struct ProFeatureBadge: View {
    var body: some View {
#if os(macOS)
        EmptyView()
#else
        Text("Pro")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.yellow)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Pro")
#endif
    }
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
