#if canImport(MediaPlayer)
import MediaPlayer
#endif
import SwiftUI

struct ContentView: View {
    private enum Keys {
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    private enum Layout {
        static let sectionSpacing: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let contentPadding: CGFloat = MacFloatingBarLayout.contentHorizontalPadding
        static let controlsSpacing: CGFloat = 10
        static let controlsTopPadding: CGFloat = 4
        static let statusLineSpacing: CGFloat = 5
        static let trackCardSpacing: CGFloat = 8
        static let nowPlayingLineSpacing: CGFloat = 4
        static let progressTopPadding: CGFloat = 8
        static let logRowSpacing: CGFloat = 8
    }

    private enum ActionButtonPalette {
        static let cardBackgroundOverlay = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.96),
            dark: NSColor(white: 0.10, alpha: 0.86)
        )
        static let cardBorder = dynamicColor(
            light: NSColor(white: 0.0, alpha: 0.10),
            dark: NSColor(white: 1.0, alpha: 0.16)
        )
        static let resume = dynamicColor(
            light: NSColor(red: 0.22, green: 0.88, blue: 0.42, alpha: 1.0),
            dark: NSColor(red: 0.34, green: 0.96, blue: 0.53, alpha: 1.0)
        )
        static let resumeForeground = dynamicColor(
            light: NSColor(red: 0.10, green: 0.44, blue: 0.21, alpha: 1.0),
            dark: NSColor(red: 0.76, green: 0.95, blue: 0.81, alpha: 1.0)
        )
        static let resumeBorder = dynamicColor(
            light: NSColor(red: 0.00, green: 0.72, blue: 0.20, alpha: 1.0),
            dark: NSColor(red: 0.00, green: 0.84, blue: 0.31, alpha: 1.0)
        )
        static let resumeFill = dynamicColor(
            light: NSColor(red: 0.82, green: 0.94, blue: 0.85, alpha: 0.20),
            dark: NSColor(red: 0.16, green: 0.40, blue: 0.23, alpha: 0.30)
        )
        static let scrobbleNow = dynamicColor(
            light: NSColor(red: 0.73, green: 0.42, blue: 0.82, alpha: 1.0),
            dark: NSColor(red: 0.79, green: 0.52, blue: 0.86, alpha: 1.0)
        )
        static let scrobbleNowForeground = dynamicColor(
            light: NSColor(red: 0.42, green: 0.27, blue: 0.49, alpha: 1.0),
            dark: NSColor(red: 0.88, green: 0.82, blue: 0.93, alpha: 1.0)
        )
        static let scrobbleNowBorder = dynamicColor(
            light: NSColor(red: 0.58, green: 0.28, blue: 0.72, alpha: 1.0),
            dark: NSColor(red: 0.66, green: 0.36, blue: 0.78, alpha: 1.0)
        )
        static let scrobbleNowFill = dynamicColor(
            light: NSColor(red: 0.90, green: 0.84, blue: 0.94, alpha: 0.18),
            dark: NSColor(red: 0.38, green: 0.28, blue: 0.48, alpha: 0.28)
        )
        static let account = dynamicColor(
            light: NSColor(red: 0.34, green: 0.62, blue: 0.86, alpha: 1.0),
            dark: NSColor(red: 0.42, green: 0.70, blue: 0.90, alpha: 1.0)
        )
        static let accountForeground = dynamicColor(
            light: NSColor(red: 0.21, green: 0.34, blue: 0.50, alpha: 1.0),
            dark: NSColor(red: 0.80, green: 0.89, blue: 0.96, alpha: 1.0)
        )
        static let monochromeForeground = dynamicColor(
            light: NSColor(white: 0.0, alpha: 1.0),
            dark: NSColor(white: 1.0, alpha: 1.0)
        )
        static let monochromeFill = dynamicColor(
            light: NSColor(white: 0.62, alpha: 1.0),
            dark: NSColor(white: 0.52, alpha: 1.0)
        )
        static let monochromeDisabledFill = dynamicColor(
            light: NSColor(white: 0.72, alpha: 1.0),
            dark: NSColor(white: 0.42, alpha: 1.0)
        )
        static let accountBorder = dynamicColor(
            light: NSColor(red: 0.24, green: 0.48, blue: 0.72, alpha: 1.0),
            dark: NSColor(red: 0.30, green: 0.56, blue: 0.78, alpha: 1.0)
        )
        static let accountFill = dynamicColor(
            light: NSColor(red: 0.84, green: 0.90, blue: 0.96, alpha: 0.18),
            dark: NSColor(red: 0.22, green: 0.34, blue: 0.48, alpha: 0.28)
        )
        static let manualForeground = dynamicColor(
            light: NSColor(white: 0.08, alpha: 1.0),
            dark: NSColor(white: 0.92, alpha: 1.0)
        )
        static let manualFill = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.60),
            dark: NSColor(white: 0.16, alpha: 0.70)
        )
        static let disabledFill = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.52),
            dark: NSColor(white: 0.20, alpha: 0.64)
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

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @EnvironmentObject private var permissions: PermissionStatusStore
    @EnvironmentObject private var pro: ProPurchaseManager

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Keys.hasSeenSetup) private var hasSeenSetup = false
    @AppStorage(AppSettings.Keys.buttonThemeSelection) private var buttonThemeSelectionRawValue = ButtonTheme.colorful.rawValue

    @State private var lastScrobbleLogRefreshDate: Date = .distantPast
    @State private var errorText: String?
    private enum ListenBrainzConnectReturnTarget {
        case setup
        case help
        case settings
    }

    @State private var isShowingSetup = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingHelp = false
    @State private var isShowingSettings = false
    @State private var isShowingManualScrobble = false
    @State private var isShowingListenBrainzConnect = false
    @State private var listenBrainzConnectReturnTarget: ListenBrainzConnectReturnTarget = .settings

    var body: some View {
        Group {
            // NavigationStack avoids the two-column split layout NavigationView produces on macOS.
            NavigationStack {
                mainContent
            }
        }
        // scenePhase doesn't fire reliably for popover-style menu bar apps, so we refresh
        // permissions each time the popover is about to become visible instead.
        .onReceive(NotificationCenter.default.publisher(for: .fastScrobblerPopoverWillShow)) { _ in
            refreshScrobbleLogDisplay(now: .now, forceReload: true)
            refreshPermissionStatusesIfNeeded()
        }
        .onAppear {
            refreshScrobbleLogDisplay(now: .now, forceReload: true)
            refreshPermissionStatusesIfNeeded()
            presentWhatsNewIfNeeded()
        }
        .onValueChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshScrobbleLogDisplay(now: .now, forceReload: true)
            refreshPermissionStatusesIfNeeded()
            presentWhatsNewIfNeeded()
        }
        .onValueChange(of: observer.authorizationStatus) { _ in
            refreshPermissionStatusesIfNeeded()
        }
        .onValueChange(of: auth.sessionKey) { _ in
            presentSetupIfNeeded()
        }
        .onValueChange(of: listenBrainzAuth.isConnected) { _ in
            presentSetupIfNeeded()
        }
        .onValueChange(of: hasSeenSetup) { hasSeenSetup in
            guard hasSeenSetup else { return }
            presentWhatsNewIfNeeded()
        }
        .overlay {
            macModalOverlay
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    macAttentionBanner
                    controls
                    trackCard
                    statusCard
                    scrobbleLogCard
                    if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                .padding(Layout.contentPadding)
                .padding(.top, -8)
                .padding(.top, MacFloatingBarLayout.contentTopPadding) // room for the floating top buttons
                .animation(.easeInOut(duration: 0.3), value: observer.track)
                .animation(.easeInOut(duration: 0.3), value: auth.sessionKey != nil)
                .animation(.easeInOut(duration: 0.3), value: listenBrainzAuth.isConnected)
                .animation(.easeInOut(duration: 0.3), value: engine.statusText)
            }

            macPopoverTopButtons
                .padding(.top, MacFloatingBarLayout.topButtonsTopInset)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshScrobbleLogDisplay(now: .now)
        }
        .navigationTitle("")
        .toolbar {}
    }

    private var macPopoverTopButtons: some View {
        HStack(spacing: 10) {
            MacCapsuleControlButton(
                title: "Help",
                systemImage: "questionmark.circle",
                help: "Help",
                accessibilityLabel: "Help"
            ) {
                isShowingHelp = true
            }

            MacCapsuleControlButton(
                title: "Settings",
                systemImage: "gear",
                help: "Settings",
                accessibilityLabel: "Settings"
            ) {
                isShowingSettings = true
            }
        }
    }

    private var contentCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ActionButtonPalette.cardBackgroundOverlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ActionButtonPalette.cardBorder, lineWidth: 1)
            }
    }

    private var selectedButtonTheme: ButtonTheme {
        ButtonTheme(rawValue: buttonThemeSelectionRawValue) ?? .colorful
    }

    private var usesMonochromeButtons: Bool {
        selectedButtonTheme == .monochrome
    }

    private func actionButtonForeground(_ defaultColor: Color) -> Color {
        usesMonochromeButtons ? ActionButtonPalette.monochromeForeground : defaultColor
    }

    private func actionButtonTint(_ defaultColor: Color) -> Color {
        usesMonochromeButtons ? ActionButtonPalette.monochromeFill : defaultColor
    }

    private func actionButtonFill(_ defaultColor: Color, disabled: Bool = false) -> Color {
        if usesMonochromeButtons {
            return disabled ? ActionButtonPalette.monochromeDisabledFill : ActionButtonPalette.monochromeFill
        }
        return defaultColor
    }

    private func actionButtonBorder(_ defaultColor: Color, disabled: Bool = false) -> Color {
        if usesMonochromeButtons {
            return ActionButtonPalette.monochromeForeground.opacity(disabled ? 0.35 : 0.85)
        }
        return defaultColor
    }

    private var statusCard: some View {
        let hasLastFM = auth.sessionKey != nil
        let hasListenBrainz = listenBrainzAuth.isConnected

        return VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            if !hasLastFM && !hasListenBrainz {
                singleStatusCard(title: "Last.fm", isConnected: false)
                singleStatusCard(title: "ListenBrainz", isConnected: false)
            } else {
                if hasLastFM {
                    singleStatusCard(title: "Last.fm", isConnected: true)
                }
                if hasListenBrainz {
                    singleStatusCard(title: "ListenBrainz", isConnected: true)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasLastFM)
        .animation(.easeInOut(duration: 0.3), value: hasListenBrainz)
        .animation(.easeInOut(duration: 0.3), value: engine.statusText)
    }

    private func singleStatusCard(title: String, isConnected: Bool) -> some View {
        VStack(alignment: .leading, spacing: Layout.statusLineSpacing) {
            Text(title)
                .font(.title2.weight(.semibold))
            if isConnected {
                Text("Signed in")
                    .font(.footnote)
                    .foregroundColor(.green)
            } else {
                Text("Not connected")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            engineStatusText(engine.statusText)
                .font(.footnote)
            if let blocker = engine.autoScrobbleBlocker, (auth.sessionKey != nil || listenBrainzAuth.isConnected) {
                Text(blocker.statusText())
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(contentCardBackground)
    }

    private var trackCard: some View {
        VStack(alignment: .leading, spacing: Layout.trackCardSpacing) {
            HStack {
                Text("Now Playing")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            if let t = observer.track {
                nowPlayingMetadata(for: t)
                if let d = t.durationSeconds, d > 0 {
                    TrackPlaybackProgressView(track: t, engine: engine, formatTime: formatTime)
                        .padding(.top, Layout.progressTopPadding)
                } else if auth.sessionKey != nil || listenBrainzAuth.isConnected {
                    Text(NSLocalizedString("Auto-scrobble needs a stable playback duration and timestamp before it can submit automatically.", comment: ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text("No track detected.")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: observer.track)
        .animation(.easeInOut(duration: 0.3), value: observer.playbackState)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(contentCardBackground)
    }

    @ViewBuilder
    private func nowPlayingMetadata(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: Layout.nowPlayingLineSpacing) {
            Text(track.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.leading)

            Text(track.artist)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary.opacity(0.82))
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.leading)

            if let album = track.album, !album.isEmpty {
                Text(album)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        let actionButtonHeight: CGFloat = 32
        let actionButtonSpacing: CGFloat = Layout.controlsSpacing
        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected

        return VStack(spacing: Layout.controlsSpacing) {
            HStack(spacing: actionButtonSpacing) {
                Button {
                    engine.setUserPaused(!engine.isUserPaused)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engine.isUserPaused ? "play.fill" : "pause.fill")
                        Text(engine.isUserPaused ? NSLocalizedString("Resume", comment: "") : NSLocalizedString("Pause", comment: ""))
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(actionButtonForeground(engine.isUserPaused ? ActionButtonPalette.resumeForeground : ActionButtonPalette.scrobbleNowForeground))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .tint(actionButtonTint(engine.isUserPaused ? ActionButtonPalette.resume : ActionButtonPalette.scrobbleNow))
                .prominentButtonBackground(actionButtonFill(engine.isUserPaused ? ActionButtonPalette.resumeFill : ActionButtonPalette.scrobbleNowFill))
                .brightButtonBorder(actionButtonBorder(engine.isUserPaused ? ActionButtonPalette.resumeBorder : ActionButtonPalette.scrobbleNowBorder))
                .disabled(!hasAnyAccount)

                if !hasAnyAccount {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label(NSLocalizedString("Sign In", comment: ""), systemImage: "person.crop.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(actionButtonForeground(ActionButtonPalette.accountForeground))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.account))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.accountFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.accountBorder))
                } else {
                    Button {
                        Task { await engine.scrobbleNow(force: true) }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "memories.badge.plus")
                            Text(NSLocalizedString("Scrobble Now", comment: ""))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(actionButtonForeground(ActionButtonPalette.scrobbleNowForeground))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.scrobbleNow))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.scrobbleNowFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.scrobbleNowBorder))
                }
            }

            if hasAnyAccount {
                if auth.sessionKey != nil {
                    Button {
                        if let url = auth.freshProfileURL() {
                            openURL(url)
                        }
                    } label: {
                        Label(NSLocalizedString("View Profile in Last.fm", comment: ""), systemImage: "person.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(actionButtonForeground(ActionButtonPalette.accountForeground))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.account))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.accountFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.accountBorder))
                    .disabled(auth.profileURL == nil)
                }

                if listenBrainzAuth.isConnected {
                    Button {
                        if let url = listenBrainzAuth.freshProfileURL() {
                            openURL(url)
                        }
                    } label: {
                        Label(NSLocalizedString("View Profile in ListenBrainz", comment: ""), systemImage: "waveform.path.ecg")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(actionButtonForeground(ActionButtonPalette.accountForeground))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.account))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.accountFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.accountBorder))
                    .disabled(listenBrainzAuth.profileURL == nil)
                }

                Button {
                    isShowingManualScrobble = true
                } label: {
                    Label(NSLocalizedString("Manual Scrobble", comment: ""), systemImage: "plus.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ActionButtonPalette.manualForeground)
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .tint(.clear)
                .prominentButtonBackground(.clear)
                .brightButtonBorder(ActionButtonPalette.manualForeground, showsShadow: false)
            }
        }
        .padding(.top, Layout.controlsTopPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var macAttentionBanner: some View {
        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected
        let isLoggedOut = !hasAnyAccount
        let isMediaLibraryPermissionOff = (permissions.mediaLibraryStatus != .authorized)
        let isMusicControlPermissionOff = (permissions.automationStatus != .authorized)
        if isLoggedOut || isMediaLibraryPermissionOff || isMusicControlPermissionOff {
            VStack(alignment: .leading, spacing: 10) {
                if isLoggedOut {
                    Label(
                        "You're signed out of Last.fm and ListenBrainz.",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.subheadline.weight(.semibold))
                }

                if isMusicControlPermissionOff {
                    Label(
                        "Music control permission is off. Enable it in System Settings → Privacy & Security → Automation.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }

                if isMediaLibraryPermissionOff {
                    Label(
                        "Media Library permission is off. Request it here or enable it in System Settings → Privacy & Security.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }

                HStack(spacing: 10) {
                    if isLoggedOut {
                        Button("Sign In") {
                            isShowingSettings = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    if permissions.mediaLibraryStatus == .notDetermined {
                        Button("Request Media Library Access") {
                            Task { @MainActor in
                                let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { cont in
                                    MPMediaLibrary.requestAuthorization { s in
                                        cont.resume(returning: s)
                                    }
                                }
                                await permissions.refreshNow(observer: observer)
                                guard status == .authorized else { return }
                                AppModel.shared.startIfNeeded()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    } else if permissions.mediaLibraryStatus == .denied || permissions.mediaLibraryStatus == .restricted {
                        Button(NSLocalizedString("Open System Settings", comment: "")) {
                            if let mediaSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                                openURL(mediaSettingsURL)
                            } else if let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                                openURL(privacySettingsURL)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    if isMusicControlPermissionOff {
                        Button(musicControlActionTitle) {
                            handleMusicControlPermissionAction()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private var scrobbleLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scrobbles")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            if scrobbleLog.entries.isEmpty {
                Text("No scrobbles yet.")
                    .foregroundColor(.secondary)
            } else {
                let entries = groupedRecentScrobbleEntries(scrobbleLog.recentEntries())
                VStack(spacing: Layout.logRowSpacing) {
                    ForEach(entries) { entry in
                        ScrobbleLogRowView(
                            entry: entry.representativeEntry,
                            consecutivePlayCount: entry.count,
                            isLast: entry.id == entries.last?.id,
                            engine: engine
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(contentCardBackground)
    }

    private func connectTapped() async {
        errorText = nil
        do {
            try await auth.connect()
            engine.start()
        } catch {
            if error is CancellationError { return }
            errorText = error.localizedDescription
        }
    }

    private var musicControlActionTitle: String {
        switch permissions.automationStatus {
        case .notDetermined:
            return NSLocalizedString("Allow Music Control", comment: "")
        case .denied, .restricted, .authorized:
            return NSLocalizedString("Open System Settings", comment: "")
        }
    }

    private func handleMusicControlPermissionAction() {
        switch permissions.automationStatus {
        case .notDetermined:
            Task { @MainActor in
                await observer.requestMusicControlPermission()
                await permissions.refreshNow(observer: observer)
                AppModel.shared.startIfNeeded()
            }
        case .denied, .restricted, .authorized:
            if let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                openURL(automationSettingsURL)
            } else if let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                openURL(privacySettingsURL)
            }
        }
    }

    private func refreshScrobbleLogDisplay(now: Date, forceReload: Bool = false) {
        guard forceReload || now.timeIntervalSince(lastScrobbleLogRefreshDate) >= 60 else { return }
        scrobbleLog.reload()
        lastScrobbleLogRefreshDate = now
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func engineStatusText(_ status: String) -> Text {
        let parts = status
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var text = Text("Engine: ")
        for (idx, part) in parts.enumerated() {
            if idx > 0 { text = text + Text(" | ") }
            let segment = Text(part)
            if part == NSLocalizedString("error scrobbling", comment: "") {
                text = text + segment.fontWeight(.bold).foregroundColor(.red)
            } else if part == NSLocalizedString("now playing sent", comment: "") || part == NSLocalizedString("scrobbled", comment: "") {
                text = text + segment.fontWeight(.bold)
            } else {
                text = text + segment
            }
        }
        return text
    }

    private func presentSetupIfNeeded() {
        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected
        let shouldShow = (!hasSeenSetup || !hasAnyAccount || permissions.automationStatus != .authorized)
        guard shouldShow else { return }

        isShowingHelp = false
        if !isShowingSetup {
            isShowingSetup = true
        }
    }

    private func refreshPermissionStatusesIfNeeded() {
        Task { @MainActor in
            await permissions.refreshNow(observer: observer)
            observer.refreshOnceIfAuthorized()
            presentSetupIfNeeded()

            let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected
            if hasSeenSetup, hasAnyAccount, permissions.automationStatus == .authorized {
                AppModel.shared.startIfNeeded()
            }
        }
    }

    private func presentWhatsNewIfNeeded() {}

    private func dismissWhatsNew() {
        WhatsNewRelease.markSeen()
        isShowingWhatsNew = false
    }
}

private struct GroupedRecentScrobbleEntry: Identifiable {
    let representativeEntry: ScrobbleLogStore.Entry
    let count: Int
    let memberIDs: [UUID]

    var id: UUID {
        representativeEntry.id
    }
}

private struct ConsecutivePlayCountBadge: View {
    let count: Int

    var body: some View {
        Text("x\(count)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}

private func groupedRecentScrobbleEntries(_ entries: [ScrobbleLogStore.Entry]) -> [GroupedRecentScrobbleEntry] {
    ConsecutivePlayGrouper.groups(
        from: entries,
        shouldGroup: { _ in true },
        dedupeKey: { "\($0.source.rawValue):\($0.track.dedupeKey)" },
        memberID: \.id
    )
    .map {
        GroupedRecentScrobbleEntry(
            representativeEntry: $0.representative,
            count: $0.count,
            memberIDs: $0.memberIDs
        )
    }
}

private struct ScrobbleLogRowView: View {
    let entry: ScrobbleLogStore.Entry
    var consecutivePlayCount: Int = 1
    let isLast: Bool
    let engine: ScrobbleEngine

    var body: some View {
        rowContent
        .frame(maxWidth: .infinity, alignment: .leading)
        // Suppress inherited animations so new scrobble rows appear instantly rather than sliding in.
        .transaction { $0.animation = nil }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                Task {
                    try? await engine.submitManualScrobble(
                        artist: entry.track.artist,
                        title: entry.track.title,
                        album: entry.track.album,
                        albumArtist: entry.track.albumArtist,
                        timestamp: Int(Date().timeIntervalSince1970)
                    )
                }
            } label: {
                Label("Scrobble Again", systemImage: "arrow.clockwise")
            }
        } preview: {
            rowContent
            .padding()
        }

        if !isLast {
            Divider()
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.track.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if consecutivePlayCount > 1 {
                        ConsecutivePlayCountBadge(count: consecutivePlayCount)
                    }
                }

                HStack(spacing: 6) {
                    Text(entry.track.artist)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.82))
                        .multilineTextAlignment(.leading)
                    if entry.track.artist.isEmpty || entry.track.title.isEmpty {
                        Text("Error")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                if let album = entry.track.album, !album.isEmpty {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            HStack(spacing: 8) {
                RelativeScrobbleTimeView(date: entry.scrobbledAt)
                if entry.lovedOnLastFM == true {
                    Text("Loved")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                if entry.source != .live {
                    sourceBadge(entry.source)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.primary)
        }
    }

    private func sourceLabel(_ source: ScrobbleLogStore.Source) -> String {
        switch source {
        case .live: return ""
        case .backlog: return NSLocalizedString("Backlog", comment: "")
        case .playbackHistory: return NSLocalizedString("Listening History", comment: "")
        case .recentlyPlayed: return NSLocalizedString("Recently Played API", comment: "")
        case .manual: return NSLocalizedString("Manual", comment: "")
        }
    }

    @ViewBuilder
    private func sourceBadge(_ source: ScrobbleLogStore.Source) -> some View {
        Text(sourceLabel(source))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            }
            .compositingGroup()
    }

}

private struct TrackPlaybackProgressView: View {
    let track: Track
    let engine: ScrobbleEngine
    let formatTime: (TimeInterval) -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let duration = track.durationSeconds ?? 0
            let playedSeconds = engine.liveDisplayedPlayedSeconds(for: track)
            let progress = duration > 0 ? min(playedSeconds / duration, 1.0) : 0

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color.primary.opacity(0.8))
                            .frame(width: geo.size.width * progress, height: 6)
                        let thresholdX = geo.size.width * ProSettings.scrobbleThresholdFraction()
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: 3, height: 10)
                            .offset(x: thresholdX - 1.5)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(formatTime(playedSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RelativeScrobbleTimeView: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(RelativeScrobbleTimeFormatter.string(from: date, to: context.date))
        }
    }
}

extension View {
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

extension View {
    @ViewBuilder
    func pillButtonBorder() -> some View {
        if #available(macOS 14.0, *) {
            self.buttonBorderShape(.capsule)
        } else {
            self.buttonBorderShape(.roundedRectangle)
        }
    }

    func prominentButtonBackground(_ color: Color) -> some View {
        self.background {
            Capsule(style: .continuous)
                .fill(color.opacity(0.1))
        }
    }

    func brightButtonBorder(_ color: Color, showsShadow: Bool = true) -> some View {
        self.overlay {
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.75), lineWidth: 1.5)
                .shadow(color: showsShadow ? color.opacity(0.66) : .clear, radius: 20, x: 0, y: 0)
                .shadow(color: showsShadow ? color.opacity(0.54) : .clear, radius: 10, x: 0, y: 0)
        }
    }
}

enum MacFloatingBarLayout {
    static let contentHorizontalPadding: CGFloat = 16
    static let topButtonsHeight: CGFloat = 40
    static let topButtonsTopInset: CGFloat = 24 // slightly increased top padding
    static let contentTopPadding: CGFloat = 68 // yields a slightly reduced 16pt bottom gap below buttons
    static let circleButtonContentTopPadding: CGFloat = 28
}

struct MacCapsuleControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .frame(minHeight: MacFloatingBarLayout.topButtonsHeight)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MacFloatingCircleButton: View {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension ContentView {
    @ViewBuilder
    var macModalOverlay: some View {
        let isPresented = (isShowingSetup || isShowingHelp || isShowingSettings || isShowingManualScrobble || isShowingListenBrainzConnect)
        if isPresented {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Don't let a backdrop tap dismiss onboarding — the user must complete setup.
                        if !isShowingSetup {
                            dismissMacModal()
                        }
                    }

                macModalContent
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
                    .padding(12)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: isPresented)
        }
    }

    @ViewBuilder
    var macModalContent: some View {
        if isShowingSetup {
            SetupHelpView(
                mode: .onboarding,
                onOpenSettings: {
                    isShowingSetup = false
                    isShowingSettings = true
                },
                onOpenListenBrainzConnect: {
                    listenBrainzConnectReturnTarget = .setup
                    isShowingSetup = false
                    isShowingListenBrainzConnect = true
                }
            ) {
                hasSeenSetup = true
                isShowingSetup = false
                presentWhatsNewIfNeeded()
                Task { @MainActor in
                    AppModel.shared.startIfNeeded()
                }
            }
        } else if isShowingHelp {
            SetupHelpView(
                mode: .help,
                onOpenSettings: {
                    isShowingHelp = false
                    isShowingSettings = true
                },
                onOpenListenBrainzConnect: {
                    listenBrainzConnectReturnTarget = .help
                    isShowingHelp = false
                    isShowingListenBrainzConnect = true
                }
            ) {
                isShowingHelp = false
            }
        } else if isShowingSettings {
            SettingsView(
                onBack: { isShowingSettings = false },
                onOpenListenBrainzConnect: {
                    listenBrainzConnectReturnTarget = .settings
                    isShowingSettings = false
                    isShowingListenBrainzConnect = true
                }
            )
        } else if isShowingListenBrainzConnect {
            ListenBrainzConnectView(onBack: {
                isShowingListenBrainzConnect = false
                switch listenBrainzConnectReturnTarget {
                case .setup:
                    isShowingSetup = true
                case .help:
                    isShowingHelp = true
                case .settings:
                    isShowingSettings = true
                }
            })
        } else if isShowingManualScrobble {
            ManualScrobbleView(onBack: { isShowingManualScrobble = false })
        }
    }

    func dismissMacModal() {
        if isShowingListenBrainzConnect {
            isShowingListenBrainzConnect = false
            switch listenBrainzConnectReturnTarget {
            case .setup:
                isShowingSetup = true
            case .help:
                isShowingHelp = true
            case .settings:
                isShowingSettings = true
            }
        } else if isShowingSettings {
            isShowingSettings = false
        } else if isShowingHelp {
            isShowingHelp = false
        } else if isShowingManualScrobble {
            isShowingManualScrobble = false
        } else if isShowingSetup {
            // Keep onboarding visible until the setup requirements are actually satisfied.
            return
        }
    }
}
