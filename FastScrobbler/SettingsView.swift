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
#else
    private static let iosLockedProNavigationBadgeTrailingInset: CGFloat = 24
    private static let iosLockedProToggleBadgeTrailingInset: CGFloat = 63
#endif

    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = false
    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = false
    @AppStorage(ProSettings.Keys.stripEpAndSingleSuffixFromAlbum, store: AppGroup.userDefaults) private var stripEpAndSingleSuffixFromAlbum = false
    @AppStorage(ProSettings.Keys.removeBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.preventDuplicateScrobblesEnabled, store: AppGroup.userDefaults) private var preventDuplicateScrobblesEnabled = true
    @AppStorage(AppSettings.Keys.scrobbleListeningHistoryEnabled, store: AppGroup.userDefaults) private var scrobbleListeningHistoryEnabled = true
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

    private enum SettingsRoute: Hashable {
        case removeBracketsFromSongTitles
        case removeBracketsFromAlbumTitles
    }

    @State private var activeAlert: ActiveAlert?
    @State private var isSigningInToLastFM = false
    @State private var lastFMLoginErrorText: String?
    @State private var isPresentingSupportEmailOptions = false
    @State private var supportEmailDraft: SupportEmailDraft?
    @State private var supportEmailErrorText: String?
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
        NavigationStack {
            settingsRootContent
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .removeBracketsFromSongTitles:
                        RemoveBracketsSettingsPage(target: .songTitles)
                    case .removeBracketsFromAlbumTitles:
                        RemoveBracketsSettingsPage(target: .albumTitles)
                    }
                }
#if os(iOS)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            IOSCloseButtonLabel(style: .plain)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
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
        .alert("Couldn't start email", isPresented: Binding(
            get: { supportEmailErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    supportEmailErrorText = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(supportEmailErrorText ?? "")
        }
#if os(iOS)
        .alert("Email FastScrobbler", isPresented: $isPresentingSupportEmailOptions) {
            Button("Feedback") {
                startSupportEmail(.feedback)
            }

            Button("Bug Report") {
                startSupportEmail(.bugReport)
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $supportEmailDraft) { draft in
            SupportEmailComposeView(draft: draft) {
                supportEmailDraft = nil
            }
        }
#else
        .confirmationDialog("Email FastScrobbler", isPresented: $isPresentingSupportEmailOptions, titleVisibility: .visible) {
            Button("Feedback") {
                startSupportEmail(.feedback)
            }

            Button("Bug Report") {
                startSupportEmail(.bugReport)
            }

            Button("Cancel", role: .cancel) {}
        }
#endif
    }

    @ViewBuilder
    private var settingsRootContent: some View {
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
                removeBracketsNavigationLink(target: .songTitles)
                removeBracketsNavigationLink(target: .albumTitles)
                Toggle(isOn: proLockedBoolBinding($loveOnFavoriteEnabled, unlockedDefault: false)) {
                    HStack {
                        Text("Love Apple Music favourites on Last.fm")
                            .foregroundStyle(pro.isPro ? .primary : .secondary)
                        Spacer()
                        proFeatureBadgePlaceholder
                    }
                }
                .disabled(!pro.isPro)
                .overlay(alignment: .trailing) {
                    lockedProBadgeOverlay(trailingInset: Self.iosLockedProToggleBadgeTrailingInset)
                }
                Toggle(isOn: proLockedBoolBinding($useAlbumArtistForScrobbling, unlockedDefault: false)) {
                    HStack {
                        Text("Replace song artist with album artist when scrobbling")
                            .foregroundStyle(pro.isPro ? .primary : .secondary)
                        Spacer()
                        proFeatureBadgePlaceholder
                    }
                }
                .disabled(!pro.isPro)
                .overlay(alignment: .trailing) {
                    lockedProBadgeOverlay(trailingInset: Self.iosLockedProToggleBadgeTrailingInset)
                }
                Toggle(isOn: proLockedBoolBinding($stripEpAndSingleSuffixFromAlbum, unlockedDefault: false)) {
                    HStack {
                        Text("Remove “- EP” / “- Single” from album name")
                            .foregroundStyle(pro.isPro ? .primary : .secondary)
                        Spacer()
                        proFeatureBadgePlaceholder
                    }
                }
                .disabled(!pro.isPro)
                .overlay(alignment: .trailing) {
                    lockedProBadgeOverlay(trailingInset: Self.iosLockedProToggleBadgeTrailingInset)
                }
            }

#if os(iOS)
            Section("Listening History") {
                let allDevicesEnabled = scrobbleListeningHistoryEnabled && pro.isPro && scrobbleListeningHistoryFromAllDevicesEnabled

                Button {
                    Task { await scanListeningHistoryTapped() }
                } label: {
                    Label(
                        isScanningListeningHistory ? NSLocalizedString("Scanning…", comment: "") : NSLocalizedString("Scan Listening History", comment: ""),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(auth.sessionKey != nil && scrobbleListeningHistoryEnabled ? .primary : .secondary)
                }
                .padding(.vertical, 8)
                .disabled(auth.sessionKey == nil || isScanningListeningHistory || !scrobbleListeningHistoryEnabled)

                Text(
                    scrobbleListeningHistoryEnabled
                        ? String.localizedStringWithFormat(
                            NSLocalizedString("Imports plays from Apple Music Playback History (%@).", comment: ""),
                            allDevicesEnabled
                                ? NSLocalizedString("all devices", comment: "")
                                : NSLocalizedString("this device only", comment: "")
                        )
                        : NSLocalizedString("Listening History scrobbling is turned off.", comment: "")
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Scrobble from Listening History", isOn: $scrobbleListeningHistoryEnabled)
                        .onValueChange(of: scrobbleListeningHistoryEnabled) { isEnabled in
                            Task { await AppModel.shared.handleListeningHistoryScrobblingChanged(isEnabled: isEnabled) }
                        }
                    Text("When off, FastScrobbler won’t import or scrobble plays from Apple Music Playback History.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: proLockedBoolBinding($scrobbleListeningHistoryFromAllDevicesEnabled, unlockedDefault: false)) {
                    HStack {
                        Text("Scrobble Listening History from all devices")
                            .foregroundStyle(pro.isPro ? .primary : .secondary)
                        Spacer()
                        proFeatureBadgePlaceholder
                    }
                }
                .disabled(!pro.isPro)
                .overlay(alignment: .trailing) {
                    lockedProBadgeOverlay(trailingInset: Self.iosLockedProToggleBadgeTrailingInset)
                }
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
                    if let url = auth.freshProfileURL() {
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
                    isPresentingSupportEmailOptions = true
                } label: {
                    Label("Email FastScrobbler", systemImage: "envelope")
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
            removeBracketsNavigationLink(target: .songTitles)
            removeBracketsNavigationLink(target: .albumTitles)
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
                    if let url = auth.freshProfileURL() {
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
                macEmailButton
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
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromSongTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromSongTitleKeywords)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromAlbumTitleKeywords)
        defaults.removeObject(forKey: ProSettings.Keys.preventDuplicateScrobblesEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.scrobbleListeningHistoryEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.scrobbleListeningHistoryFromAllDevicesEnabled)

        loveOnFavoriteEnabled = false
        scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
        preventDuplicateScrobblesEnabled = true
        useAlbumArtistForScrobbling = false
        stripEpAndSingleSuffixFromAlbum = false
        removeBracketsFromSongTitlesEnabled = false
        removeAllBracketsFromSongTitlesEnabled = false
        removeBracketsFromAlbumTitlesEnabled = false
        removeAllBracketsFromAlbumTitlesEnabled = false
        scrobbleListeningHistoryEnabled = true
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

    @MainActor
    private func startSupportEmail(_ kind: SupportEmailKind) {
        isPresentingSupportEmailOptions = false
        let draft = SupportEmailDraft.make(kind: kind, context: supportEmailContext())

#if os(iOS)
        guard SupportEmailMailCompose.canSendMail else {
            supportEmailErrorText = SupportEmailError.unavailable.localizedDescription
            return
        }

        supportEmailDraft = draft
#elseif os(macOS)
        do {
            try SupportEmailMailCompose.compose(draft)
        } catch let error as SupportEmailError {
            supportEmailErrorText = error.localizedDescription
        } catch {
            supportEmailErrorText = SupportEmailError.preparationFailed.localizedDescription
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
                lockedProInlineBadge
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

    private func removeBracketsNavigationLink(target: RemoveBracketsSettingsPage.Target) -> some View {
        let route: SettingsRoute
        switch target {
        case .songTitles:
            route = .removeBracketsFromSongTitles
        case .albumTitles:
            route = .removeBracketsFromAlbumTitles
        }
#if os(macOS)
        return NavigationLink(value: route) {
            HStack(spacing: 12) {
                Text(target.settingsLabel)
                    .foregroundStyle(pro.isPro ? .primary : .secondary)
                Spacer()
                ProFeatureBadge()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!pro.isPro)
#else
        return NavigationLink(value: route) {
            HStack {
                Text(target.settingsLabel)
                    .foregroundStyle(pro.isPro ? .primary : .secondary)
                Spacer()
                proFeatureBadgePlaceholder
            }
        }
        .disabled(!pro.isPro)
        .overlay(alignment: .trailing) {
            lockedProBadgeOverlay(trailingInset: Self.iosLockedProNavigationBadgeTrailingInset)
        }
#endif
    }

    @ViewBuilder
    private var lockedProInlineBadge: some View {
        if !pro.isPro {
            ProFeatureBadge()
        }
    }

#if os(iOS)
    @ViewBuilder
    private var proFeatureBadgePlaceholder: some View {
        if !pro.isPro {
            ProFeatureBadge()
                .hidden()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func lockedProBadgeOverlay(trailingInset: CGFloat) -> some View {
        if !pro.isPro {
            ProFeatureBadge()
                .allowsHitTesting(false)
                .padding(.trailing, trailingInset)
        }
    }
#endif

    private func proLockedBoolBinding(_ storage: Binding<Bool>, unlockedDefault: Bool) -> Binding<Bool> {
        Binding(
            get: { pro.isPro ? storage.wrappedValue : unlockedDefault },
            set: { newValue in
                guard pro.isPro else { return }
                storage.wrappedValue = newValue
            }
        )
    }

    private func supportEmailContext() -> SupportEmailContext {
        let effectiveThresholdIndex = pro.isPro
            ? scrobbleThresholdIndex
            : ProSettings.defaultScrobbleThresholdIndex
        var settings: [SupportEmailSetting] = []

#if os(iOS)
        settings.append(SupportEmailSetting(
            label: "Live Activity enabled",
            value: SupportEmailDiagnostics.yesNo(liveActivityEnabled)
        ))
#endif

        settings.append(SupportEmailSetting(
            label: "Prevent duplicate scrobbles",
            value: SupportEmailDiagnostics.yesNo(preventDuplicateScrobblesEnabled)
        ))
        settings.append(SupportEmailSetting(
            label: "Scrobble threshold",
            value: "\(ProSettings.scrobbleThresholdPercentText(index: effectiveThresholdIndex)) of duration"
        ))
        settings.append(SupportEmailSetting(
            label: "Love Apple Music favourites on Last.fm",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? loveOnFavoriteEnabled : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Replace song artist with album artist when scrobbling",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? useAlbumArtistForScrobbling : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove “- EP” / “- Single” from album name",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? stripEpAndSingleSuffixFromAlbum : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove brackets for song titles",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? removeBracketsFromSongTitlesEnabled : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove ALL brackets for song titles",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? removeAllBracketsFromSongTitlesEnabled : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove brackets keywords for song titles",
            value: ProSettings.removeBracketsFromSongTitleKeywords().joined(separator: ", ")
        ))
        settings.append(SupportEmailSetting(
            label: "Remove brackets for album titles",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? removeBracketsFromAlbumTitlesEnabled : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove ALL brackets for album titles",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? removeAllBracketsFromAlbumTitlesEnabled : false)
        ))
        settings.append(SupportEmailSetting(
            label: "Remove brackets keywords for album titles",
            value: ProSettings.removeBracketsFromAlbumTitleKeywords().joined(separator: ", ")
        ))

#if os(iOS)
        settings.append(SupportEmailSetting(
            label: "Scrobble from Listening History",
            value: SupportEmailDiagnostics.yesNo(scrobbleListeningHistoryEnabled)
        ))
        settings.append(SupportEmailSetting(
            label: "Scrobble Listening History from all devices",
            value: SupportEmailDiagnostics.yesNo(pro.isPro ? scrobbleListeningHistoryFromAllDevicesEnabled : false)
        ))

        return SupportEmailContext(
            platformName: "iOS",
            isProEnabled: pro.isPro,
            isLastFMConnected: auth.sessionKey != nil,
            settings: settings
        )
#elseif os(macOS)
        settings.insert(SupportEmailSetting(label: "Language", value: appLanguage.selection.title), at: 0)
        settings.insert(
            SupportEmailSetting(
                label: "Start at Login",
                value: SupportEmailDiagnostics.yesNo(startAtLoginEnabled)
            ),
            at: 1
        )

        return SupportEmailContext(
            platformName: "macOS",
            isProEnabled: pro.isPro,
            isLastFMConnected: auth.sessionKey != nil,
            settings: settings
        )
#endif
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

    private var macEmailButton: some View {
        Button {
            isPresentingSupportEmailOptions = true
        } label: {
            Label("Email FastScrobbler", systemImage: "envelope")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
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
