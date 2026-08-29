import SwiftUI
import ActivityKit

let proYellow = Color(red: 0.89, green: 0.71, blue: 0.16)
let darkOrange = Color(red: 0.85, green: 0.40, blue: 0.0)
let scrobbleNowPurple = Color(UIColor { traitCollection in
    traitCollection.userInterfaceStyle == .dark
        ? UIColor(red: 0.66, green: 0.36, blue: 0.78, alpha: 1.0)
        : UIColor(red: 0.58, green: 0.28, blue: 0.72, alpha: 1.0)
})

struct SettingsIconBadge: View {
    let systemImage: String
    let backgroundColor: Color
    var foregroundColor: Color = .white
    var iconSize: CGFloat = 13
    var yOffset: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor)
                .frame(width: 28, height: 28)
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(foregroundColor)
                .offset(y: yOffset)
        }
    }
}

struct SettingsBrandIconBadge: View {
    let imageName: String
    let backgroundColor: Color
    var foregroundColor: Color = .white
    var iconSize: CGFloat = 13

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor)
                .frame(width: 28, height: 28)
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(foregroundColor)
        }
    }
}

enum SettingsScrollTarget: String {
    case listeningHistory

    var anchorID: String {
        rawValue
    }
}

struct SettingsScrollRequest: Equatable {
    let target: SettingsScrollTarget
    let token = UUID()
}

struct SettingsView: View {
    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @EnvironmentObject private var pro: ProPurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isEmbeddedInTab) private var isEmbeddedInTab

    fileprivate enum ActiveAlert: Identifiable {
        case logoutConfirmation
        case listenBrainzLogoutConfirmation
        case resetConfirmation
        case listeningHistoryScanResult(message: String)

        var id: String {
            switch self {
            case .logoutConfirmation:
                return "logoutConfirmation"
            case .listenBrainzLogoutConfirmation:
                return "listenBrainzLogoutConfirmation"
            case .resetConfirmation:
                return "resetConfirmation"
            case .listeningHistoryScanResult(let message):
                return "listeningHistoryScanResult-\(message)"
            }
        }
    }

    fileprivate enum SettingsRoute: Hashable {
        case scrobbleControls
        case listeningHistory
        case theme
        case liveActivity
        case account
        case about
        case advanced

        case appStorage
        case icloudSync
        case appleMusicAPI
        case debug
        case help
        case removeBracketsFromSongTitles
        case removeBracketsFromAlbumTitles
        case textReplacement
        case firstArtistOnly
        case proUpgrade
        case scanButtonLocation
    }

    @State private var activeAlert: ActiveAlert?
    @State private var isSigningInToLastFM = false
    @State private var lastFMLoginErrorText: String?
    @State private var isScanningListeningHistory = false
    @State private var isShowingListenBrainzConnectSheet = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingListeningHistoryReview = false
    @State private var navigationPath = NavigationPath()

    var isShowingSetup: Binding<Bool>?
    let scrollRequest: Binding<SettingsScrollRequest?>

    init(
        isShowingSetup: Binding<Bool>? = nil,
        scrollRequest: Binding<SettingsScrollRequest?> = .constant(nil)
    ) {
        self.isShowingSetup = isShowingSetup
        self.scrollRequest = scrollRequest
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { proxy in
                settingsRootContent
                    .navigationDestination(for: SettingsRoute.self) { route in
                        switch route {
                        case .scrobbleControls:
                            ScrobbleControlsSettingsPage()
                        case .listeningHistory:
                            ListeningHistorySettingsPage(
                                activeAlert: $activeAlert,
                                isScanningListeningHistory: $isScanningListeningHistory,
                                isShowingListeningHistoryReview: $isShowingListeningHistoryReview
                            )
                        case .theme:
                            ThemeSettingsPage()
                        case .liveActivity:
                            LiveActivitySettingsPage()
                        case .account:
                            AccountSettingsPage(
                                activeAlert: $activeAlert,
                                isSigningInToLastFM: $isSigningInToLastFM,
                                lastFMLoginErrorText: $lastFMLoginErrorText,
                                isShowingListenBrainzConnectSheet: $isShowingListenBrainzConnectSheet
                            )
                        case .about:
                            AboutSettingsPage(isShowingWhatsNew: $isShowingWhatsNew)
                        case .advanced:
                            AdvancedSettingsPage(activeAlert: $activeAlert)
                        case .appStorage:
                            AppStorageSettingsPage()
                        case .icloudSync:
                            ICloudSyncSettingsPage()
                        case .appleMusicAPI:
                            AppleMusicAPISettingsPage()
                        case .debug:
                            DebugSettingsPage(isShowingSetup: isShowingSetup)
                        case .help:
                            SetupHelpView(mode: .help) {}
                        case .removeBracketsFromSongTitles:
                            RemoveBracketsSettingsPage(target: .songTitles)
                        case .removeBracketsFromAlbumTitles:
                            RemoveBracketsSettingsPage(target: .albumTitles)
                        case .textReplacement:
                            TextReplacementSettingsPage()
                        case .firstArtistOnly:
                            FirstArtistOnlySettingsPage()
                        case .proUpgrade:
                            ProUpgradeView()
                        case .scanButtonLocation:
                            ScanButtonLocationSettingsPage()
                        }
                    }
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if !isEmbeddedInTab {
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
                    }
                    .task(id: scrollRequest.wrappedValue?.token) {
                        guard let scrollRequest = scrollRequest.wrappedValue else { return }
                        await Task.yield()
                        if scrollRequest.target == .listeningHistory {
                            navigationPath.append(SettingsRoute.listeningHistory)
                        }
                        self.scrollRequest.wrappedValue = nil
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHelp)) { _ in
            navigationPath = NavigationPath([SettingsRoute.help])
        }
        .task {
            await auth.refreshUserInfoIfNeeded()
            await listenBrainzAuth.refreshUserInfoIfNeeded()
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
            case .listenBrainzLogoutConfirmation:
                Alert(
                    title: Text(localized("Sign Out of ListenBrainz?")),
                    message: Text(localized("You'll need to enter your token again to scrobble.")),
                    primaryButton: .destructive(Text(localized("Sign Out")), action: performListenBrainzLogout),
                    secondaryButton: .cancel(Text(localized("Cancel")))
                )
            case .resetConfirmation:
                Alert(
                    title: Text(localized("Reset Settings?")),
                    message: Text(localized("This resets settings back to their initial values (your Last.fm and ListenBrainz accounts stay connected).")),
                    primaryButton: .destructive(Text(localized("Reset")), action: resetToInitialSettings),
                    secondaryButton: .cancel(Text(localized("Cancel")))
                )
            case .listeningHistoryScanResult(let message):
                Alert(
                    title: Text(localized("Listening History")),
                    message: Text(message),
                    dismissButton: .default(Text(localized("OK")))
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
        .fullScreenCover(isPresented: $isShowingWhatsNew) {
            WhatsNewView {
                isShowingWhatsNew = false
            }
        }
        .sheet(isPresented: $isShowingListeningHistoryReview) {
            ListeningHistoryReviewView {
                scrobbleLog.reload()
                engine.start()
            }
            .environmentObject(auth)
            .environmentObject(scrobbleLog)
        }
        .sheet(isPresented: $isShowingListenBrainzConnectSheet) {
            ListenBrainzConnectSheet()
                .environmentObject(listenBrainzAuth)
        }
    }

    @ViewBuilder
    private var settingsRootContent: some View {
        Form {
            Section {
                if pro.isPro {
                    NavigationLink(value: SettingsRoute.proUpgrade) {
                        Label {
                            Text("View Pro features")
                        } icon: {
                            SettingsIconBadge(systemImage: "star.square.fill", backgroundColor: proYellow, foregroundColor: .black, iconSize: 14)
                        }
                    }
                } else {
                    proUpgradeBannerRow
                }

                NavigationLink(value: SettingsRoute.help) {
                    Label {
                        Text("Help")
                    } icon: {
                        SettingsIconBadge(systemImage: "questionmark.circle", backgroundColor: .blue)
                    }
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.scrobbleControls) {
                    Label {
                        Text("Scrobble Controls")
                    } icon: {
                        SettingsIconBadge(systemImage: "slider.horizontal.3", backgroundColor: darkOrange)
                    }
                }

                NavigationLink(value: SettingsRoute.listeningHistory) {
                    Label {
                        Text("Listening History")
                    } icon: {
                        SettingsIconBadge(systemImage: "clock.arrow.circlepath", backgroundColor: scrobbleNowPurple)
                    }
                }
                .id(SettingsScrollTarget.listeningHistory.anchorID)

                NavigationLink(value: SettingsRoute.theme) {
                    Label {
                        Text("Theme")
                    } icon: {
                        SettingsIconBadge(systemImage: "circle.lefthalf.filled", backgroundColor: .black)
                    }
                }

                NavigationLink(value: SettingsRoute.liveActivity) {
                    Label {
                        Text("Live Activity")
                    } icon: {
                        SettingsIconBadge(systemImage: "clock.badge", backgroundColor: .blue)
                    }
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.account) {
                    Label {
                        Text("Account")
                    } icon: {
                        SettingsIconBadge(systemImage: "person.circle", backgroundColor: Color.accentColor)
                    }
                }

                NavigationLink(value: SettingsRoute.about) {
                    Label {
                        Text("About")
                    } icon: {
                        SettingsIconBadge(systemImage: "info.circle", backgroundColor: Color(white: 0.45))
                    }
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.advanced) {
                    Label {
                        Text("Advanced")
                    } icon: {
                        SettingsIconBadge(systemImage: "gearshape", backgroundColor: Color(white: 0.22))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var proUpgradeBannerRow: some View {
        Button {
            navigationPath.append(SettingsRoute.proUpgrade)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.square.fill")
                Text("Upgrade to Pro")
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(proYellow)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func performLogout() {
        auth.disconnect()
        engine.setUserPaused(false)
        engine.stop()
    }

    private func performListenBrainzLogout() {
        listenBrainzAuth.disconnect()
    }

    private func resetToInitialSettings() {
        UserDefaults.standard.removeObject(forKey: LiveActivityManager.enabledDefaultsKey)
        UserDefaults.standard.removeObject(forKey: LiveActivityManager.compactModeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.themeSelection)
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.buttonThemeSelection)
        Task { @MainActor in
            await LiveActivityManager.shared.stop()
        }

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
        defaults.removeObject(forKey: AppSettings.Keys.scrobbleAppleMusicAPIEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
        defaults.removeObject(forKey: AppSettings.Keys.extendedListeningHistoryScanEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.listeningHistoryRequireConfirmationEnabled)
        defaults.removeObject(forKey: AppSettings.Keys.listeningHistoryResumeRecoveryCutoffDate)
        defaults.removeObject(forKey: AppSettings.Keys.sendNowPlayingAutomaticallyEnabled)
        defaults.removeObject(forKey: ProSettings.Keys.textReplacementRules)
        AppleMusicRecentTracksImporter.shared.resetState()
        ListeningHistoryReviewStore.shared.clear()
    }
}

private struct ScrobbleControlsSettingsPage: View {
    private static let iosLockedProNavigationBadgeTrailingInset: CGFloat = 24
    private static let iosLockedProToggleBadgeTrailingInset: CGFloat = 75

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    @AppStorage(ProSettings.Keys.loveOnFavoriteEnabled, store: AppGroup.userDefaults) private var loveOnFavoriteEnabled = false
    @AppStorage(ProSettings.Keys.scrobbleThresholdIndex, store: AppGroup.userDefaults) private var scrobbleThresholdIndex = ProSettings.defaultScrobbleThresholdIndex
    @AppStorage(ProSettings.Keys.useAlbumArtistForScrobbling, store: AppGroup.userDefaults) private var useAlbumArtistForScrobbling = false
    @AppStorage(ProSettings.Keys.preventDuplicateScrobblesEnabled, store: AppGroup.userDefaults) private var preventDuplicateScrobblesEnabled = true
    @AppStorage(AppSettings.Keys.sendNowPlayingAutomaticallyEnabled, store: AppGroup.userDefaults) private var sendNowPlayingAutomaticallyEnabled = true

    @EnvironmentObject private var pro: ProPurchaseManager

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Prevent duplicate scrobbles", isOn: $preventDuplicateScrobblesEnabled)
                    Text("Avoids sending the same playback session more than once within a short time window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Send Now Playing status", isOn: $sendNowPlayingAutomaticallyEnabled)
                    Text("Display the currently playing track on your connected profile. Automatic scrobbles still work when this is off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                scrobbleThresholdSlider()
                removeBracketsNavigationLink(target: .songTitles)
                removeBracketsNavigationLink(target: .albumTitles)
                textReplacementNavigationLink
                Toggle(isOn: proLockedBoolBinding($loveOnFavoriteEnabled, unlockedDefault: false)) {
                    HStack {
                        Text("Love Apple Music favourites on Last.fm")
                            .foregroundStyle(pro.isPro ? .primary : .secondary)
                        Spacer()
                        proFeatureBadgePlaceholder
                    }
                }
                .disabled(!pro.isPro)
                .tint(proYellow)
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
                .tint(proYellow)
                .overlay(alignment: .trailing) {
                    lockedProBadgeOverlay(trailingInset: Self.iosLockedProToggleBadgeTrailingInset)
                }
                firstArtistOnlyNavigationLink
            }
        }
        .navigationTitle("Scrobble Controls")
        .navigationBarTitleDisplayMode(.inline)
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
            Slider(value: sliderValue, in: 0...Double(ProSettings.scrobbleThresholdOptions.count - 1), step: 1) {
                Text(localized("Scrobble threshold"))
            }
            .disabled(!pro.isPro)
            .tint(proYellow)
            .frame(maxWidth: .infinity)
            HStack {
                Text(localized("10%"))
                Spacer()
                Text(localized("25%"))
                Spacer()
                Text(localized("50%"))
                Spacer()
                Text(localized("75%"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func removeBracketsNavigationLink(target: RemoveBracketsSettingsPage.Target) -> some View {
        let route: SettingsView.SettingsRoute
        let iconName: String
        switch target {
        case .songTitles:
            route = .removeBracketsFromSongTitles
            iconName = "parentheses"
        case .albumTitles:
            route = .removeBracketsFromAlbumTitles
            iconName = "parentheses"
        }
        return NavigationLink(value: route) {
            Label {
                HStack {
                    Text(target.settingsLabel)
                    Spacer()
                    proFeatureBadgePlaceholder
                }
            } icon: {
                SettingsIconBadge(systemImage: iconName, backgroundColor: .black, iconSize: 11)
            }
        }
        .overlay(alignment: .trailing) {
            lockedProBadgeOverlay(trailingInset: Self.iosLockedProNavigationBadgeTrailingInset)
        }
    }

    @ViewBuilder
    private var textReplacementNavigationLink: some View {
        NavigationLink(value: SettingsView.SettingsRoute.textReplacement) {
            Label {
                HStack {
                    Text(localized("Text replacement"))
                        .foregroundStyle(pro.isPro ? .primary : .secondary)
                    Spacer()
                    proFeatureBadgePlaceholder
                }
            } icon: {
                SettingsIconBadge(systemImage: "character.textbox", backgroundColor: .black, iconSize: 11)
            }
        }
        .disabled(!pro.isPro)
        .overlay(alignment: .trailing) {
            lockedProBadgeOverlay(trailingInset: Self.iosLockedProNavigationBadgeTrailingInset)
        }
    }

    @ViewBuilder
    private var firstArtistOnlyNavigationLink: some View {
        NavigationLink(value: SettingsView.SettingsRoute.firstArtistOnly) {
            Label {
                HStack {
                    Text(localized("Scrobble only the first credited artist"))
                    Spacer()
                    proFeatureBadgePlaceholder
                }
            } icon: {
                SettingsIconBadge(systemImage: "person.fill", backgroundColor: .black, iconSize: 11)
            }
        }
        .overlay(alignment: .trailing) {
            lockedProBadgeOverlay(trailingInset: Self.iosLockedProNavigationBadgeTrailingInset)
        }
    }

    @ViewBuilder
    private var lockedProInlineBadge: some View {
        if !pro.isPro {
            ProFeatureBadge()
        }
    }

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

    private func proLockedBoolBinding(_ storage: Binding<Bool>, unlockedDefault: Bool) -> Binding<Bool> {
        Binding(
            get: { pro.isPro ? storage.wrappedValue : unlockedDefault },
            set: { newValue in
                guard pro.isPro else { return }
                storage.wrappedValue = newValue
            }
        )
    }
}

private struct ListeningHistorySettingsPage: View {
    @AppStorage(AppSettings.Keys.extendedListeningHistoryScanEnabled, store: AppGroup.userDefaults) private var extendedListeningHistoryScanEnabled = false
    @AppStorage(AppSettings.Keys.listeningHistoryRequireConfirmationEnabled, store: AppGroup.userDefaults) private var listeningHistoryRequireConfirmationEnabled = true

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager

    @Binding var activeAlert: SettingsView.ActiveAlert?
    @Binding var isScanningListeningHistory: Bool
    @Binding var isShowingListeningHistoryReview: Bool

    private var hasAnyAccount: Bool {
        auth.sessionKey != nil || listenBrainzAuth.isConnected
    }

    private var autoScrobbleListeningHistoryBinding: Binding<Bool> {
        Binding(
            get: { !listeningHistoryRequireConfirmationEnabled },
            set: { isEnabled in
                let requireConfirmation = !isEnabled
                guard listeningHistoryRequireConfirmationEnabled != requireConfirmation else { return }
                listeningHistoryRequireConfirmationEnabled = requireConfirmation
                Task {
                    if isEnabled { isScanningListeningHistory = true }
                    defer { if isEnabled { isScanningListeningHistory = false } }
                    await AppModel.shared.handleListeningHistoryRequireConfirmationChanged(isEnabled: requireConfirmation)
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await scanListeningHistoryTapped() }
                } label: {
                    Label {
                        Text(isScanningListeningHistory ? NSLocalizedString("Scanning…", comment: "") : NSLocalizedString("Scan Listening History", comment: ""))
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(hasAnyAccount ? .primary : .secondary)
                }
                .padding(.vertical, 8)
                .disabled(!hasAnyAccount || isScanningListeningHistory)

                Text(
                    listeningHistoryRequireConfirmationEnabled
                        ? (
                            extendedListeningHistoryScanEnabled
                                ? NSLocalizedString("Scan Listening History will add plays from the past 7 days to the review list.", comment: "")
                                : NSLocalizedString("Scan Listening History will add plays from the past 36 hours to the review list.", comment: "")
                        )
                        : (
                            extendedListeningHistoryScanEnabled
                                ? NSLocalizedString("Scan Listening History will import plays from the past 7 days.", comment: "")
                                : NSLocalizedString("Scan Listening History will import plays from the past 36 hours.", comment: "")
                        )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink(value: SettingsView.SettingsRoute.appleMusicAPI) {
                    Label {
                        Text(NSLocalizedString("Scrobble Recently Played from Apple Music API", comment: ""))
                    } icon: {
                        SettingsIconBadge(systemImage: "music.note", backgroundColor: Color.accentColor)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Auto-scrobble Listening History", isOn: autoScrobbleListeningHistoryBinding)
                        .tint(Color.accentColor)
                    Text("When on, scans submit plays automatically. When off, scans add items to a review list in Home instead. This also applies to Recently Played API songs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Extended History Scan", isOn: $extendedListeningHistoryScanEnabled)
                    Text("When off, \"Scan Listening History\" checks the past 36 hours. When on, \"Scan Listening History\" checks the past 7 days.\n\nAutomatic scans always check the past 36 hours and only run when \"Auto-scrobble Listening History\" is on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink(value: SettingsView.SettingsRoute.scanButtonLocation) {
                    Text("Scan History Shortcut")
                }
            }
        }
        .navigationTitle("Listening History")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func scanListeningHistoryTapped() async {
        guard auth.sessionKey != nil || listenBrainzAuth.isConnected else { return }
        guard !isScanningListeningHistory else { return }
        isScanningListeningHistory = true
        defer { isScanningListeningHistory = false }

        let result = await AppModel.shared.runUserInitiatedListeningHistoryScan(
            allowExtendedLookback: true,
            allowSubmissionWhilePaused: true,
            bypassRecentTrackCooldown: true
        )
        if result.requiresConfirmation, result.pendingReviewCount > 0 {
            isShowingListeningHistoryReview = true
        } else {
            activeAlert = .listeningHistoryScanResult(
                message: listeningHistoryScanMessage(for: result)
            )
        }
    }
}

private struct ThemeSettingsPage: View {
    @AppStorage(AppSettings.Keys.themeSelection) private var themeSelectionRawValue = AppTheme.system.rawValue
    @AppStorage(AppSettings.Keys.buttonThemeSelection) private var buttonThemeSelectionRawValue = ButtonTheme.colorful.rawValue

    var body: some View {
        Form {
            Section {
                Picker("App Theme", selection: $themeSelectionRawValue) {
                    Text("System").tag(AppTheme.system.rawValue)
                    Text("Light").tag(AppTheme.light.rawValue)
                    Text("Dark").tag(AppTheme.dark.rawValue)
                }

                Picker("Button Theme", selection: $buttonThemeSelectionRawValue) {
                    Text("Colourful").tag(ButtonTheme.colorful.rawValue)
                    Text("Monochrome").tag(ButtonTheme.monochrome.rawValue)
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LiveActivitySettingsPage: View {
    @AppStorage(LiveActivityManager.enabledDefaultsKey) private var liveActivityEnabled = false
    @AppStorage(LiveActivityManager.compactModeDefaultsKey) private var liveActivityCompactModeEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Show Live Activity", isOn: $liveActivityEnabled)
                    .onValueChange(of: liveActivityEnabled) { isEnabled in
                        if isEnabled {
                            Task { @MainActor in
                                await LiveActivityManager.shared.startIfPossible()
                            }
                        } else {
                            Task { @MainActor in
                                await LiveActivityManager.shared.stop()
                            }
                        }
                    }

                Picker("Live Activity Size", selection: $liveActivityCompactModeEnabled) {
                    Text("Default").tag(false)
                    Text("Compact").tag(true)
                }
                .disabled(!liveActivityEnabled)
                .allowsHitTesting(liveActivityEnabled)
                .opacity(liveActivityEnabled ? 1.0 : 0.5)
                .onValueChange(of: liveActivityCompactModeEnabled) { _ in
                    LiveActivityManager.shared.refreshActiveActivity()
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
        }
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountSettingsPage: View {
    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @Environment(\.openURL) private var openURL

    @Binding var activeAlert: SettingsView.ActiveAlert?
    @Binding var isSigningInToLastFM: Bool
    @Binding var lastFMLoginErrorText: String?
    @Binding var isShowingListenBrainzConnectSheet: Bool

    var body: some View {
        Form {
            Section("Last.fm Account") {
                HStack {
                    Text("Last.fm")
                    Spacer()
                    if auth.sessionKey != nil {
                        Text("Signed in")
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
                    Label {
                        Text("View Profile")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "person.circle")
                    }
                    .foregroundStyle(canViewProfile ? Color.accentColor : .secondary)
                }
                .disabled(!canViewProfile)

                if auth.sessionKey != nil {
                    Button {
                        activeAlert = .logoutConfirmation
                    } label: {
                        Label {
                            Text("Sign Out")
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "power")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Button {
                        Task { await connectTapped() }
                    } label: {
                        Label {
                            Text(isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In", comment: ""))
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .disabled(isSigningInToLastFM)
                }
            }

            Section(header: Text("ListenBrainz Account"), footer: Text("ListenBrainz support is currently in beta.").foregroundStyle(.secondary)) {
                HStack {
                    Text("ListenBrainz")
                    Spacer()
                    if listenBrainzAuth.isConnected {
                        Text("Signed in")
                            .foregroundColor(.green)
                    } else {
                        Text("Not connected")
                            .foregroundColor(.secondary)
                    }
                }

                if listenBrainzAuth.isConnected {
                    if let username = listenBrainzAuth.username {
                        HStack {
                            Text("Username")
                            Spacer()
                            Text(username)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    let canViewProfile = listenBrainzAuth.profileURL != nil
                    Button {
                        if let url = listenBrainzAuth.freshProfileURL() {
                            openURL(url)
                        }
                    } label: {
                        Label {
                            Text("View Profile")
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "person.circle")
                        }
                        .foregroundStyle(canViewProfile ? Color.accentColor : .secondary)
                    }
                    .disabled(!canViewProfile)

                    Button {
                        activeAlert = .listenBrainzLogoutConfirmation
                    } label: {
                        Label {
                            Text("Sign Out")
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "power")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Button {
                        isShowingListenBrainzConnectSheet = true
                    } label: {
                        Label {
                            Text("Connect ListenBrainz")
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "waveform.path.ecg")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct AboutSettingsPage: View {
    private static let repositoryURL = URL(string: "https://github.com/kevinlim512/FastScrobbler")!
    private static let redditURL = URL(string: "https://www.reddit.com/r/FastScrobbler/")!
    private static let redditSubmitURL = URL(string: "https://www.reddit.com/r/FastScrobbler/submit")!
    private static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6759501541?action=write-review")!
    private static let privacyPolicyURL = URL(string: "https://github.com/kevinlim512/FastScrobbler/blob/main/PRIVACY_POLICY.md")!

    @Environment(\.openURL) private var openURL
    @Binding var isShowingWhatsNew: Bool

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "7.0"
        return String.localizedStringWithFormat(NSLocalizedString("Version %@", comment: ""), version)
    }

    var body: some View {
        Form {
            Section("Links") {
                Button {
                    openURL(Self.redditURL)
                } label: {
                    Label {
                        Text("r/FastScrobbler")
                            .fontWeight(.medium)
                    } icon: {
                        SettingsBrandIconBadge(imageName: "reddit_logo", backgroundColor: Color(red: 1.0, green: 0.27, blue: 0.0), iconSize: 18)
                    }
                }

                Button {
                    openURL(Self.redditSubmitURL)
                } label: {
                    Label {
                        Text("Ask a Question or Report a Bug")
                            .fontWeight(.medium)
                    } icon: {
                        SettingsIconBadge(systemImage: "questionmark.bubble.fill", backgroundColor: .blue)
                    }
                }

                Button {
                    openURL(Self.writeReviewURL)
                } label: {
                    Label {
                        Text("Rate FastScrobbler")
                            .fontWeight(.medium)
                    } icon: {
                        SettingsIconBadge(systemImage: "star.bubble.fill", backgroundColor: .orange)
                    }
                }

                Button {
                    openURL(Self.repositoryURL)
                } label: {
                    Label {
                        Text("GitHub")
                            .fontWeight(.medium)
                    } icon: {
                        SettingsBrandIconBadge(imageName: "github_logo", backgroundColor: Color(white: 0.2), iconSize: 18)
                    }
                }
            }

            Section("Legal") {
                Button {
                    openURL(Self.privacyPolicyURL)
                } label: {
                    Label {
                        Text("Privacy Policy")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }

            Section {
                Button {
                    isShowingWhatsNew = true
                } label: {
                    HStack {
                        Label {
                            Text("What's New")
                        } icon: {
                            SettingsIconBadge(systemImage: "sparkles", backgroundColor: .purple)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text(appVersionString)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdvancedSettingsPage: View {
    @Binding var activeAlert: SettingsView.ActiveAlert?

    var body: some View {
        Form {
            Section {
                NavigationLink(value: SettingsView.SettingsRoute.icloudSync) {
                    Label {
                        Text("iCloud Sync")
                    } icon: {
                        SettingsIconBadge(systemImage: "icloud.fill", backgroundColor: .blue)
                    }
                }

                NavigationLink(value: SettingsView.SettingsRoute.appStorage) {
                    Label {
                        Text("App Storage")
                    } icon: {
                        SettingsIconBadge(systemImage: "externaldrive.fill", backgroundColor: .gray)
                    }
                }
            }

            Section {
                Button {
                    activeAlert = .resetConfirmation
                } label: {
                    Label {
                        Text("Reset Settings")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ICloudSyncSettingsPage: View {
    @ObservedObject private var iCloudSync = ICloudSyncCoordinator.shared
    @State private var isConfirmingICloudDeletion = false
    @State private var alertMessage: String?

    private var canDeleteICloudData: Bool {
        !iCloudSync.isBusy && (iCloudSync.isSyncEnabled || iCloudSync.hasCloudData)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { iCloudSync.isSyncEnabled },
                    set: { newValue in
                        Task { await setICloudSyncEnabled(newValue) }
                    }
                )) {
                    Text(localized("Sync with iCloud"))
                }
                .disabled(iCloudSync.isBusy || (!iCloudSync.isICloudAvailable && !iCloudSync.isSyncEnabled))

                Button {
                    isConfirmingICloudDeletion = true
                } label: {
                    Label(localized("Delete iCloud Data"), systemImage: "trash")
                        .fontWeight(.medium)
                        .foregroundStyle(canDeleteICloudData ? Color.accentColor : .secondary)
                }
                .disabled(!canDeleteICloudData)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Back up your FastScrobbler data to iCloud and keep it synced across your devices."))

                    if !iCloudSync.isICloudAvailable {
                        Text(localized("iCloud is currently unavailable on this device."))
                    } else if iCloudSync.isBusy {
                        Text(localized("Working…"))
                    } else if let error = iCloudSync.lastErrorMessage, !error.isEmpty {
                        Text(error)
                    } else if let status = iCloudSync.statusMessage, !status.isEmpty {
                        Text(status)
                    }
                }
            }
        }
        .navigationTitle(localized("iCloud Sync"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await iCloudSync.refreshStatus()
        }
        .alert(localized("iCloud Sync"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )) {
            Button(localized("OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert(localized("Delete iCloud Data?"), isPresented: $isConfirmingICloudDeletion) {
            Button(localized("Delete iCloud Data"), role: .destructive) {
                Task { await deleteICloudDataTapped() }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(localized("This removes only the iCloud copy of your synced FastScrobbler data. Local data on this iPhone stays intact, and iCloud sync will be turned off here."))
        }
    }

    @MainActor
    private func setICloudSyncEnabled(_ isEnabled: Bool) async {
        if isEnabled {
            do {
                try await iCloudSync.enableSync()
            } catch {
                alertMessage = error.localizedDescription
            }
        } else {
            await iCloudSync.disableSync()
        }
    }

    @MainActor
    private func deleteICloudDataTapped() async {
        do {
            try await iCloudSync.deleteCloudData()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct AppStorageSettingsPage: View {
    @State private var isRunningStorageMaintenance = false
    @State private var storageUsageSnapshot: StorageUsageSnapshot?
    @State private var storageMaintenanceAlertMessage: String?
    @State private var isDebugUnlocked = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await runStorageMaintenanceTapped() }
                } label: {
                    Label(
                        isRunningStorageMaintenance ? localized("Cleaning Up…") : localized("Trim Local Storage"),
                        systemImage: "externaldrive.badge.timemachine"
                    )
                    .fontWeight(.medium)
                    .foregroundStyle(isRunningStorageMaintenance ? .secondary : Color.accentColor)
                }
                .disabled(isRunningStorageMaintenance)
            }

            Section {
                storageUsageRow(title: "Backlog items", value: storageUsageSnapshot.map { "\($0.backlogCount)" })
                storageUsageRow(title: "Backlog storage", value: storageUsageSnapshot.map { byteCountText($0.backlogBytes) })
                storageUsageRow(title: "Scrobble log entries", value: storageUsageSnapshot.map { "\($0.scrobbleLogCount)" })
                storageUsageRow(title: "Scrobble log storage", value: storageUsageSnapshot.map { byteCountText($0.scrobbleLogBytes) })
                storageUsageRow(title: "Listening history state", value: storageUsageSnapshot.map { byteCountText($0.playbackHistoryStateBytes) })
                storageUsageRow(
                    title: "Recent tracks state",
                    value: storageUsageSnapshot.map { byteCountText($0.recentTracksStateBytes) }
                ) {
                    isDebugUnlocked = true
                }
            } footer: {
                Text(localized("FastScrobbler stores these data to optimise your scrobbling experience. FastScrobbler does NOT store these for data collection purposes."))
            }

            if isDebugUnlocked {
                Section {
                    NavigationLink(value: SettingsView.SettingsRoute.debug) {
                        Text("Debug")
                    }
                }
            }
        }
        .navigationTitle(localized("App Storage"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStorageUsageSnapshot()
        }
        .alert(localized("App Storage"), isPresented: Binding(
            get: { storageMaintenanceAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    storageMaintenanceAlertMessage = nil
                }
            }
        )) {
            Button(localized("OK"), role: .cancel) {}
        } message: {
            Text(storageMaintenanceAlertMessage ?? "")
        }
    }

    @MainActor
    private func runStorageMaintenanceTapped() async {
        guard !isRunningStorageMaintenance else { return }
        isRunningStorageMaintenance = true
        defer { isRunningStorageMaintenance = false }

        await AppModel.shared.runStorageMaintenanceNow()
        await refreshStorageUsageSnapshot()
        storageMaintenanceAlertMessage = localized("Local storage cleanup finished.")
    }

    @MainActor
    private func refreshStorageUsageSnapshot() async {
        storageUsageSnapshot = await AppModel.shared.collectStorageUsageSnapshot()
    }

    private func storageUsageRow(title: String, value: String?, titleTapAction: (() -> Void)? = nil) -> some View {
        HStack {
            if let titleTapAction {
                Text(localized(title))
                    .onTapGesture(count: 3, perform: titleTapAction)
            } else {
                Text(localized(title))
            }
            Spacer()
            Text(value ?? localized("Loading…"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

private struct DebugSettingsPage: View {
    let isShowingSetup: Binding<Bool>?

    var body: some View {
        Form {
            Section {
                if let isShowingSetup {
                    Button("Show Setup") {
                        isShowingSetup.wrappedValue = true
                    }
                }

                Button {
                    fatalError("Crashlytics test crash")
                }
                label: {
                    Text("Test Crashlytics")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProFeatureBadge: View {
    var body: some View {
        Text("Pro")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(proYellow)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Pro")
    }
}

struct ScanButtonLocationSettingsPage: View {
    @AppStorage(AppSettings.Keys.scanButtonLocation) private var scanButtonLocationRawValue = ScanButtonLocation.recentScrobbles.rawValue

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        Form {
            Section {
                ForEach(ScanButtonLocation.allCases) { location in
                    Button {
                        scanButtonLocationRawValue = location.rawValue
                    } label: {
                        HStack {
                            Text(location.localizedName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if scanButtonLocationRawValue == location.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(localized("Choose where to display the \"Scan Listening History\" shortcut button, or disable it."))
            }
        }
        .navigationTitle(localized("Scan History Shortcut"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
