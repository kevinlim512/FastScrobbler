import AppKit
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if os(macOS)
import ServiceManagement
#endif
import SwiftUI

struct SetupHelpView: View {
    private enum Keys {
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    private static let redditSubmitURL = URL(string: "https://www.reddit.com/r/FastScrobbler/submit/")!
    private static let redditSubmitPlainSubtitle = "Submit a post to r/FastScrobbler, and FastScrobbler will respond to your post."
    private static let redditSubmitMarkdownSubtitle = "[Submit a post to r/FastScrobbler](https://www.reddit.com/r/FastScrobbler/submit/), and FastScrobbler will respond to your post."

    private enum CardPalette {
        static let backgroundOverlay = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.96),
            dark: NSColor(white: 0.10, alpha: 0.86)
        )
        static let border = dynamicColor(
            light: NSColor(white: 0.0, alpha: 0.10),
            dark: NSColor(white: 1.0, alpha: 0.16)
        )
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

    enum Mode {
        case onboarding
        case help
    }

    let mode: Mode
    let onOpenSettings: (() -> Void)?
    let onOpenListenBrainzConnect: (() -> Void)?
    let onDone: () -> Void

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var permissions: PermissionStatusStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var startAtLoginEnabled = Self.isStartAtLoginEnabled
    @State private var isSigningInToLastFM = false
    @State private var lastFMErrorText: String?
    @State private var isShowingListenBrainzConnectSheet = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private var contentCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CardPalette.backgroundOverlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CardPalette.border, lineWidth: 1)
            }
    }

    private var canFinishSetup: Bool {
        (auth.sessionKey != nil || listenBrainzAuth.isConnected) && permissions.automationStatus == .authorized
    }

    init(mode: Mode, onOpenSettings: (() -> Void)? = nil, onOpenListenBrainzConnect: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.mode = mode
        self.onOpenSettings = onOpenSettings
        self.onOpenListenBrainzConnect = onOpenListenBrainzConnect
        self.onDone = onDone
    }

    private struct HelpRow: View {
        let icon: String
        let title: String
        let subtitle: AttributedString
        let isChecked: Bool
        let showsUncheckedStatus: Bool
        let actionTitle: String?
        let action: (() -> Void)?
        let actionTint: Color?
        let actionProminent: Bool
        let actionDisabled: Bool
        let contentCardBackground: AnyView

        init(
            icon: String,
            title: String,
            subtitle: String,
            isChecked: Bool = false,
            showsUncheckedStatus: Bool = false,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            actionTint: Color? = nil,
            actionProminent: Bool = false,
            actionDisabled: Bool = false,
            contentCardBackground: AnyView
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = AttributedString(subtitle)
            self.isChecked = isChecked
            self.showsUncheckedStatus = showsUncheckedStatus
            self.actionTitle = actionTitle
            self.action = action
            self.actionTint = actionTint
            self.actionProminent = actionProminent
            self.actionDisabled = actionDisabled
            self.contentCardBackground = contentCardBackground
        }

        init(
            icon: String,
            title: String,
            subtitle: AttributedString,
            isChecked: Bool = false,
            showsUncheckedStatus: Bool = false,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            actionTint: Color? = nil,
            actionProminent: Bool = false,
            actionDisabled: Bool = false,
            contentCardBackground: AnyView
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.isChecked = isChecked
            self.showsUncheckedStatus = showsUncheckedStatus
            self.actionTitle = actionTitle
            self.action = action
            self.actionTint = actionTint
            self.actionProminent = actionProminent
            self.actionDisabled = actionDisabled
            self.contentCardBackground = contentCardBackground
        }

        var body: some View {
            let showsStatusBadge = isChecked || showsUncheckedStatus
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        if showsStatusBadge {
                            statusBadge(isEnabled: isChecked)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                        .tint(.accentColor)

                    if let actionTitle, let action {
                        actionButton(title: actionTitle, action: action)
                            .disabled(actionDisabled)
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 2)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(contentCardBackground)
        }

        private func statusBadge(isEnabled: Bool) -> some View {
            HStack(spacing: 6) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(NSLocalizedString(isEnabled ? "Enabled" : "Not Enabled", comment: ""))
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? .green : .red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((isEnabled ? Color.green : Color.red).opacity(0.12), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }

        @ViewBuilder
        private func actionButton(title: String, action: @escaping () -> Void) -> some View {
            if actionProminent {
                Button(title) { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(actionTint)
            } else {
                Button(title) { action() }
                    .tint(actionTint)
            }
        }
    }

    private enum StatusLevel {
        case good
        case warning
        case bad
        case tip
    }

    private struct StatusBadge: View {
        let text: String
        let level: StatusLevel

        var body: some View {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(background)
                .clipShape(Capsule())
        }

        private var foreground: Color {
            switch level {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            case .tip: return .blue
            }
        }

        private var background: Color {
            switch level {
            case .good: return .green.opacity(0.12)
            case .warning: return .orange.opacity(0.12)
            case .bad: return .red.opacity(0.12)
            case .tip: return .blue.opacity(0.12)
            }
        }
    }

    private struct ServiceSubRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let badgeText: String
        let badgeLevel: StatusLevel
        let actionTitle: String?
        let action: (() -> Void)?
        let actionDisabled: Bool
        let actionTint: Color?
        let actionProminent: Bool

        init(
            icon: String,
            title: String,
            subtitle: String,
            badgeText: String,
            badgeLevel: StatusLevel,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            actionDisabled: Bool = false,
            actionTint: Color? = nil,
            actionProminent: Bool = false
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.badgeText = badgeText
            self.badgeLevel = badgeLevel
            self.actionTitle = actionTitle
            self.action = action
            self.actionDisabled = actionDisabled
            self.actionTint = actionTint
            self.actionProminent = actionProminent
        }

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        StatusBadge(text: badgeText, level: badgeLevel)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        actionButton(title: actionTitle, action: action)
                            .disabled(actionDisabled)
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        @ViewBuilder
        private func actionButton(title: String, action: @escaping () -> Void) -> some View {
            if actionProminent {
                Button(title) { action() }
                    .buttonStyle(.borderedProminent)
                    .tint(actionTint)
            } else {
                Button(title) { action() }
                    .tint(actionTint)
            }
        }
    }

    private var scrobbleServicesGroupCard: some View {
        let isLastFMConnected = (auth.sessionKey != nil)
        let isListenBrainzConnected = listenBrainzAuth.isConnected
        let hasAnyAccount = isLastFMConnected || isListenBrainzConnected

        let overallBadgeText = hasAnyAccount ? NSLocalizedString("Signed in", comment: "") : NSLocalizedString("Required", comment: "")
        let overallBadgeLevel: StatusLevel = hasAnyAccount ? .good : .bad

        let lastFMBadgeText = isLastFMConnected ? NSLocalizedString("Signed in", comment: "") : NSLocalizedString("Not connected", comment: "")
        let lastFMBadgeLevel: StatusLevel = isLastFMConnected ? .good : .warning

        let lastFMSubtitle: String = {
            if isLastFMConnected {
                if let username = auth.username, !username.isEmpty {
                    return String(format: NSLocalizedString("Signed in as %@", comment: ""), username)
                }
                return NSLocalizedString("Signed in to your Last.fm account.", comment: "")
            }
            return NSLocalizedString("Sign in to start scrobbling to your Last.fm account.", comment: "")
        }()

        let listenBrainzBadgeText = isListenBrainzConnected ? NSLocalizedString("Signed in", comment: "") : NSLocalizedString("Not connected", comment: "")
        let listenBrainzBadgeLevel: StatusLevel = isListenBrainzConnected ? .good : .warning

        let listenBrainzSubtitle: String = {
            if isListenBrainzConnected {
                if let username = listenBrainzAuth.username, !username.isEmpty {
                    return String(format: NSLocalizedString("Beta feature: Signed in as %@", comment: ""), username)
                }
                return NSLocalizedString("Beta feature: Signed in to your ListenBrainz account.", comment: "")
            }
            return NSLocalizedString("Beta feature: Sign in to start scrobbling to your ListenBrainz account.", comment: "")
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(NSLocalizedString("Scrobble Services", comment: ""))
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        Spacer(minLength: 0)

                        StatusBadge(text: overallBadgeText, level: overallBadgeLevel)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(NSLocalizedString("Choose at least one service to start scrobbling.", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ServiceSubRow(
                icon: "person.crop.circle",
                title: NSLocalizedString("Last.fm", comment: ""),
                subtitle: lastFMSubtitle,
                badgeText: lastFMBadgeText,
                badgeLevel: lastFMBadgeLevel,
                actionTitle: isLastFMConnected ? nil : (isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In to Last.fm", comment: "")),
                action: isLastFMConnected ? nil : signInToLastFM,
                actionDisabled: isSigningInToLastFM,
                actionTint: .red,
                actionProminent: true
            )

            Divider()

            ServiceSubRow(
                icon: "waveform.path.ecg",
                title: NSLocalizedString("ListenBrainz", comment: ""),
                subtitle: listenBrainzSubtitle,
                badgeText: listenBrainzBadgeText,
                badgeLevel: listenBrainzBadgeLevel,
                actionTitle: isListenBrainzConnected ? nil : NSLocalizedString("Sign In to ListenBrainz", comment: ""),
                action: isListenBrainzConnected ? nil : {
                    if let onOpenListenBrainzConnect {
                        onOpenListenBrainzConnect()
                    } else {
                        isShowingListenBrainzConnectSheet = true
                    }
                },
                actionDisabled: false,
                actionTint: nil,
                actionProminent: false
            )
        }
        .padding(.top, 2)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentCardBackground)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    scrobbleServicesGroupCard

                    let musicControlAllowed = (permissions.automationStatus == .authorized)
                    let musicControlActionTitle: String? = {
                        guard !musicControlAllowed else { return nil }
                        switch permissions.automationStatus {
                        case .notDetermined:
                            return NSLocalizedString("Allow Music Control", comment: "")
                        case .denied, .restricted:
                            return NSLocalizedString("Open System Settings", comment: "")
                        case .authorized:
                            return nil
                        }
                    }()
                    let musicControlAction: (() -> Void)? = {
                        guard !musicControlAllowed else { return nil }
                        switch permissions.automationStatus {
                        case .notDetermined:
                            return requestMusicControlPermission
                        case .denied, .restricted:
                            return { openPrivacySettings(kind: .automation) }
                        case .authorized:
                            return nil
                        }
                    }()
                    HelpRow(
                        icon: "music.note",
                        title: NSLocalizedString("Allow Music Control", comment: ""),
                        subtitle: NSLocalizedString("When macOS asks to let FastScrobbler control Music, click Allow. This lets FastScrobbler read what’s playing for scrobbling.", comment: ""),
                        isChecked: musicControlAllowed,
                        showsUncheckedStatus: true,
                        actionTitle: musicControlActionTitle,
                        action: musicControlAction,
                        contentCardBackground: AnyView(contentCardBackground)
                    )

                    let mediaAllowed = (permissions.mediaLibraryStatus == .authorized)
                    let mediaActionTitle: String? = {
                        guard !mediaAllowed else { return nil }
                        switch permissions.mediaLibraryStatus {
                        case .notDetermined:
                            return NSLocalizedString("Request Access", comment: "")
                        case .denied, .restricted:
                            return NSLocalizedString("Open Media Library Settings", comment: "")
                        case .authorized:
                            return nil
                        }
                    }()
                    let mediaAction: (() -> Void)? = {
                        guard !mediaAllowed else { return nil }
                        switch permissions.mediaLibraryStatus {
                        case .notDetermined:
                            return requestMediaLibraryPermission
                        case .denied, .restricted:
                            return { openPrivacySettings(kind: .media) }
                        case .authorized:
                            return nil
                        }
                    }()
                    HelpRow(
                        icon: "music.note.list",
                        title: NSLocalizedString("Media Library Permission", comment: ""),
                        subtitle: NSLocalizedString("If Media Library access is off, enable it in System Settings.", comment: ""),
                        isChecked: mediaAllowed,
                        showsUncheckedStatus: true,
                        actionTitle: mediaActionTitle,
                        action: mediaAction,
                        contentCardBackground: AnyView(contentCardBackground)
                    )

                    HelpRow(
                        icon: "play.circle.fill",
                        title: NSLocalizedString("Start playing music", comment: ""),
                        subtitle: NSLocalizedString("Start playing music! FastScrobbler will show Now Playing and scrobble when eligible.", comment: ""),
                        contentCardBackground: AnyView(contentCardBackground)
                    )

                    HelpRow(
                        icon: "waveform.path.ecg",
                        title: NSLocalizedString("Auto-scrobble troubleshooting", comment: ""),
                        subtitle: NSLocalizedString("If \"Scrobble Now\" works but auto-scrobble does not, FastScrobbler is usually blocking the play because playback state or duplicate checks do not look trustworthy yet. Check the status card for the exact blocker.", comment: ""),
                        contentCardBackground: AnyView(contentCardBackground)
                    )

                    HelpRow(
                        icon: "power.circle",
                        title: NSLocalizedString("Start at login", comment: ""),
                        subtitle: NSLocalizedString("Optional: turn this on in Settings if you want FastScrobbler to launch when you sign in to your Mac.", comment: ""),
                        isChecked: startAtLoginEnabled,
                        contentCardBackground: AnyView(contentCardBackground)
                    )

                    HelpRow(
                        icon: "questionmark.bubble",
                        title: NSLocalizedString("Questions or Bug Reports?", comment: ""),
                        subtitle: redditSubmitSubtitle,
                        contentCardBackground: AnyView(contentCardBackground)
                    )
                }

                Button {
                    onDone()
                } label: {
                    Text(mode == .onboarding ? NSLocalizedString("Continue", comment: "") : NSLocalizedString("Done", comment: ""))
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .onboarding && !canFinishSetup)

                if mode == .onboarding && !canFinishSetup {
                    Text(localized("Connect Last.fm or ListenBrainz and allow Music control before continuing."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .padding(.top, MacFloatingBarLayout.circleButtonContentTopPadding)
        }
        .background(PagePalette.background)
        .onAppear { refreshStatuses() }
        .onValueChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshStatuses()
        }
        .alert(NSLocalizedString("Couldn't sign in to Last.fm", comment: ""), isPresented: Binding(
            get: { lastFMErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    lastFMErrorText = nil
                }
            }
        )) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(lastFMErrorText ?? "")
        }
        .overlay(alignment: .topLeading) {
            if mode == .help {
                MacFloatingCircleButton(
                    systemImage: "chevron.left",
                    help: NSLocalizedString("Back", comment: ""),
                    accessibilityLabel: NSLocalizedString("Back", comment: ""),
                    action: onDone
                )
                .padding(.top, 10)
                .padding(.leading, 10)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(mode == .help ? localized("Help") : localized("Setup"))
                .font(.system(size: 28, weight: .bold))
            Text(localized("A quick checklist to get scrobbling working reliably."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var redditSubmitSubtitle: AttributedString {
        let localizedMarkdown = NSLocalizedString(Self.redditSubmitMarkdownSubtitle, comment: "")
        if let subtitle = try? AttributedString(
            markdown: localizedMarkdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return subtitle
        }

        return AttributedString(NSLocalizedString(Self.redditSubmitPlainSubtitle, comment: ""))
    }

    private enum PrivacyKind {
        case media
        case automation
    }

    private func openPrivacySettings(kind: PrivacyKind) {
        let primary: URL? = {
            switch kind {
            case .media:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")
            case .automation:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }
        }()

        if let primary {
            openURL(primary)
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            openURL(fallback)
        }
    }

    private func refreshStatuses() {
        startAtLoginEnabled = Self.isStartAtLoginEnabled
        Task { @MainActor in
            await permissions.refreshNow(observer: observer)
            observer.refreshOnceIfAuthorized()
        }
    }

    private static var isStartAtLoginEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    private func requestMediaLibraryPermission() {
        Task { @MainActor in
            _ = await withCheckedContinuation { cont in
                MPMediaLibrary.requestAuthorization { _ in
                    cont.resume(returning: ())
                }
            }
            await permissions.refreshNow(observer: observer)
            refreshStatuses()
            await maybeStartScrobblingIfSetupAlreadyCompleted()
        }
    }

    private func requestMusicControlPermission() {
        Task { @MainActor in
            await observer.requestMusicControlPermission()
            await permissions.refreshNow(observer: observer)
            refreshStatuses()
            await maybeStartScrobblingIfSetupAlreadyCompleted()
        }
    }

    private func signInToLastFM() {
        guard auth.sessionKey == nil else { return }
        guard !isSigningInToLastFM else { return }
        isSigningInToLastFM = true
        lastFMErrorText = nil

        Task { @MainActor in
            defer { isSigningInToLastFM = false }
            do {
                try await auth.connect()
                refreshStatuses()
                await maybeStartScrobblingIfSetupAlreadyCompleted()
            } catch {
                if error is CancellationError { return }
                lastFMErrorText = error.localizedDescription
            }
        }
    }

    private func maybeStartScrobblingIfSetupAlreadyCompleted() async {
        guard UserDefaults.standard.bool(forKey: Keys.hasSeenSetup) || mode == .help else { return }
        guard (auth.sessionKey != nil || listenBrainzAuth.isConnected), permissions.automationStatus == .authorized else { return }
        AppModel.shared.startIfNeeded()
    }
}
