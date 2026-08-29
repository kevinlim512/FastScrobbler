import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/kevinlim512/FastScrobbler")!
    private static let redditURL = URL(string: "https://www.reddit.com/r/FastScrobbler/")!
    private static let redditSubmitURL = URL(string: "https://www.reddit.com/r/FastScrobbler/submit")!
    private static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6759501541?action=write-review")!
    // Last.fm brand red, used for the links section background
    private static let linksSectionRed = Color(red: 0.72, green: 0.14, blue: 0.14)
    private static let macSettingsButtonMinHeight: CGFloat = 28

    private enum CardPalette {
        static let backgroundOverlay = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.96),
            dark: NSColor(white: 0.10, alpha: 0.86)
        )
        static let border = dynamicColor(
            light: NSColor(white: 0.0, alpha: 0.10),
            dark: NSColor(white: 1.0, alpha: 0.16)
        )

        private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
            Color(
                NSColor(name: nil) { appearance in
                    let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                    return bestMatch == .darkAqua ? dark : light
                }
            )
        }
    }

    private enum PagePalette {
        static let background = dynamicColor(
            light: NSColor(white: 0.97, alpha: 1.0),
            dark: NSColor(white: 0.14, alpha: 1.0)
        )
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            NSColor(name: nil) { appearance in
                let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                return bestMatch == .darkAqua ? dark : light
            }
        )
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "7.0"
        return String.localizedStringWithFormat(localized("Version %@"), version)
    }

    private var contentCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CardPalette.backgroundOverlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CardPalette.border, lineWidth: 1)
            }
    }

    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = false
    @AppStorage(ProSettings.Keys.useFirstArtistOnlyForScrobbling, store: AppGroup.userDefaults) private var useFirstArtistOnlyForScrobbling = false
    @AppStorage(ProSettings.Keys.removeBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.preventDuplicateScrobblesEnabled, store: AppGroup.userDefaults) private var preventDuplicateScrobblesEnabled = true
    @AppStorage(AppSettings.Keys.sendNowPlayingAutomaticallyEnabled, store: AppGroup.userDefaults) private var sendNowPlayingAutomaticallyEnabled = true
    @AppStorage(AppSettings.Keys.buttonThemeSelection) private var buttonThemeSelectionRawValue = ButtonTheme.colorful.rawValue

    @ObservedObject private var iCloudSync = ICloudSyncCoordinator.shared

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var pro: ProPurchaseManager
    @EnvironmentObject private var appLanguage: AppLanguageStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum ActiveAlert: Identifiable {
        case logoutConfirmation
        case resetConfirmation

        var id: String {
            switch self {
            case .logoutConfirmation:
                return "logoutConfirmation"
            case .resetConfirmation:
                return "resetConfirmation"
            }
        }
    }

    private enum SettingsRoute: Hashable {
        case removeBracketsFromSongTitles
        case removeBracketsFromAlbumTitles
        case textReplacement
        case firstArtistOnly
    }

    @State private var activeAlert: ActiveAlert?
    @State private var isSigningInToLastFM = false
    @State private var lastFMLoginErrorText: String?
    @State private var listenBrainzTokenInput = ""
    @State private var isConnectingListenBrainz = false
    @State private var listenBrainzErrorText: String?
    @State private var startAtLoginEnabled = StartAtLoginManager.isEnabled
    @State private var startAtLoginErrorText: String?
    @State private var isConfirmingReset = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingListenBrainzSignOut = false
    @State private var isShowingListenBrainzConnectSheet = false
    @State private var isConfirmingICloudDeletion = false

    let onBack: (() -> Void)?
    let onOpenListenBrainzConnect: (() -> Void)?

    init(onBack: (() -> Void)? = nil, onOpenListenBrainzConnect: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onOpenListenBrainzConnect = onOpenListenBrainzConnect
    }

    var body: some View {
        NavigationStack {
            settingsRootContent
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .removeBracketsFromSongTitles:
                        RemoveBracketsSettingsPage(target: .songTitles)
                    case .removeBracketsFromAlbumTitles:
                        RemoveBracketsSettingsPage(target: .albumTitles)
                    case .textReplacement:
                        TextReplacementSettingsPage()
                    case .firstArtistOnly:
                        FirstArtistOnlySettingsPage()
                    }
                }
        }
        .task {
            await auth.refreshUserInfoIfNeeded()
            await listenBrainzAuth.refreshUserInfoIfNeeded()
            await iCloudSync.refreshStatus()
            startAtLoginEnabled = StartAtLoginManager.isEnabled
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .logoutConfirmation:
                Alert(
                    title: Text(localized("Sign Out of Last.fm?")),
                    message: Text(localized("You'll need to sign in again to scrobble.")),
                    primaryButton: .destructive(Text(localized("Sign Out")), action: performLogout),
                    secondaryButton: .cancel(Text(localized("Cancel")))
                )
            case .resetConfirmation:
                Alert(
                    title: Text(localized("Reset Settings?")),
                    message: Text(localized("This resets settings back to their initial values (your Last.fm and ListenBrainz accounts stay connected).")),
                    primaryButton: .destructive(Text(localized("Reset")), action: resetToInitialSettings),
                    secondaryButton: .cancel(Text(localized("Cancel")))
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

    @ViewBuilder
    private var settingsRootContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localized("Settings"))
                    .font(.title.weight(.bold))

                macGeneralCard
                macScrobbleControlsCard
                macAccountCard
                macListenBrainzAccountCard
                macICloudSyncCard
                macSupportCard

                Text(appVersionString)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, -6)
            }
            .padding()
            .padding(.top, MacFloatingBarLayout.contentTopPadding)
        }
        .background(PagePalette.background)
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
    }

    private var macGeneralCard: some View {
        let requiresApproval = (StartAtLoginManager.status == .requiresApproval)
        return VStack(alignment: .leading, spacing: 12) {
            Text(localized("General"))
                .font(.title3.weight(.semibold))

            HStack(alignment: .center, spacing: -20) {
                Text(localized("Language"))
                Picker(localized("Language"), selection: $appLanguage.selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
            }
            .fixedSize()

            HStack(alignment: .center, spacing: -20) {
                Text(localized("Button Theme"))
                Picker(localized("Button Theme"), selection: $buttonThemeSelectionRawValue) {
                    Text(localized("Colourful")).tag(ButtonTheme.colorful.rawValue)
                    Text(localized("Monochrome")).tag(ButtonTheme.monochrome.rawValue)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
            }
            .fixedSize()

            Toggle(localized("Start at login"), isOn: $startAtLoginEnabled)
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
        .background(contentCardBackground)
        .alert(localized("Couldn't update Start at login"), isPresented: Binding(
            get: { startAtLoginErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    startAtLoginErrorText = nil
                }
            }
        )) {
            Button(localized("OK"), role: .cancel) {}
        } message: {
            Text(startAtLoginErrorText ?? "")
        }
    }

    private var macScrobbleControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Scrobble Controls"))
                .font(.title3.weight(.semibold))

            Toggle(localized("Prevent duplicate scrobbles"), isOn: $preventDuplicateScrobblesEnabled)
            Text(localized("Avoids sending the same playback session more than once within a short time window."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(localized("Send Now Playing status"), isOn: $sendNowPlayingAutomaticallyEnabled)
                Text(localized("Display the currently playing track on your connected profile. Automatic scrobbles still work when this is off."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            scrobbleThresholdSlider()
            removeBracketsNavigationLink(target: .songTitles)
            removeBracketsNavigationLink(target: .albumTitles)
            textReplacementNavigationLink
            Toggle(isOn: proLockedBoolBinding($loveOnFavoriteEnabled, unlockedDefault: false)) {
                HStack {
                    Text(localized("Love Apple Music favourites on Last.fm"))
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
            .disabled(!pro.isPro)
            Toggle(isOn: proLockedBoolBinding($useAlbumArtistForScrobbling, unlockedDefault: false)) {
                HStack {
                    Text(localized("Replace song artist with album artist when scrobbling"))
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
            .disabled(!pro.isPro)
            firstArtistOnlyNavigationLink
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private var macAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized("Last.fm Account"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(auth.sessionKey != nil ? NSLocalizedString("Signed in", comment: "") : NSLocalizedString("Not connected", comment: ""))
                    .foregroundStyle(auth.sessionKey != nil ? .green : .secondary)
            }

            if auth.sessionKey != nil {
                HStack {
                    Text(localized("Username"))
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
                if !isConfirmingSignOut {
                    Button {
                        if let url = auth.freshProfileURL() {
                            openURL(url)
                        }
                    } label: {
                        Label(localized("View Profile"), systemImage: "person.circle")
                            .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .disabled(auth.sessionKey == nil || auth.profileURL == nil)
                }

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
                    if isConfirmingSignOut {
                        HStack(spacing: 8) {
                            Text(localized("Sign Out?"))
                                .foregroundStyle(.secondary)
                                .font(.headline)
                            Spacer()
                            Button(localized("Cancel")) {
                                isConfirmingSignOut = false
                            }
                            .buttonStyle(.bordered)
                            .pillButtonBorder()
                            Button(localized("Sign Out")) {
                                isConfirmingSignOut = false
                                performLogout()
                            }
                            .buttonStyle(.borderedProminent)
                            .pillButtonBorder()
                            .tint(.red)
                        }
                        .frame(minHeight: Self.macSettingsButtonMinHeight)
                    } else {
                        Button {
                            isConfirmingSignOut = true
                        } label: {
                            Label(localized("Sign Out"), systemImage: "power")
                                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                        }
                        .buttonStyle(.bordered)
                        .pillButtonBorder()
                        .tint(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private var macListenBrainzAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized("ListenBrainz Account"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(listenBrainzAuth.isConnected ? NSLocalizedString("Signed in", comment: "") : NSLocalizedString("Not connected", comment: ""))
                    .foregroundStyle(listenBrainzAuth.isConnected ? .green : .secondary)
            }

            if listenBrainzAuth.isConnected {
                if let username = listenBrainzAuth.username {
                    HStack {
                        Text(localized("Username"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(username)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .font(.subheadline)
                }

                HStack(spacing: 12) {
                    if !isConfirmingListenBrainzSignOut {
                        Button {
                            if let url = listenBrainzAuth.freshProfileURL() {
                                openURL(url)
                            }
                        } label: {
                            Label(localized("View Profile"), systemImage: "person.circle")
                                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                        }
                        .buttonStyle(.bordered)
                        .pillButtonBorder()
                        .disabled(listenBrainzAuth.profileURL == nil)
                    }

                    if isConfirmingListenBrainzSignOut {
                        HStack(spacing: 8) {
                            Text(localized("Sign Out?"))
                                .foregroundStyle(.secondary)
                                .font(.headline)
                            Spacer()
                            Button(localized("Cancel")) {
                                isConfirmingListenBrainzSignOut = false
                            }
                            .buttonStyle(.bordered)
                            .pillButtonBorder()
                            Button(localized("Sign Out")) {
                                isConfirmingListenBrainzSignOut = false
                                performListenBrainzLogout()
                            }
                            .buttonStyle(.borderedProminent)
                            .pillButtonBorder()
                            .tint(.red)
                        }
                        .frame(minHeight: Self.macSettingsButtonMinHeight)
                    } else {
                        Button {
                            isConfirmingListenBrainzSignOut = true
                        } label: {
                            Label(localized("Sign Out"), systemImage: "power")
                                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                        }
                        .buttonStyle(.bordered)
                        .pillButtonBorder()
                        .tint(.red)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("Beta feature: Sign in to start scrobbling to your ListenBrainz account."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        if let onOpenListenBrainzConnect {
                            onOpenListenBrainzConnect()
                        } else {
                            isShowingListenBrainzConnectSheet = true
                        }
                    } label: {
                        Label(localized("Sign In to ListenBrainz"), systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .pillButtonBorder()
                    .tint(Self.linksSectionRed)
                }
            }

            Text(localized("ListenBrainz support is currently in beta."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private var macSupportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                macRedditButton
                macAskQuestionButton
                macRateButton
                macGitHubButton
                macResetButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private func performLogout() {
        auth.disconnect()
        engine.setUserPaused(false)
        engine.stop()
    }

    private func performListenBrainzLogout() {
        listenBrainzAuth.disconnect()
        listenBrainzTokenInput = ""
        listenBrainzErrorText = nil
    }

    private func resetToInitialSettings() {
        let defaults = AppGroup.userDefaults
        defaults.removeObject(forKey: ProSettings.Keys.loveOnFavoriteEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.scrobbleThresholdIndex)
        defaults.removeObject(forKey: ProSettings.Keys.useAlbumArtistForScrobbling)
        defaults.removeObject(forKey: ProSettings.Keys.useFirstArtistOnlyForScrobbling)
        defaults.removeObject(forKey: ProSettings.Keys.firstArtistOnlyIgnoredArtists)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromSongTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromSongTitleKeywords)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.removeBracketsFromAlbumTitleKeywords)
        defaults.removeObject(forKey: ProSettings.Keys.preventDuplicateScrobblesEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.extendedListeningHistoryScanEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.sendNowPlayingAutomaticallyEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.buttonThemeSelection)
        defaults.removeObject(forKey: ProSettings.Keys.textReplacementRules)

        loveOnFavoriteEnabled = false
        scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
        preventDuplicateScrobblesEnabled = true
        useAlbumArtistForScrobbling = false
        useFirstArtistOnlyForScrobbling = false
        removeBracketsFromSongTitlesEnabled = false
        removeAllBracketsFromSongTitlesEnabled = false
        removeBracketsFromAlbumTitlesEnabled = false
        removeAllBracketsFromAlbumTitlesEnabled = false
        sendNowPlayingAutomaticallyEnabled = true
        buttonThemeSelectionRawValue = ButtonTheme.colorful.rawValue

        appLanguage.selection = .system
        Task { @MainActor in
            do {
                try StartAtLoginManager.setEnabled(false)
            } catch {
                startAtLoginErrorText = error.localizedDescription
            }
            startAtLoginEnabled = StartAtLoginManager.isEnabled
        }
    }

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
                Text(String.localizedStringWithFormat(localized("Scrobble at %@ of duration"), percentText))
                Spacer()
                lockedProInlineBadge
            }
            .foregroundStyle(pro.isPro ? .primary : .secondary)
            Slider(value: sliderValue, in: 0...Double(ProSettings.scrobbleThresholdOptions.count - 1), step: 1)
                .disabled(!pro.isPro)
                .frame(maxWidth: .infinity)
            HStack {
                ForEach(Array(ProSettings.scrobbleThresholdOptions.enumerated()), id: \.offset) { index, _ in
                    if index > 0 {
                        Spacer()
                    }
                    Text(ProSettings.scrobbleThresholdPercentText(index: index))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var textReplacementNavigationLink: some View {
        NavigationLink(value: SettingsRoute.textReplacement) {
            HStack(spacing: 12) {
                Text(localized("Text replacement"))
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
    }

    @ViewBuilder
    private var firstArtistOnlyNavigationLink: some View {
        NavigationLink(value: SettingsRoute.firstArtistOnly) {
            HStack(spacing: 12) {
                Text(localized("Scrobble only the first credited artist"))
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
    }

    @ViewBuilder
    private var lockedProInlineBadge: some View {
        if !pro.isPro {
            ProFeatureBadge()
        }
    }

    private func settingsBrandLabel(title: LocalizedStringKey, imageName: String, color: Color, iconSize: CGFloat = 24) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .frame(width: iconSize + 5, alignment: .center)
        }
        .foregroundStyle(color)
    }

    // Returns a binding that reads/writes the real storage only when Pro is active;
    // non-Pro users always see unlockedDefault and writes are silently dropped.
    private func proLockedBoolBinding(_ storage: Binding<Bool>, unlockedDefault: Bool) -> Binding<Bool> {
        Binding(
            get: { pro.isPro ? storage.wrappedValue : unlockedDefault },
            set: { newValue in
                guard pro.isPro else { return }
                storage.wrappedValue = newValue
            }
        )
    }

    private var macRedditButton: some View {
        Button {
            openURL(Self.redditURL)
        } label: {
            settingsBrandLabel(title: "r/FastScrobbler", imageName: "reddit_logo", color: .white, iconSize: 16)
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .pillButtonBorder()
        .tint(Self.linksSectionRed)
    }

    private var macAskQuestionButton: some View {
        Button {
            openURL(Self.redditSubmitURL)
        } label: {
            Label("Ask a Question or Report a Bug", systemImage: "questionmark.bubble")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .pillButtonBorder()
        .tint(Self.linksSectionRed)
    }

    private var macRateButton: some View {
        Button {
            openURL(Self.writeReviewURL)
        } label: {
            Label("Rate FastScrobbler", systemImage: "star.bubble")
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .pillButtonBorder()
        .tint(Self.linksSectionRed)
    }

    private var macGitHubButton: some View {
        Button {
            openURL(Self.repositoryURL)
        } label: {
            settingsBrandLabel(title: "GitHub", imageName: "github_logo", color: .white, iconSize: 16)
                .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .pillButtonBorder()
        .tint(Self.linksSectionRed)
    }

    private var macResetButton: some View {
        Group {
            if isConfirmingReset {
                HStack(spacing: 8) {
                    Text(localized("Reset Settings?"))
                        .foregroundStyle(.secondary)
                        .font(.headline)
                    Spacer()
                    Button(localized("Cancel")) {
                        isConfirmingReset = false
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    Button(localized("Reset")) {
                        isConfirmingReset = false
                        resetToInitialSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .pillButtonBorder()
                    .tint(.red)
                }
                .frame(minHeight: Self.macSettingsButtonMinHeight)
            } else {
                Button {
                    isConfirmingReset = true
                } label: {
                    Label("Reset Settings", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: Self.macSettingsButtonMinHeight)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .tint(.red)
            }
        }
    }

    private var canDeleteICloudData: Bool {
        !iCloudSync.isBusy && (iCloudSync.isSyncEnabled || iCloudSync.hasCloudData)
    }

    private var macICloudSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("iCloud Sync"))
                .font(.title3.weight(.semibold))

            Text(localized("Back up your FastScrobbler data to iCloud and keep it synced across your devices."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(
                isOn: Binding(
                    get: { iCloudSync.isSyncEnabled },
                    set: { newValue in
                        Task { await setICloudSyncEnabled(newValue) }
                    }
                )
            ) {
                Text(localized("Sync with iCloud"))
            }
            .disabled(iCloudSync.isBusy || (!iCloudSync.isICloudAvailable && !iCloudSync.isSyncEnabled))

            if !iCloudSync.isICloudAvailable {
                Text(localized("iCloud is currently unavailable on this device."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if iCloudSync.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if let error = iCloudSync.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let status = iCloudSync.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(role: .destructive) {
                isConfirmingICloudDeletion = true
            } label: {
                Label(localized("Delete iCloud Data"), systemImage: "trash")
                    .foregroundStyle(canDeleteICloudData ? .red : .secondary)
            }
            .disabled(!canDeleteICloudData)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentCardBackground)
        .confirmationDialog(
            localized("Delete iCloud Data?"),
            isPresented: $isConfirmingICloudDeletion,
            titleVisibility: .visible
        ) {
            Button(localized("Delete iCloud Data"), role: .destructive) {
                Task { await deleteICloudDataTapped() }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This removes only the iCloud copy of your synced FastScrobbler data. Local data on this Mac stays intact, and iCloud sync will be turned off here."))
        }
    }

    private func setICloudSyncEnabled(_ isEnabled: Bool) async {
        if isEnabled {
            do {
                try await iCloudSync.enableSync()
            } catch {}
        } else {
            await iCloudSync.disableSync()
        }
    }

    private func deleteICloudDataTapped() async {
        do {
            try await iCloudSync.deleteCloudData()
        } catch {}
    }

    private enum StartAtLoginManager {
        static var status: SMAppService.Status {
            SMAppService.mainApp.status
        }

        // .requiresApproval counts as "enabled" because the user already toggled it on;
        // macOS just hasn't granted final permission yet.
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
}

struct ProFeatureBadge: View {
    var body: some View {
        EmptyView()
    }
}
