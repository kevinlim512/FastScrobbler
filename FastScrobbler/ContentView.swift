import MediaPlayer
import SwiftUI
#if canImport(SafariServices) && canImport(UIKit)
import SafariServices
#endif
#if canImport(WebKit)
import WebKit
#endif

struct ContentView: View {
    fileprivate static let homeListeningHistoryButtonHeight: CGFloat = 44
    fileprivate static let listeningHistoryConfirmationButtonHeight: CGFloat = 50

    private enum Keys {
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    private enum ActionButtonPalette {
        static let cardBackgroundOverlay = dynamicColor(
            light: UIColor(white: 0.97, alpha: 0.85),
            dark: UIColor(white: 0.10, alpha: 0.86)
        )
        static let cardBorder = dynamicColor(
            light: UIColor(white: 0.0, alpha: 0.10),
            dark: UIColor(white: 1.0, alpha: 0.16)
        )
        static let openMusic = dynamicColor(
            light: UIColor(red: 0.88, green: 0.45, blue: 0.50, alpha: 1.0),
            dark: UIColor(red: 0.92, green: 0.54, blue: 0.60, alpha: 1.0)
        )
        static let openMusicForeground = dynamicColor(
            light: UIColor(red: 0.54, green: 0.21, blue: 0.25, alpha: 1.0),
            dark: UIColor(red: 0.95, green: 0.82, blue: 0.84, alpha: 1.0)
        )
        static let openMusicBorder = dynamicColor(
            light: UIColor(red: 0.78, green: 0.28, blue: 0.34, alpha: 1.0),
            dark: UIColor(red: 0.84, green: 0.36, blue: 0.42, alpha: 1.0)
        )
        static let openMusicFill = dynamicColor(
            light: UIColor(red: 0.95, green: 0.84, blue: 0.86, alpha: 0.18),
            dark: UIColor(red: 0.56, green: 0.30, blue: 0.34, alpha: 0.28)
        )
        static let resume = dynamicColor(
            light: UIColor(red: 0.22, green: 0.88, blue: 0.42, alpha: 1.0),
            dark: UIColor(red: 0.34, green: 0.96, blue: 0.53, alpha: 1.0)
        )
        static let resumeForeground = dynamicColor(
            light: UIColor(red: 0.10, green: 0.44, blue: 0.21, alpha: 1.0),
            dark: UIColor(red: 0.76, green: 0.95, blue: 0.81, alpha: 1.0)
        )
        static let resumeBorder = dynamicColor(
            light: UIColor(red: 0.00, green: 0.72, blue: 0.20, alpha: 1.0),
            dark: UIColor(red: 0.00, green: 0.84, blue: 0.31, alpha: 1.0)
        )
        static let resumeFill = dynamicColor(
            light: UIColor(red: 0.82, green: 0.94, blue: 0.85, alpha: 0.20),
            dark: UIColor(red: 0.16, green: 0.40, blue: 0.23, alpha: 0.30)
        )
        static let scrobbleNow = dynamicColor(
            light: UIColor(red: 0.73, green: 0.42, blue: 0.82, alpha: 1.0),
            dark: UIColor(red: 0.79, green: 0.52, blue: 0.86, alpha: 1.0)
        )
        static let scrobbleNowForeground = dynamicColor(
            light: UIColor(red: 0.42, green: 0.27, blue: 0.49, alpha: 1.0),
            dark: UIColor(red: 0.88, green: 0.82, blue: 0.93, alpha: 1.0)
        )
        static let scrobbleNowBorder = dynamicColor(
            light: UIColor(red: 0.58, green: 0.28, blue: 0.72, alpha: 1.0),
            dark: UIColor(red: 0.66, green: 0.36, blue: 0.78, alpha: 1.0)
        )
        static let scrobbleNowFill = dynamicColor(
            light: UIColor(red: 0.90, green: 0.84, blue: 0.94, alpha: 0.18),
            dark: UIColor(red: 0.38, green: 0.28, blue: 0.48, alpha: 0.28)
        )
        static let account = dynamicColor(
            light: UIColor(red: 0.34, green: 0.62, blue: 0.86, alpha: 1.0),
            dark: UIColor(red: 0.42, green: 0.70, blue: 0.90, alpha: 1.0)
        )
        static let accountForeground = dynamicColor(
            light: UIColor(red: 0.21, green: 0.34, blue: 0.50, alpha: 1.0),
            dark: UIColor(red: 0.80, green: 0.89, blue: 0.96, alpha: 1.0)
        )
        static let monochromeForeground = dynamicColor(
            light: UIColor(white: 0.0, alpha: 1.0),
            dark: UIColor(white: 1.0, alpha: 1.0)
        )
        static let monochromeFill = dynamicColor(
            light: UIColor(white: 0.62, alpha: 1.0),
            dark: UIColor(white: 0.52, alpha: 1.0)
        )
        static let monochromeDisabledFill = dynamicColor(
            light: UIColor(white: 0.72, alpha: 1.0),
            dark: UIColor(white: 0.42, alpha: 1.0)
        )
        static let accountBorder = dynamicColor(
            light: UIColor(red: 0.24, green: 0.48, blue: 0.72, alpha: 1.0),
            dark: UIColor(red: 0.30, green: 0.56, blue: 0.78, alpha: 1.0)
        )
        static let accountFill = dynamicColor(
            light: UIColor(red: 0.84, green: 0.90, blue: 0.96, alpha: 0.18),
            dark: UIColor(red: 0.22, green: 0.34, blue: 0.48, alpha: 0.28)
        )
        static let manualForeground = dynamicColor(
            light: UIColor(white: 0.08, alpha: 1.0),
            dark: UIColor(white: 0.92, alpha: 1.0)
        )
        static let manualFill = dynamicColor(
            light: UIColor(white: 1.0, alpha: 0.60),
            dark: UIColor(white: 0.16, alpha: 0.70)
        )
        static let disabledFill = dynamicColor(
            light: UIColor(white: 1.0, alpha: 0.52),
            dark: UIColor(white: 0.20, alpha: 0.64)
        )

        private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
            Color(
                UIColor { traits in
                    traits.userInterfaceStyle == .dark ? dark : light
                }
            )
        }
    }

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @EnvironmentObject private var pro: ProPurchaseManager

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Keys.hasSeenSetup) private var hasSeenSetup = false
    @AppStorage(AppSettings.Keys.listeningHistoryRequireConfirmationEnabled, store: AppGroup.userDefaults) private var listeningHistoryRequireConfirmationEnabled = true
    @AppStorage(AppSettings.Keys.themeSelection) private var themeSelectionRawValue = AppTheme.system.rawValue
    @AppStorage(AppSettings.Keys.buttonThemeSelection) private var buttonThemeSelectionRawValue = ButtonTheme.colorful.rawValue
    @AppStorage(AppSettings.Keys.scanButtonLocation) private var scanButtonLocationRawValue = ScanButtonLocation.recentScrobbles.rawValue

    @State private var lastScrobbleLogRefreshDate: Date = .distantPast
    @State private var errorText: String?
    @State private var listeningHistoryAlertMessage: String?
    @State private var isShowingSetup = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingSettings = false
    @State private var isShowingManualScrobble = false
    @State private var isShowingListeningHistoryReview = false
    @State private var isShowingFullscreenNowPlaying = false
    @State private var isScanningListeningHistory = false
    @State private var isHandlingPendingListeningHistoryLaunchRequest = false
    @State private var settingsScrollRequest: SettingsScrollRequest?

    @State private var inAppBrowserURL: URL?
    @State private var prevBounce = 0
    @State private var nextBounce = 0

    private enum Tab { case home, settings }
    @State private var selectedTab: Tab = .home

    private var autoScrobbleListeningHistoryBinding: Binding<Bool> {
        Binding(
            get: { !listeningHistoryRequireConfirmationEnabled },
            set: { isEnabled in
                let requireConfirmation = !isEnabled
                guard listeningHistoryRequireConfirmationEnabled != requireConfirmation else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    listeningHistoryRequireConfirmationEnabled = requireConfirmation
                }
                Task {
                    if isEnabled { isScanningListeningHistory = true }
                    defer { if isEnabled { isScanningListeningHistory = false } }
                    await AppModel.shared.handleListeningHistoryRequireConfirmationChanged(isEnabled: requireConfirmation)
                }
            }
        )
    }

    var body: some View {
        Group {
            // TabView keeps both tabs alive so the engine continues running in the background.
            TabView(selection: $selectedTab) {
                NavigationView {
                    mainContent
                }
                .tabItem { Label("Home", systemImage: UIImage(systemName: "music.note.arrow.trianglehead.clockwise") != nil ? "music.note.arrow.trianglehead.clockwise" : "music.note") }
                .tag(Tab.home)

                settingsTabContent
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(Tab.settings)
            }

        }
        .onAppear {
            refreshScrobbleLogDisplay(now: .now, forceReload: true)
            refreshMediaLibraryStatusIfNeeded()
            presentSetupIfNeeded()
            presentWhatsNewIfNeeded()
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onValueChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshScrobbleLogDisplay(now: .now, forceReload: true)
            refreshMediaLibraryStatusIfNeeded()
            presentSetupIfNeeded()
            presentWhatsNewIfNeeded()
            if hasSeenSetup {
                AppModel.shared.startIfNeeded()
            }
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onValueChange(of: observer.authorizationStatus) { _ in
            refreshMediaLibraryStatusIfNeeded()
            presentSetupIfNeeded()
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onValueChange(of: auth.sessionKey) { _ in
            presentSetupIfNeeded()
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onValueChange(of: listenBrainzAuth.userToken) { _ in
            presentSetupIfNeeded()
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onValueChange(of: hasSeenSetup) { hasSeenSetup in
            guard hasSeenSetup else { return }
            presentWhatsNewIfNeeded()
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openManualScrobble)) { _ in
            isShowingManualScrobble = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHelp)) { _ in
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerPendingScan)) { _ in
            handlePendingListeningHistoryLaunchRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerScrobbleSong)) { _ in
            Task {
                await engine.scrobbleNow(force: true)
            }
        }
        .fullScreenCover(isPresented: $isShowingSetup) {
            SetupHelpView(mode: .setup) {
                guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
                guard auth.sessionKey != nil || listenBrainzAuth.isConnected else { return }
                hasSeenSetup = true
                isShowingSetup = false
                presentWhatsNewIfNeeded()
                AppModel.shared.startIfNeeded()
                handlePendingListeningHistoryLaunchRequestIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $isShowingWhatsNew) {
            WhatsNewView {
                dismissWhatsNew()
            }
        }
#if os(iOS)
        .fullScreenCover(isPresented: $isShowingFullscreenNowPlaying) {
            FullscreenNowPlayingView(
                auth: auth,
                observer: observer,
                engine: engine,
                openURL: openURL
            )
            .presentationBackground(.clear)
        }
#endif
        // Custom Binding because .sheet(item:) would require URL: Identifiable.
        .sheet(isPresented: Binding(
            get: { inAppBrowserURL != nil },
            set: { isPresented in
                if !isPresented {
                    inAppBrowserURL = nil
                }
            }
        )) {
            if let url = inAppBrowserURL {
                InAppSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isShowingListeningHistoryReview) {
            ListeningHistoryReviewView {
                scrobbleLog.reload()
                lastScrobbleLogRefreshDate = .now
                engine.start()
            }
            .environmentObject(auth)
            .environmentObject(scrobbleLog)
        }
        .alert("Listening History", isPresented: Binding(
            get: { listeningHistoryAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    listeningHistoryAlertMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(listeningHistoryAlertMessage ?? "")
        }
        .preferredColorScheme(selectedAppTheme.preferredColorScheme)
    }

    private var selectedAppTheme: AppTheme {
        AppTheme(rawValue: themeSelectionRawValue) ?? .system
    }

    private var selectedButtonTheme: ButtonTheme {
        ButtonTheme(rawValue: buttonThemeSelectionRawValue) ?? .colorful
    }

    private var selectedScanButtonLocation: ScanButtonLocation {
        ScanButtonLocation(rawValue: scanButtonLocationRawValue) ?? .recentScrobbles
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
        return disabled ? .secondary.opacity(0.35) : defaultColor
    }

    private var mainContent: some View {
        let hasLastFM = auth.sessionKey != nil
        let hasListenBrainz = listenBrainzAuth.isConnected
        let isTwoServicesSignedIn = hasLastFM && hasListenBrainz

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                if !isTwoServicesSignedIn {
                    statusCard
                    trackCard
                } else {
                    trackCard
                    statusCard
                }
                scrobbleLogCard
                if let errorText {
                    Text(errorText)
                        .foregroundColor(Color.accentColor)
                        .font(.footnote)
                }
            }
            .padding()
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: observer.track)
            .animation(.easeInOut(duration: 0.3), value: auth.sessionKey != nil)
            .animation(.easeInOut(duration: 0.3), value: listenBrainzAuth.isConnected)
            .animation(.easeInOut(duration: 0.3), value: engine.statusText)
        }
        .refreshable {
            await refreshHome()
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                // Keep this overlay out of the scroll view so SwiftUI never snapshots it
                // at full width with a transient zero-height container during modal transitions.
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: homeTopGradientHeight(for: proxy.size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshScrobbleLogDisplay(now: .now)
        }
        .navigationTitle("")
    }

    private var settingsTabContent: some View {
        SettingsView(isShowingSetup: $isShowingSetup, scrollRequest: $settingsScrollRequest)
            .environment(\.isEmbeddedInTab, true)
    }

    private func homeTopGradientHeight(for size: CGSize) -> CGFloat {
        isFourPointSevenInchPhone(size) ? 40 : 70
    }

    private func isFourPointSevenInchPhone(_ size: CGSize) -> Bool {
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        return shortSide <= 375 && longSide <= 667
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

    @ViewBuilder
    private var statusCard: some View {
        let hasLastFM = auth.sessionKey != nil
        let hasListenBrainz = listenBrainzAuth.isConnected

        if !hasLastFM && !hasListenBrainz {
            VStack(alignment: .leading, spacing: 12) {
                singleStatusCard(title: "Last.fm", isConnected: false)
                singleStatusCard(title: "ListenBrainz", isConnected: false)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if hasLastFM {
                    singleStatusCard(title: "Last.fm", isConnected: true)
                }
                if hasListenBrainz {
                    singleStatusCard(title: "ListenBrainz", isConnected: true)
                }
            }
        }
    }

    private func singleStatusCard(title: String, isConnected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
        .animation(.easeInOut(duration: 0.3), value: isConnected)
        .animation(.easeInOut(duration: 0.3), value: engine.statusText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private var trackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Now Playing")
                    .font(.title2.weight(.semibold))
                Spacer()
#if os(iOS)
                Button {
                    isShowingFullscreenNowPlaying = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("Open Fullscreen Now Playing", comment: "")))
#endif
            }
            if let t = observer.track {
                nowPlayingMetadata(for: t)
                if let d = t.durationSeconds, d > 0 {
                    VStack(spacing: 6) {
                        TrackPlaybackProgressView(track: t, engine: engine, formatTime: formatTime)
                        HStack(spacing: 32) {
                            Button {
                                prevBounce += 1
                                observer.skipToPreviousItem()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .symbolEffect(.bounce, value: prevBounce)
                            }
                            .font(.title3)
                            Button { observer.togglePlayPause() } label: {
                                Image(systemName: observer.playbackState == .playing ? "pause.fill" : "play.fill")
                                    .contentTransition(.symbolEffect(.replace.downUp))
                                    .scaleEffect(observer.playbackState == .playing ? 1.0 : 1.15)
                                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: observer.playbackState)
                                    .frame(width: 32, height: 32)
                            }
                            .font(.title)
                            Button {
                                nextBounce += 1
                                observer.skipToNextItem()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .symbolEffect(.bounce, value: nextBounce)
                            }
                            .font(.title3)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: observer.playbackState)
                    }
                    .padding(.top, 12)
                }
            } else {
                Text("No track detected.")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: observer.track)
        .animation(.easeInOut(duration: 0.3), value: observer.playbackState)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
#if os(iOS)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            isShowingFullscreenNowPlaying = true
        }
#endif
    }

    @ViewBuilder
    private func nowPlayingMetadata(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.body.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.leading)

            Text(track.artist)
                .font(.body.weight(.semibold))
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
        let actionButtonHeight: CGFloat = 40
        let actionButtonSpacing: CGFloat = 12
        let hasAnyAccount = auth.sessionKey != nil || listenBrainzAuth.isConnected

        return VStack(spacing: 12) {
            Button {
                if let url = URL(string: "music://") {
                    openURL(url)
                }
            } label: {
                Label(NSLocalizedString("Open Music App", comment: ""), systemImage: "music.note")
                    .font(.body.weight(.bold))
                    .foregroundStyle(actionButtonForeground(ActionButtonPalette.openMusicForeground))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
            }
            .buttonStyle(.bordered)
            .pillButtonBorder()
            .tint(actionButtonTint(ActionButtonPalette.openMusic))
            .prominentButtonBackground(actionButtonFill(ActionButtonPalette.openMusicFill))
            .brightButtonBorder(actionButtonBorder(ActionButtonPalette.openMusicBorder))
            .buttonGlow(actionButtonTint(ActionButtonPalette.openMusic))

            HStack(spacing: actionButtonSpacing) {
                Button {
                    if engine.isUserPaused {
                        AppSettings.noteListeningHistoryRecoveryResumeNow()
                    }
                    engine.setUserPaused(!engine.isUserPaused)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engine.isUserPaused ? "play.fill" : "pause.fill")
                        Text(engine.isUserPaused ? NSLocalizedString("Resume", comment: "") : NSLocalizedString("Pause", comment: ""))
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(actionButtonForeground(engine.isUserPaused ? ActionButtonPalette.resumeForeground : ActionButtonPalette.scrobbleNowForeground))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.bordered)
                .pillButtonBorder()
                .tint(actionButtonTint(engine.isUserPaused ? ActionButtonPalette.resume : ActionButtonPalette.scrobbleNow))
                .prominentButtonBackground(actionButtonFill(engine.isUserPaused ? ActionButtonPalette.resumeFill : ActionButtonPalette.scrobbleNowFill))
                .brightButtonBorder(actionButtonBorder(engine.isUserPaused ? ActionButtonPalette.resumeBorder : ActionButtonPalette.scrobbleNowBorder))
                .buttonGlow(actionButtonTint(engine.isUserPaused ? ActionButtonPalette.resume : ActionButtonPalette.scrobbleNow))
                .disabled(!hasAnyAccount)

                if !hasAnyAccount {
                    Button {
                        isShowingSetup = true
                    } label: {
                        Label(NSLocalizedString("Sign In", comment: ""), systemImage: "person.crop.circle")
                            .font(.body.weight(.bold))
                            .foregroundStyle(ActionButtonPalette.accountForeground)
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(ActionButtonPalette.account)
                    .prominentButtonBackground(ActionButtonPalette.accountFill)
                    .brightButtonBorder(ActionButtonPalette.accountBorder)
                    .buttonGlow(ActionButtonPalette.account)
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
                        .font(.body.weight(.bold))
                        .foregroundStyle(actionButtonForeground(ActionButtonPalette.scrobbleNowForeground))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.scrobbleNow))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.scrobbleNowFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.scrobbleNowBorder))
                    .buttonGlow(actionButtonTint(ActionButtonPalette.scrobbleNow))
                }
            }

            if selectedScanButtonLocation == .homeTabActions {
                scanListeningHistoryButton
            }

            if hasAnyAccount {
                if auth.sessionKey != nil {
                    Button {
                        if let url = auth.freshProfileURL() {
                            inAppBrowserURL = url
                        }
                    } label: {
                        Label(NSLocalizedString("View Profile in Last.fm", comment: ""), systemImage: "person.circle")
                            .font(.body.weight(.bold))
                            .foregroundStyle(actionButtonForeground(ActionButtonPalette.accountForeground))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.account))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.accountFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.accountBorder))
                    .buttonGlow(actionButtonTint(ActionButtonPalette.account))
                    .disabled(auth.profileURL == nil)
                }

                if listenBrainzAuth.isConnected {
                    Button {
                        if let url = listenBrainzAuth.freshProfileURL() {
                            inAppBrowserURL = url
                        }
                    } label: {
                        Label(NSLocalizedString("View Profile in ListenBrainz", comment: ""), systemImage: "waveform.path.ecg")
                            .font(.body.weight(.bold))
                            .foregroundStyle(actionButtonForeground(ActionButtonPalette.accountForeground))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(actionButtonTint(ActionButtonPalette.account))
                    .prominentButtonBackground(actionButtonFill(ActionButtonPalette.accountFill))
                    .brightButtonBorder(actionButtonBorder(ActionButtonPalette.accountBorder))
                    .buttonGlow(actionButtonTint(ActionButtonPalette.account))
                    .disabled(listenBrainzAuth.profileURL == nil)
                }

                Button {
                    isShowingManualScrobble = true
                } label: {
                    Label(NSLocalizedString("Manual Scrobble", comment: ""), systemImage: "plus.circle")
                        .font(.body.weight(.bold))
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
        .frame(maxWidth: .infinity, alignment: .center)
        .sheet(isPresented: $isShowingManualScrobble) {
            ManualScrobbleView()
        }
    }

    @ViewBuilder
    private var scanListeningHistoryButton: some View {
        let isListeningHistoryScanDisabled = engine.isUserPaused || !canRunListeningHistoryScan || isScanningListeningHistory

        Button {
            Task { await runListeningHistoryScanFromHome(showsResultAlert: true) }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text(isScanningListeningHistory ? NSLocalizedString("Scanning…", comment: "") : NSLocalizedString("Scan Listening History", comment: ""))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
            .font(.body.weight(.bold))
            .foregroundStyle(actionButtonForeground(ActionButtonPalette.scrobbleNowForeground))
            .frame(maxWidth: .infinity, minHeight: Self.homeListeningHistoryButtonHeight, alignment: .center)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
        .tint(actionButtonTint(ActionButtonPalette.scrobbleNow))
        .prominentButtonBackground(actionButtonFill(ActionButtonPalette.scrobbleNowFill, disabled: isListeningHistoryScanDisabled))
        .brightButtonBorder(actionButtonBorder(ActionButtonPalette.scrobbleNowBorder, disabled: isListeningHistoryScanDisabled))
        .buttonGlow(actionButtonTint(ActionButtonPalette.scrobbleNow))
        .disabled(isListeningHistoryScanDisabled)
        .transition(.opacity)
    }

    private var scrobbleLogCard: some View {
        let recentScrobblesTopPadding: CGFloat = 6

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scrobbles")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    settingsScrollRequest = SettingsScrollRequest(target: .listeningHistory)
                    selectedTab = .settings
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel(Text("Listening History"))
                .accessibilityHint(Text("Settings"))
            }

            if selectedScanButtonLocation == .recentScrobbles {
                scanListeningHistoryButton
                    .padding(.top, 6)
            }

            Toggle(isOn: autoScrobbleListeningHistoryBinding) {
                Text("Auto-scrobble Listening History")
                    .font(.body.weight(.semibold))
            }
                .tint(Color.accentColor)
                .padding(.vertical, 10)

            Divider()

            if scrobbleLog.entries.isEmpty {
                Text("No scrobbles yet.")
                    .foregroundColor(.secondary)
                    .padding(.top, recentScrobblesTopPadding)
            } else {
                let entries = groupedRecentScrobbleEntries(scrobbleLog.recentEntries())
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        ScrobbleLogRowView(
                            entry: entry.representativeEntry,
                            consecutivePlayCount: entry.count,
                            isLast: entry.id == entries.last?.id,
                            engine: engine
                        )
                    }
                }
                .padding(.top, recentScrobblesTopPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: listeningHistoryRequireConfirmationEnabled)
        .padding()
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

    @MainActor
    private func refreshHome() async {
        if listeningHistoryRequireConfirmationEnabled {
            await runListeningHistoryScanFromHome(showsResultAlert: false)
            return
        }

        let result = await AppModel.shared.runUserInitiatedListeningHistoryScan(bypassRecentTrackCooldown: true)
        if result.totalFlushedCount > 0 {
            scrobbleLog.reload()
            lastScrobbleLogRefreshDate = .now
        }
    }

    private var canRunListeningHistoryScan: Bool {
        auth.sessionKey != nil || listenBrainzAuth.isConnected
    }

    @MainActor
    private func runListeningHistoryScanFromHome(showsResultAlert: Bool) async {
        guard canRunListeningHistoryScan else { return }
        guard !isScanningListeningHistory else { return }
        isScanningListeningHistory = true
        defer { isScanningListeningHistory = false }

        let result = await AppModel.shared.runUserInitiatedListeningHistoryScan(
            allowExtendedLookback: true,
            allowSubmissionWhilePaused: true,
            bypassRecentTrackCooldown: true
        )

        if result.requiresConfirmation {
            if result.pendingReviewCount > 0 {
                isShowingListeningHistoryReview = true
            } else if showsResultAlert {
                listeningHistoryAlertMessage = listeningHistoryScanMessage(for: result)
            }
            return
        }

        if result.totalFlushedCount > 0 {
            scrobbleLog.reload()
            lastScrobbleLogRefreshDate = .now
        }

        if showsResultAlert {
            listeningHistoryAlertMessage = listeningHistoryScanMessage(for: result)
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
                text = text + segment.fontWeight(.bold).foregroundColor(Color.accentColor)
            } else if part == NSLocalizedString("now playing sent", comment: "") || part == NSLocalizedString("scrobbled", comment: "") {
                text = text + segment.fontWeight(.bold)
            } else {
                text = text + segment
            }
        }
        return text
    }

    private func presentSetupIfNeeded() {
        // Re-check on every scene activation — permissions can change while the app is backgrounded.
        let mediaAuthorized = (MPMediaLibrary.authorizationStatus() == .authorized)
        let hasAnyAccount = (auth.sessionKey != nil || listenBrainzAuth.isConnected)
        let shouldShow = (!hasSeenSetup || !mediaAuthorized || !hasAnyAccount)
        guard shouldShow else { return }

        if !isShowingSetup {
            isShowingSetup = true
        }
    }

    private func refreshMediaLibraryStatusIfNeeded() {}

    private func presentWhatsNewIfNeeded() {
        guard hasSeenSetup else { return }
        guard !isShowingSetup && !isShowingWhatsNew else { return }
        guard inAppBrowserURL == nil else { return }
        if WhatsNewRelease.shouldPresent() {
            isShowingWhatsNew = true
        }
    }

    private func dismissWhatsNew() {
        WhatsNewRelease.markSeen()
        isShowingWhatsNew = false
        handlePendingListeningHistoryLaunchRequestIfNeeded()
    }

    private func handlePendingManualScrobbleLaunchRequestIfNeeded() {
        guard hasSeenSetup else { return }
        guard !isShowingSetup && !isShowingWhatsNew else { return }
        guard AppSettings.consumePendingManualScrobbleLaunchRequest() else { return }
        isShowingManualScrobble = true
    }

    private func handlePendingHelpLaunchRequestIfNeeded() {
        guard !isShowingSetup && !isShowingWhatsNew else { return }
        guard AppSettings.consumePendingHelpLaunchRequest() else { return }
        selectedTab = .settings
        NotificationCenter.default.post(name: .openHelp, object: nil)
    }

    private func handlePendingListeningHistoryLaunchRequestIfNeeded() {
        handlePendingManualScrobbleLaunchRequestIfNeeded()
        handlePendingHelpLaunchRequestIfNeeded()
        guard hasSeenSetup else { return }
        guard !isShowingSetup && !isShowingWhatsNew else { return }
        guard inAppBrowserURL == nil else { return }
        guard !isHandlingPendingListeningHistoryLaunchRequest else { return }
        guard let request = AppSettings.consumePendingListeningHistoryLaunchRequest() else { return }

        isHandlingPendingListeningHistoryLaunchRequest = true
        selectedTab = .home
        listeningHistoryAlertMessage = nil
        Task { @MainActor in
            defer { isHandlingPendingListeningHistoryLaunchRequest = false }

            guard request != .openReviewOnly else {
                isShowingListeningHistoryReview = true
                return
            }

            guard canRunListeningHistoryScan else {
                if request == .scanAndOpenReview {
                    isShowingListeningHistoryReview = true
                }
                return
            }

            let result = await AppModel.shared.runUserInitiatedListeningHistoryScan(
                allowExtendedLookback: true,
                allowSubmissionWhilePaused: true,
                bypassRecentTrackCooldown: true
            )

            if result.totalFlushedCount > 0 {
                scrobbleLog.reload()
                lastScrobbleLogRefreshDate = .now
            }

            switch request {
            case .openReviewOnly:
                isShowingListeningHistoryReview = true
            case .scanAndOpenReview:
                isShowingListeningHistoryReview = true
            case .scanAndShowResult:
                isShowingListeningHistoryReview = false
                listeningHistoryAlertMessage = listeningHistoryScanMessage(for: result)
            }
        }
    }
}

func listeningHistoryScanMessage(for result: ListeningHistoryScanService.Result) -> String {
    if result.requiresConfirmation {
        if result.totalQueuedCount > 0 || result.skippedDuplicateCount > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("Found %lld new library play(s) and %lld new Apple Music recent track(s).\nAdded %lld item(s) to the review list.\nSkipped %lld already imported play(s).", comment: ""),
                Int64(result.importedCount),
                Int64(result.importedRecentTrackCount),
                Int64(result.totalQueuedCount),
                Int64(result.skippedDuplicateCount)
            )
        } else if result.recentTracksAuthorizationUnavailable {
            return NSLocalizedString(
                "No new library plays found. Apple Music recent tracks could not be checked because Music access is disabled.",
                comment: ""
            )
        } else if result.recentTracksStatus == .seeded {
            return NSLocalizedString(
                "Apple Music recent tracks were initialized from your current history. Future scans will only add newer plays to the review list.",
                comment: ""
            )
        } else if result.recentTracksStatus == .fetchFailed {
            return NSLocalizedString(
                "No new library plays found. Apple Music recent tracks could not be checked because the Apple Music API request failed.",
                comment: ""
            )
        } else {
            return NSLocalizedString(
                "No new plays found. Scrobbling from Listening History only works for songs added to your Library.",
                comment: ""
            )
        }
    }

    if result.totalImportedCount > 0 || result.totalFlushedCount > 0 || result.skippedDuplicateCount > 0 {
        return String.localizedStringWithFormat(
            NSLocalizedString("Found %lld new library play(s) and %lld new Apple Music recent track(s).\nSubmitted %lld scrobble(s).\nSkipped %lld already imported play(s).", comment: ""),
            Int64(result.importedCount),
            Int64(result.importedRecentTrackCount),
            Int64(result.totalFlushedCount),
            Int64(result.skippedDuplicateCount)
        )
    } else if result.recentTracksAuthorizationUnavailable {
        return NSLocalizedString(
            "No new library plays found. Apple Music recent tracks could not be checked because Music access is disabled.",
            comment: ""
        )
    } else if result.recentTracksStatus == .seeded {
        return NSLocalizedString(
            "Apple Music recent tracks were initialized from your current history. Future scans will only import newer plays.",
            comment: ""
        )
    } else if result.recentTracksStatus == .fetchFailed {
        return NSLocalizedString(
            "No new library plays found. Apple Music recent tracks could not be checked because the Apple Music API request failed.",
            comment: ""
        )
    } else {
        return NSLocalizedString(
            "No new plays found. Scrobbling from Listening History only works for songs added to your Library.",
            comment: ""
        )
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

private struct GroupedListeningHistoryReviewEntry: Identifiable {
    let representativeEntry: ListeningHistoryReviewStore.Entry
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

private func groupedListeningHistoryReviewEntries(
    _ entries: [ListeningHistoryReviewStore.Entry]
) -> [GroupedListeningHistoryReviewEntry] {
    ConsecutivePlayGrouper.groups(
        from: entries,
        shouldGroup: { _ in true },
        dedupeKey: { "\($0.origin.rawValue):\($0.track.dedupeKey)" },
        memberID: \.id
    )
    .map {
        GroupedListeningHistoryReviewEntry(
            representativeEntry: $0.representative,
            count: $0.count,
            memberIDs: $0.memberIDs
        )
    }
}

struct ListeningHistoryReviewView: View {
    var onSubmitted: (() -> Void)? = nil

    private let deleteButtonHeight: CGFloat = 40
    private let submitButtonHeight = ContentView.listeningHistoryConfirmationButtonHeight

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reviewStore = ListeningHistoryReviewStore.shared

    @State private var selectedIDs: Set<UUID> = []
    @State private var isSubmitting = false
    @State private var now = Date()

    private var entries: [ListeningHistoryReviewStore.Entry] {
        reviewStore.pendingEntries()
    }

    private var groupedEntries: [GroupedListeningHistoryReviewEntry] {
        groupedListeningHistoryReviewEntries(entries)
    }

    private var selectedEntryIDs: Set<UUID> {
        Set(entries.map(\.id)).intersection(selectedIDs)
    }

    private var selectedEntryCount: Int {
        selectedEntryIDs.count
    }

    private var isSelectingEntries: Bool {
        selectedEntryCount > 0
    }

    private var allSelected: Bool {
        !entries.isEmpty && selectedEntryCount == entries.count
    }

    private var showingCloseButton: Bool {
        !isSelectingEntries
    }

    private var topLeadingTitle: String {
        return allSelected
            ? NSLocalizedString("Deselect All", comment: "")
            : NSLocalizedString("Select All", comment: "")
    }

    private var navigationTitle: String {
        showingCloseButton ? NSLocalizedString("Listening History", comment: "") : ""
    }

    private var deleteButtonTitle: String {
        if isSelectingEntries {
            return String(
                format: NSLocalizedString("Delete Selected (%lld)", comment: ""),
                selectedEntryCount
            )
        }
        return NSLocalizedString("Delete Selected", comment: "")
    }

    private var submitButtonTitle: String {
        if isSelectingEntries {
            return String(
                format: NSLocalizedString("Submit Selected (%lld)", comment: ""),
                selectedEntryCount
            )
        }
        return NSLocalizedString("Submit All", comment: "")
    }

    private var canDelete: Bool {
        isSelectingEntries && !isSubmitting
    }

    private var canSubmit: Bool {
        (auth.sessionKey != nil || listenBrainzAuth.isConnected) && !entries.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 18) {
                        Text("No pending plays from Listening History.")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
                } else {
                    List {
                        ForEach(groupedEntries) { entry in
                            let isSelected = ConsecutivePlayGrouper.isFullySelected(
                                memberIDs: entry.memberIDs,
                                selectedIDs: selectedIDs
                            )
                            Button {
                                toggleSelection(for: entry.memberIDs)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(entry.representativeEntry.track.artist) — \(entry.representativeEntry.track.title)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if entry.count > 1 {
                                                ConsecutivePlayCountBadge(count: entry.count)
                                            }
                                        }
                                        if let album = entry.representativeEntry.track.album, !album.isEmpty {
                                            Text(album)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            Text(RelativeScrobbleTimeFormatter.string(from: entry.representativeEntry.playedAt, to: now))
                                            if let sourceLabel = visibleSourceLabel(for: entry.representativeEntry.origin) {
                                                Text(sourceLabel)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleTopLeadingTap()
                    } label: {
                        if showingCloseButton {
                            IOSCloseButtonLabel(style: .plain)
                        } else {
                            Text(topLeadingTitle)
                        }
                    }
                    .accessibilityLabel(showingCloseButton ? NSLocalizedString("Close", comment: "") : topLeadingTitle)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        handleDeleteTapped()
                    } label: {
                        Text(deleteButtonTitle)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: deleteButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .pillButtonBorder()
                    .tint(Color.accentColor)
                    .disabled(!canDelete)

                    Button {
                        Task { await submitPendingItems() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(submitButtonTitle)
                                    .font(.body.weight(.semibold))
                            }
                            Spacer()
                        }
                        .frame(minHeight: submitButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .pillButtonBorder()
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
        .onValueChange(of: entries.map(\.id)) { ids in
            let validIDs = Set(ids)
            selectedIDs = selectedIDs.intersection(validIDs)
        }
    }

    private func handleTopLeadingTap() {
        if !isSelectingEntries {
            dismiss()
        } else if allSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(entries.map(\.id))
        }
    }

    private func handleDeleteTapped() {
        reviewStore.remove(ids: selectedEntryIDs)
        selectedIDs.removeAll()
    }

    private func toggleSelection(for ids: [UUID]) {
        selectedIDs = ConsecutivePlayGrouper.toggleSelection(for: ids, in: selectedIDs)
    }

    private func visibleSourceLabel(for origin: ScrobbleBacklog.Origin) -> String? {
        switch origin {
        case .playbackHistory:
            return nil
        case .recentlyPlayed:
            return NSLocalizedString("Recently Played API", comment: "")
        case .live:
            return NSLocalizedString("Live", comment: "")
        case .manual:
            return NSLocalizedString("Manual", comment: "")
        }
    }

    @MainActor
    private func submitPendingItems() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let submissionIDs = isSelectingEntries ? selectedEntryIDs : nil
        _ = await AppModel.shared.submitPendingListeningHistoryReviewItems(ids: submissionIDs)
        scrobbleLog.reload()
        onSubmitted?()
        selectedIDs.removeAll()

        if reviewStore.pendingEntries().isEmpty {
            dismiss()
        }
    }
}

private extension AppTheme {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}


private struct IsEmbeddedInTabKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isEmbeddedInTab: Bool {
        get { self[IsEmbeddedInTabKey.self] }
        set { self[IsEmbeddedInTabKey.self] = newValue }
    }
}

private struct ScrobbleLogRowView: View {
    let entry: ScrobbleLogStore.Entry
    let consecutivePlayCount: Int
    let isLast: Bool
    let engine: ScrobbleEngine

    var body: some View {
        rowContent
        .frame(maxWidth: .infinity, alignment: .leading)
        // Suppress inherited list animations so new scrobble rows appear instantly rather than sliding in.
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
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if consecutivePlayCount > 1 {
                        ConsecutivePlayCountBadge(count: consecutivePlayCount)
                    }
                }

                HStack(spacing: 6) {
                    Text(entry.track.artist)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .multilineTextAlignment(.leading)
                    if entry.track.artist.isEmpty || entry.track.title.isEmpty {
                        Text("Error")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                if let album = entry.track.album, !album.isEmpty {
                    Text(album)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            HStack(spacing: 8) {
                RelativeScrobbleTimeView(date: displayDate(for: entry))
                if entry.lovedOnLastFM == true {
                    Text("Loved")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                if entry.source != .live {
                    sourceBadge(entry.source)
                }
                Spacer()
            }
            .padding(.top, 2)
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

    private func sourceBadgeBackground(_ source: ScrobbleLogStore.Source) -> Color {
        switch source {
        case .recentlyPlayed:
            return recentTracksBadgeBackground
        case .live, .backlog, .playbackHistory, .manual:
            return Color.secondary.opacity(0.15)
        }
    }

    private func sourceBadgeForeground(_ source: ScrobbleLogStore.Source) -> Color {
        switch source {
        case .recentlyPlayed:
            return recentTracksBadgeForeground
        case .live, .backlog, .playbackHistory, .manual:
            return .primary
        }
    }

    private var recentTracksBadgeBackground: Color {
        Color(
            UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor(red: 0.20, green: 0.40, blue: 0.68, alpha: 1.0)
                }
                return UIColor(red: 0.82, green: 0.92, blue: 1.0, alpha: 1.0)
            }
        )
    }

    private var recentTracksBadgeForeground: Color {
        Color(
            UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return .white
                }
                return UIColor(red: 0.00, green: 0.29, blue: 0.56, alpha: 1.0)
            }
        )
    }

    @ViewBuilder
    private func sourceBadge(_ source: ScrobbleLogStore.Source) -> some View {
        Text(sourceLabel(source))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(sourceBadgeForeground(source))
            .background {
                Capsule(style: .continuous)
                    .fill(sourceBadgeBackground(source))
            }
            .compositingGroup()
    }

    private func displayDate(for entry: ScrobbleLogStore.Entry) -> Date {
        if entry.source == .playbackHistory || entry.source == .recentlyPlayed {
            return Date(timeIntervalSince1970: TimeInterval(entry.startTimestamp))
        }
        return entry.scrobbledAt
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

#if os(iOS)
private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#elseif os(macOS)
private struct InAppSafariView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url != url else { return }
        nsView.load(URLRequest(url: url))
    }
}
#endif

extension View {
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
        onChange(of: value) { _, newValue in
            action(newValue)
        }
    }
}

struct IOSCloseButtonLabel: View {
    enum Style {
        case plain
        case floating
    }

    let style: Style

    init(style: Style = .floating) {
        self.style = style
    }

    var body: some View {
        let icon = Image(systemName: "xmark")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)

        switch style {
        case .plain:
            icon
        case .floating:
            icon
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .contentShape(Circle())
        }
    }
}

extension View {
    @ViewBuilder
    func pillButtonBorder() -> some View {
        self.buttonBorderShape(.capsule)
    }

    func buttonGlow(_ color: Color) -> some View {
        self.overlay {
            Capsule(style: .continuous)
                .strokeBorder(.clear, lineWidth: 1.5)
                // .shadow(color: color.opacity(0.44), radius: 8, x: 0, y: 0)
                // .shadow(color: color.opacity(0.48), radius: 4, x: 0, y: 0)
        }
    }

    func prominentButtonBackground(_ color: Color) -> some View {
        self.background {
            Capsule(style: .continuous)
                .fill(color.opacity(0))
        }
    }

    func brightButtonBorder(_ color: Color, showsShadow: Bool = true) -> some View {
        self.overlay {
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.75), lineWidth: 2)
                .shadow(color: showsShadow ? color.opacity(0.22) : .clear, radius: 4, x: 0, y: 0)
                .shadow(color: showsShadow ? color.opacity(0.18) : .clear, radius: 2, x: 0, y: 0)
        }
    }
}
