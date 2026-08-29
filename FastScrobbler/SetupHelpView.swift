import MediaPlayer
import SwiftUI
import UIKit

struct SetupHelpView: View {
    private static let redditSubmitURL = URL(string: "https://www.reddit.com/r/FastScrobbler/submit/")!

    enum Mode {
        case setup
        case help
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
            case .bad: return .accentColor
            case .tip: return .blue
            }
        }

        private var background: Color {
            switch level {
            case .good: return .green.opacity(0.12)
            case .warning: return .orange.opacity(0.12)
            case .bad: return Color.accentColor.opacity(0.12)
            case .tip: return .blue.opacity(0.12)
            }
        }
    }

    private struct SettingRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let attributedSubtitle: AttributedString?
        let badgeText: String
        let badgeLevel: StatusLevel
        let actionTitle: String?
        let action: (() -> Void)?
        let actionSystemImage: String?
        let actionDisabled: Bool
        let actionProminent: Bool
        let actionTint: Color?

        init(
            icon: String,
            title: String,
            subtitle: String,
            attributedSubtitle: AttributedString? = nil,
            badgeText: String,
            badgeLevel: StatusLevel,
            actionTitle: String?,
            action: (() -> Void)?,
            actionSystemImage: String? = nil,
            actionDisabled: Bool = false,
            actionProminent: Bool = false,
            actionTint: Color? = nil
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.attributedSubtitle = attributedSubtitle
            self.badgeText = badgeText
            self.badgeLevel = badgeLevel
            self.actionTitle = actionTitle
            self.action = action
            self.actionSystemImage = actionSystemImage
            self.actionDisabled = actionDisabled
            self.actionProminent = actionProminent
            self.actionTint = actionTint
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        StatusBadge(text: badgeText, level: badgeLevel)
                            .hidden()
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let attributedSubtitle {
                        Text(attributedSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let actionTitle, let action {
                        if actionProminent {
                            Button {
                                action()
                            } label: {
                                Group {
                                    if let actionSystemImage {
                                        Label(actionTitle, systemImage: actionSystemImage)
                                    } else {
                                        Text(actionTitle)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                                .disabled(actionDisabled)
                                .buttonStyle(GiantPillButtonStyle(tint: actionTint ?? .accentColor))
                                .padding(.top, 10)
                        } else {
                            Button(actionTitle) { action() }
                                .disabled(actionDisabled)
                                .font(.subheadline.weight(.semibold))
                                .tint(actionTint)
                                .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                StatusBadge(text: badgeText, level: badgeLevel)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding()
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
        let actionSystemImage: String?
        let actionDisabled: Bool
        let actionTint: Color
        let actionForeground: Color

        init(
            icon: String,
            title: String,
            subtitle: String,
            badgeText: String,
            badgeLevel: StatusLevel,
            actionTitle: String?,
            action: (() -> Void)?,
            actionSystemImage: String? = nil,
            actionDisabled: Bool = false,
            actionTint: Color = .accentColor,
            actionForeground: Color = .white
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.badgeText = badgeText
            self.badgeLevel = badgeLevel
            self.actionTitle = actionTitle
            self.action = action
            self.actionSystemImage = actionSystemImage
            self.actionDisabled = actionDisabled
            self.actionTint = actionTint
            self.actionForeground = actionForeground
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        Spacer()

                        StatusBadge(text: badgeText, level: badgeLevel)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        Button {
                            action()
                        } label: {
                            Group {
                                if let actionSystemImage {
                                    Label(actionTitle, systemImage: actionSystemImage)
                                } else {
                                    Text(actionTitle)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(actionDisabled)
                        .buttonStyle(GiantPillButtonStyle(tint: actionTint, foreground: actionForeground))
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct GiantPillButtonStyle: ButtonStyle {
        let tint: Color
        let foreground: Color

        init(tint: Color, foreground: Color = .white) {
            self.tint = tint
            self.foreground = foreground
        }

        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 24)
                .frame(minHeight: 68)
                .background(tint)
                .clipShape(Capsule())
                .shadow(
                    color: .black.opacity(configuration.isPressed ? 0.14 : 0.22),
                    radius: configuration.isPressed ? 6 : 10,
                    y: configuration.isPressed ? 3 : 6
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1.0) : 0.55)
                .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    let mode: Mode
    let onDone: () -> Void

    init(mode: Mode, onDone: @escaping () -> Void) {
        self.mode = mode
        self.onDone = onDone
    }

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var mediaStatus: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .restricted
    @State private var isSigningInToLastFM = false
    @State private var lastFMErrorText: String?
    @State private var isShowingListenBrainzConnectSheet = false

    var body: some View {
        Group {
            if mode == .setup {
                NavigationStack {
                    screenContent
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar(.hidden, for: .navigationBar)
                .interactiveDismissDisabled(true)
            } else {
                screenContent
                    .navigationTitle("Help")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(
            NSLocalizedString("Sign-in Error", comment: ""),
            isPresented: Binding(
                get: { lastFMErrorText != nil },
                set: { if !$0 { lastFMErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastFMErrorText ?? "")
        }
        .sheet(isPresented: $isShowingListenBrainzConnectSheet) {
            ListenBrainzConnectSheet()
                .environmentObject(listenBrainzAuth)
        }
        .onAppear { refreshStatuses() }
        .onValueChange(of: scenePhase) { newValue in
            if newValue == .active {
                refreshStatuses()
            }
        }
    }

    private var screenContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                    .padding(.top, mode == .help ? 12 : 30)

                VStack(spacing: 12) {
                    scrobbleServicesGroupCard
                    mediaLibraryRow
                    backgroundRefreshRow
                    shortcutsAndControlCenterRow
                }

                if mode == .help {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Help")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                        listeningHistoryLibraryOnlyNoteRow
                        autoMixListeningHistoryNoteRow
                        appleMusicAPINoteRow
                        confirmationReviewNoteRow
                        scrobblingIssuesNoteRow
                        questionsOrBugReportsRow
                    }
                }

                if mode == .setup {
                    Button {
                        handlePrimaryAction()
                    } label: {
                        Label(NSLocalizedString("Continue", comment: ""), systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled((auth.sessionKey == nil && !listenBrainzAuth.isConnected) || mediaStatus != .authorized)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func handlePrimaryAction() {
        onDone()
    }

    private var header: some View {
        VStack(spacing: 8) {
            if mode == .setup {
                Text("Setup")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Text("FastScrobbler needs a few permissions and settings to work reliably.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(NSLocalizedString("Scrobble Services", comment: ""))
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        StatusBadge(text: overallBadgeText, level: overallBadgeLevel)
                            .hidden()
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
                action: isLastFMConnected ? nil : {
                    guard !isSigningInToLastFM else { return }
                    isSigningInToLastFM = true
                    Task { @MainActor in
                        defer { isSigningInToLastFM = false }
                        do {
                            try await auth.connect()
                        } catch {
                            if error is CancellationError { return }
                            lastFMErrorText = error.localizedDescription
                        }
                    }
                },
                actionSystemImage: "music.note",
                actionDisabled: isSigningInToLastFM,
                actionTint: .accentColor,
                actionForeground: .white
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
                    isShowingListenBrainzConnectSheet = true
                },
                actionSystemImage: "music.note",
                actionDisabled: false,
                actionTint: Color(uiColor: .systemGray4),
                actionForeground: .primary
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            StatusBadge(text: overallBadgeText, level: overallBadgeLevel)
                .fixedSize(horizontal: true, vertical: false)
                .padding()
        }
    }


    private var mediaLibraryRow: some View {
        let (badgeText, badgeLevel) = badge(for: mediaStatus)
        let action: (() -> Void)?
        let actionTitle: String?
        let actionSystemImage: String?
        let actionProminent: Bool
        let actionTint: Color?

        switch mediaStatus {
        case .authorized:
            action = nil
            actionTitle = nil
            actionSystemImage = nil
            actionProminent = false
            actionTint = nil
        case .notDetermined:
            action = { Task { await requestMediaLibraryPermission() } }
            actionTitle = NSLocalizedString("Enable Media Library", comment: "")
            actionSystemImage = "music.note.list"
            actionProminent = true
            actionTint = .accentColor
        case .denied, .restricted:
            action = openAppSettings
            actionTitle = NSLocalizedString("Open Settings", comment: "")
            actionSystemImage = "gearshape"
            actionProminent = true
            actionTint = .accentColor
        @unknown default:
            action = openAppSettings
            actionTitle = NSLocalizedString("Open Settings", comment: "")
            actionSystemImage = "gearshape"
            actionProminent = true
            actionTint = .accentColor
        }

        return SettingRow(
            icon: "music.note.list",
            title: NSLocalizedString("Media Library", comment: ""),
            subtitle: NSLocalizedString("Required to read Apple Music now-playing metadata.", comment: ""),
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: actionTitle,
            action: action,
            actionSystemImage: actionSystemImage,
            actionProminent: actionProminent,
            actionTint: actionTint
        )
    }

    private var backgroundRefreshRow: some View {
        let (badgeText, badgeLevel) = badge(for: backgroundRefreshStatus)
        let showAction = backgroundRefreshStatus != .available

        return SettingRow(
            icon: "arrow.triangle.2.circlepath",
            title: NSLocalizedString("Background App Refresh", comment: ""),
            subtitle: NSLocalizedString("Recommended to periodically sync when the app is in the background.", comment: ""),
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: showAction ? NSLocalizedString("Open Settings", comment: "") : nil,
            action: showAction ? openAppSettings : nil
        )
    }

    private var shortcutsAndControlCenterRow: some View {
        SettingRow(
            icon: "memories.badge.plus",
            title: NSLocalizedString("Shortcuts & Control Center", comment: ""),
            subtitle: NSLocalizedString("Add Shortcut actions and Control Center buttons for Send Now Playing, Scrobble Song, or Manual Scrobble.", comment: ""),
            badgeText: NSLocalizedString("Tip", comment: ""),
            badgeLevel: .tip,
            actionTitle: nil,
            action: nil
        )
    }

    private var listeningHistoryLibraryOnlyNoteRow: some View {
        SettingRow(
            icon: "clock",
            title: NSLocalizedString("Listening History", comment: ""),
            subtitle: NSLocalizedString("Scrobbling from Listening History only works for songs added to your Library.", comment: ""),
            badgeText: NSLocalizedString("Note", comment: ""),
            badgeLevel: .warning,
            actionTitle: nil,
            action: nil
        )
    }

    private var autoMixListeningHistoryNoteRow: some View {
        SettingRow(
            icon: "shuffle.circle",
            title: NSLocalizedString("AutoMix", comment: ""),
            subtitle: NSLocalizedString("Scrobbling from Listening History may be affected when AutoMix is on.", comment: ""),
            badgeText: NSLocalizedString("Note", comment: ""),
            badgeLevel: .warning,
            actionTitle: nil,
            action: nil
        )
    }

    private var appleMusicAPINoteRow: some View {
        SettingRow(
            icon: "square.and.arrow.down.badge.clock",
            title: NSLocalizedString("Need more plays?", comment: ""),
            subtitle: NSLocalizedString("Turn on \"Scrobble Recently Played from Apple Music API\" if you need to capture more plays, including non-library songs.", comment: ""),
            badgeText: NSLocalizedString("Tip", comment: ""),
            badgeLevel: .tip,
            actionTitle: nil,
            action: nil
        )
    }

    private var confirmationReviewNoteRow: some View {
        SettingRow(
            icon: "checklist",
            title: NSLocalizedString("Don't want auto-scrobbles?", comment: ""),
            subtitle: NSLocalizedString("Turn off \"Auto-scrobble Listening History\" to review items before submitting them.", comment: ""),
            badgeText: NSLocalizedString("Tip", comment: ""),
            badgeLevel: .tip,
            actionTitle: nil,
            action: nil
        )
    }

    private var scrobblingIssuesNoteRow: some View {
        SettingRow(
            icon: "exclamationmark.circle",
            title: NSLocalizedString("Issues Scrobbling?", comment: ""),
            subtitle: NSLocalizedString("Try signing out and signing in again.", comment: ""),
            badgeText: NSLocalizedString("Note", comment: ""),
            badgeLevel: .warning,
            actionTitle: nil,
            action: nil
        )
    }

    private var questionsOrBugReportsRow: some View {
        SettingRow(
            icon: "questionmark.bubble",
            title: NSLocalizedString("Questions or Bug Reports?", comment: ""),
            subtitle: NSLocalizedString("Submit a post to r/FastScrobbler, and FastScrobbler will respond to your post.", comment: ""),
            attributedSubtitle: questionsOrBugReportsSubtitle,
            badgeText: NSLocalizedString("Tip", comment: ""),
            badgeLevel: .tip,
            actionTitle: nil,
            action: nil
        )
    }

    private var questionsOrBugReportsSubtitle: AttributedString {
        var linkedText = AttributedString(NSLocalizedString("Submit a post to r/FastScrobbler", comment: ""))
        linkedText.link = Self.redditSubmitURL

        let suffix = AttributedString(NSLocalizedString(", and FastScrobbler will respond to your post.", comment: ""))
        var result = linkedText
        result.append(suffix)
        return result
    }

    private func refreshStatuses() {
        mediaStatus = MPMediaLibrary.authorizationStatus()
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    private func requestMediaLibraryPermission() async {
        let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { s in
                cont.resume(returning: s)
            }
        }
        await MainActor.run {
            mediaStatus = status
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func badge(for status: MPMediaLibraryAuthorizationStatus) -> (String, StatusLevel) {
        switch status {
        case .authorized:
            return (NSLocalizedString("On", comment: ""), .good)
        case .notDetermined:
            return (NSLocalizedString("Not Set", comment: ""), .warning)
        case .denied:
            return (NSLocalizedString("Off", comment: ""), .bad)
        case .restricted:
            return (NSLocalizedString("Restricted", comment: ""), .bad)
        @unknown default:
            return (NSLocalizedString("Unknown", comment: ""), .warning)
        }
    }

    private func badge(for status: UIBackgroundRefreshStatus) -> (String, StatusLevel) {
        switch status {
        case .available:
            return (NSLocalizedString("On", comment: ""), .good)
        case .denied:
            return (NSLocalizedString("Off", comment: ""), .bad)
        case .restricted:
            return (NSLocalizedString("Restricted", comment: ""), .bad)
        @unknown default:
            return (NSLocalizedString("Unknown", comment: ""), .warning)
        }
    }

}
