#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if os(iOS)
import SafariServices
#endif
import SwiftUI

struct ContentView: View {
    private enum Keys {
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @EnvironmentObject private var pro: ProPurchaseManager

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Keys.hasSeenSetup) private var hasSeenSetup = false

    @State private var errorText: String?
    @State private var isShowingSetup = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingHelp = false
    @State private var isShowingSettings = false
#if os(iOS)
    @State private var isShowingProUpgrade = false
    @State private var inAppBrowserURL: URL?
#endif
#if os(macOS)
    @State private var mediaLibraryStatus: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
#endif

	    var body: some View {
	        Group {
#if os(macOS)
	            // On macOS, `NavigationView` defaults to a split view (sidebar + detail).
	            // Use a single-column stack to avoid the empty detail column.
	            NavigationStack {
	                mainContent
	            }
#else
	            NavigationView {
	                mainContent
	            }
#endif
	        }
	#if os(macOS)
	        .onReceive(NotificationCenter.default.publisher(for: .fastScrobblerPopoverWillShow)) { _ in
	            refreshMediaLibraryStatusIfNeeded()
	        }
	#endif
	        .onAppear {
	            refreshMediaLibraryStatusIfNeeded()
	            presentSetupIfNeeded()
                presentWhatsNewIfNeeded()
	        }
        .onValueChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshMediaLibraryStatusIfNeeded()
            presentSetupIfNeeded()
            presentWhatsNewIfNeeded()
            if hasSeenSetup {
                Task { @MainActor in
	                    await AppModel.shared.startIfNeeded()
	                }
	            }
	        }
        .onValueChange(of: observer.authorizationStatus) { _ in
            refreshMediaLibraryStatusIfNeeded()
            presentSetupIfNeeded()
        }
        .onValueChange(of: hasSeenSetup) { hasSeenSetup in
            guard hasSeenSetup else { return }
            presentWhatsNewIfNeeded()
        }
#if os(macOS)
        .overlay {
            macModalOverlay
        }
#else
        .fullScreenCover(isPresented: $isShowingSetup) {
            SetupHelpView(mode: .onboarding) {
                guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
                guard auth.sessionKey != nil else { return }
                hasSeenSetup = true
                isShowingSetup = false
                presentWhatsNewIfNeeded()
                Task { @MainActor in
                    await AppModel.shared.startIfNeeded()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingWhatsNew) {
            WhatsNewView {
                dismissWhatsNew()
            }
        }
        .fullScreenCover(isPresented: $isShowingHelp) {
            SetupHelpView(mode: .help) {
                isShowingHelp = false
            }
        }
#endif
#if os(iOS)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingProUpgrade) {
            ProUpgradeView()
        }
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
#endif
    }

    private var mainContent: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if os(macOS)
                    macAttentionBanner
#endif
                    statusCard
                    trackCard
                    controls
                        .padding(.top, 12)
                    scrobbleLogCard
                    if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                .padding()
#if os(macOS)
                // Leave room for the top-right popover buttons.
                .padding(.top, MacFloatingBarLayout.contentTopPadding)
#endif
            }

#if os(macOS)
            macPopoverTopButtons
                .padding(.top, 10)
                .padding(.trailing, 10)
#endif
        }
        .navigationTitle("")
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isShowingProUpgrade = true
                } label: {
                    proButtonLabel
                }
                .padding(.trailing, -6)
                .accessibilityLabel("FastScrobbler Pro")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")

                Button {
                    isShowingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
#endif
        }
    }

#if os(iOS)
    private var proButtonLabel: some View {
        Text("Pro")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.yellow, in: Capsule())
    }
#endif

#if os(macOS)
    private var macPopoverTopButtons: some View {
        MacCapsuleBar {
            HStack(spacing: 10) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(6)
                }
                .help("Settings")
                .accessibilityLabel("Settings")

                Button {
                    isShowingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(6)
                }
                .help("Help")
                .accessibilityLabel("Help")
            }
        }
    }
#endif

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last.fm")
                .font(.title2.weight(.semibold))
            if auth.sessionKey != nil {
                Text("Connected").foregroundColor(.green)
            } else {
                Text("Not connected").foregroundColor(.secondary)
            }
            engineStatusText(engine.statusText)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var trackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Now Playing")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            if let t = observer.track {
                Text("\(t.artist) - \(t.title)")
                if let album = t.album, !album.isEmpty {
                    Text(album).foregroundColor(.secondary)
                }
                if let d = t.durationSeconds {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Duration: %@s | Playback: %@s", comment: ""),
                            String(Int(d)),
                            String(Int(observer.playbackTimeSeconds))
                        )
                    )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Text("State: \(playbackStateText(observer.playbackState))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("No track detected.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var controls: some View {
        let actionButtonHeight: CGFloat = {
#if os(macOS)
            return 40
#else
            return 48
#endif
        }()
        let actionButtonSpacing: CGFloat = 12

        return VStack(spacing: 12) {
            Button {
                if let url = URL(string: "music://") {
                    openURL(url)
                }
            } label: {
                Label("Open Music App", systemImage: "music.note")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
            }
            .buttonStyle(.borderedProminent)
            .pillButtonBorder()
            .tint(.red)

            HStack(spacing: actionButtonSpacing) {
                Button {
                    engine.setUserPaused(!engine.isUserPaused)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engine.isUserPaused ? "play.fill" : "pause.fill")
                        Text(engine.isUserPaused ? NSLocalizedString("Resume", comment: "") : NSLocalizedString("Pause", comment: ""))
                    }
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(engine.isUserPaused ? .green : .orange)
                .disabled(auth.sessionKey == nil)

                if auth.sessionKey == nil {
                    Button {
                        Task { await connectTapped() }
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle")
                            .font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .pillButtonBorder()
                    .tint(.blue)
                } else {
                    Button {
                        Task { await engine.scrobbleNow(force: true) }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "memories.badge.plus")
                            Text("Scrobble Now")
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                        }
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .pillButtonBorder()
                    .tint(.purple)
                    .disabled(engine.isUserPaused)
                }
            }

            if auth.sessionKey != nil {
                Button {
                    if let url = auth.freshProfileURL() {
#if os(iOS)
                        inAppBrowserURL = url
#else
                        openURL(url)
#endif
                    }
                } label: {
                    Label("View Profile in Last.fm", systemImage: "person.circle")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
                .disabled(auth.profileURL == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

	#if os(macOS)
	    @ViewBuilder
	    private var macAttentionBanner: some View {
	        let isLoggedOut = (auth.sessionKey == nil)
	        let isMediaLibraryPermissionOff = (mediaLibraryStatus != .authorized)
	        let isMusicControlPermissionOff = (observer.authorizationStatus != .authorized)
	        if isLoggedOut || isMediaLibraryPermissionOff || isMusicControlPermissionOff {
	            VStack(alignment: .leading, spacing: 10) {
	                if isLoggedOut {
	                    Label(
	                        "You’re signed out of Last.fm.",
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

	                    if isMediaLibraryPermissionOff {
	                        Button("Request Media Library Access") {
	                            Task { @MainActor in
	                                let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { cont in
	                                    MPMediaLibrary.requestAuthorization { s in
                                        cont.resume(returning: s)
                                    }
                                }
                                mediaLibraryStatus = status
                                guard status == .authorized else { return }
	                                await AppModel.shared.startIfNeeded()
	                            }
	                        }
	                        .buttonStyle(.bordered)
	                        .tint(.white)
	                    }

	                    if isMusicControlPermissionOff {
	                        Button("Request Music Control Access") {
	                            Task { @MainActor in
	                                await observer.requestMusicControlPermission()
	                            }
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
	#endif

    private func presentSetupIfNeeded() {
#if os(macOS)
        let shouldShow = (!hasSeenSetup || auth.sessionKey == nil || observer.authorizationStatus != .authorized)
        guard shouldShow else { return }

        isShowingHelp = false
        isShowingSettings = false
        if !isShowingSetup {
            isShowingSetup = true
        }
#else
        let mediaAuthorized = (MPMediaLibrary.authorizationStatus() == .authorized)
        let shouldShow = (!hasSeenSetup || !mediaAuthorized || auth.sessionKey == nil)
        guard shouldShow else { return }

        isShowingHelp = false
        isShowingSettings = false
        if !isShowingSetup {
            isShowingSetup = true
        }
#endif
    }

#if os(macOS)
	    private func refreshMediaLibraryStatusIfNeeded() {
	        mediaLibraryStatus = MPMediaLibrary.authorizationStatus()
	        observer.refreshOnceIfAuthorized()

	        if hasSeenSetup, auth.sessionKey != nil, observer.authorizationStatus == .authorized {
	            Task { @MainActor in
	                await AppModel.shared.startIfNeeded()
	            }
	        }
	    }
#else
	    private func refreshMediaLibraryStatusIfNeeded() {}
#endif

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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let entries = Array(scrobbleLog.entries.prefix(30))
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.track.artist) — \(entry.track.title)")
                                    .font(.subheadline.weight(.semibold))
                                if let album = entry.track.album, !album.isEmpty {
                                    Text(album)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Text(relativeHoursMinutes(from: entry.scrobbledAt, to: context.date))
                                    if entry.lovedOnLastFM == true {
                                        Text("Loved")
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .foregroundColor(.white)
                                            .background(Color.red)
                                            .clipShape(Capsule())
                                    }
                                    if entry.source != .live {
                                        Text(sourceLabel(entry.source))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private func sourceLabel(_ source: ScrobbleLogStore.Source) -> String {
        switch source {
        case .live: return ""
        case .backlog: return NSLocalizedString("Backlog", comment: "")
        case .playbackHistory: return NSLocalizedString("Listening History", comment: "")
        case .recentlyPlayed: return NSLocalizedString("Recently Played", comment: "")
        }
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

    private func playbackStateText(_ s: MPMusicPlaybackState) -> String {
        switch s {
        case .stopped: return NSLocalizedString("stopped", comment: "")
        case .playing: return NSLocalizedString("playing", comment: "")
        case .paused: return NSLocalizedString("paused", comment: "")
        case .interrupted: return NSLocalizedString("interrupted", comment: "")
        case .seekingForward: return NSLocalizedString("seeking forward", comment: "")
        case .seekingBackward: return NSLocalizedString("seeking backward", comment: "")
        @unknown default: return NSLocalizedString("unknown", comment: "")
        }
    }

    private func relativeHoursMinutes(from date: Date, to now: Date) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        let totalMinutes = Int(delta / 60)
        if totalMinutes < 60 {
            return String.localizedStringWithFormat(NSLocalizedString("%lldm ago", comment: ""), Int64(totalMinutes))
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return String.localizedStringWithFormat(NSLocalizedString("%lldh ago", comment: ""), Int64(hours))
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("%1$lldh %2$lldm ago", comment: ""),
            Int64(hours),
            Int64(minutes)
        )
    }

    private func engineStatusText(_ status: String) -> Text {
        let parts = status
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var text = Text("Engine: ")
        for (idx, part) in parts.enumerated() {
            if idx > 0 { text = text + Text(" | ") }
            let segment = Text(part)
            if part == NSLocalizedString("now playing sent", comment: "") || part == NSLocalizedString("scrobbled", comment: "") {
                text = text + segment.fontWeight(.bold)
            } else {
                text = text + segment
            }
        }
        return text
    }

    private func presentWhatsNewIfNeeded() {
#if os(macOS)
        return
#else
        guard hasSeenSetup else { return }
        guard !isShowingSetup && !isShowingWhatsNew && !isShowingHelp && !isShowingSettings else { return }
        guard !isShowingProUpgrade && inAppBrowserURL == nil else { return }
        if WhatsNewRelease.shouldPresent() {
            isShowingWhatsNew = true
        }
#endif
    }

    private func dismissWhatsNew() {
        WhatsNewRelease.markSeen()
        isShowingWhatsNew = false
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
#endif

extension View {
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
#if os(iOS)
        onChange(of: value) { _, newValue in
            action(newValue)
        }
#elseif os(macOS)
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
#endif
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
            .font(.system(size: 17, weight: .semibold))
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
#if os(macOS)
        if #available(macOS 14.0, *) {
            self.buttonBorderShape(.capsule)
        } else {
            self.buttonBorderShape(.roundedRectangle)
        }
#else
        self.buttonBorderShape(.capsule)
#endif
    }
}

#if os(macOS)
enum MacFloatingBarLayout {
    /// Extra top padding (in addition to the view's normal padding) to keep content from sitting under the floating capsule buttons.
    static let contentTopPadding: CGFloat = 52
    /// Reduced top padding for screens that only show a single floating circle button (e.g. a back button).
    static let circleButtonContentTopPadding: CGFloat = 28
}

struct MacCapsuleBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
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
                .font(.system(size: 16, weight: .semibold))
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
    private var macModalOverlay: some View {
        let isPresented = (isShowingSetup || isShowingHelp || isShowingSettings)
        if isPresented {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
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
    private var macModalContent: some View {
        if isShowingSetup {
            SetupHelpView(mode: .onboarding, onOpenSettings: {
                isShowingSetup = false
                isShowingSettings = true
            }) {
                hasSeenSetup = true
                isShowingSetup = false
                presentWhatsNewIfNeeded()
                Task { @MainActor in
                    await AppModel.shared.startIfNeeded()
                }
            }
        } else if isShowingHelp {
            SetupHelpView(mode: .help, onOpenSettings: {
                isShowingHelp = false
                isShowingSettings = true
            }) {
                isShowingHelp = false
            }
        } else if isShowingSettings {
            SettingsView(onBack: { isShowingSettings = false })
        }
    }

    private func dismissMacModal() {
        if isShowingSettings {
            isShowingSettings = false
        } else if isShowingHelp {
            isShowingHelp = false
        } else if isShowingSetup {
            // Keep onboarding visible until the setup requirements are actually satisfied.
            return
        }
    }
}
#endif
