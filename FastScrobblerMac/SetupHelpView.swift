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

    enum Mode {
        case onboarding
        case help
    }

    let mode: Mode
    let onOpenSettings: (() -> Void)?
    let onDone: () -> Void

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var mediaLibraryStatus: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @State private var startAtLoginEnabled = Self.isStartAtLoginEnabled
    @State private var isSigningInToLastFM = false
    @State private var lastFMErrorText: String?

    private var canFinishSetup: Bool {
        auth.sessionKey != nil && observer.authorizationStatus == .authorized
    }

    init(mode: Mode, onOpenSettings: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.mode = mode
        self.onOpenSettings = onOpenSettings
        self.onDone = onDone
    }

    private struct HelpRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let isChecked: Bool
        let actionTitle: String?
        let action: (() -> Void)?
        let actionTint: Color?
        let actionProminent: Bool
        let actionDisabled: Bool

        init(
            icon: String,
            title: String,
            subtitle: String,
            isChecked: Bool = false,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            actionTint: Color? = nil,
            actionProminent: Bool = false,
            actionDisabled: Bool = false
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.isChecked = isChecked
            self.actionTitle = actionTitle
            self.action = action
            self.actionTint = actionTint
            self.actionProminent = actionProminent
            self.actionDisabled = actionDisabled
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.trailing, isChecked ? 88 : 0)

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
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isChecked {
                    statusBadge
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
            }
        }

        private var statusBadge: some View {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Enabled")
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.green.opacity(0.12), in: Capsule())
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

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    let isConnected = (auth.sessionKey != nil)
                    HelpRow(
                        icon: "person.crop.circle",
                        title: NSLocalizedString("Connect Last.fm", comment: ""),
                        subtitle: NSLocalizedString("Connect your account in Settings to start scrobbling.", comment: ""),
                        isChecked: isConnected,
                        actionTitle: isConnected ? nil : (isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In to Last.fm", comment: "")),
                        action: isConnected ? nil : signInToLastFM,
                        actionTint: .red,
                        actionProminent: true,
                        actionDisabled: isSigningInToLastFM
                    )

                    let musicControlAllowed = (observer.authorizationStatus == .authorized)
                    let musicControlActionTitle: String? = {
                        guard !musicControlAllowed else { return nil }
                        switch observer.authorizationStatus {
                        case .notDetermined:
                            return NSLocalizedString("Request Access", comment: "")
                        case .denied, .restricted:
                            return NSLocalizedString("Open System Settings", comment: "")
                        case .authorized:
                            return nil
                        }
                    }()
                    let musicControlAction: (() -> Void)? = {
                        guard !musicControlAllowed else { return nil }
                        switch observer.authorizationStatus {
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
                        actionTitle: musicControlActionTitle,
                        action: musicControlAction
                    )

                    let mediaAllowed = (mediaLibraryStatus == .authorized)
                    let mediaActionTitle: String? = {
                        guard !mediaAllowed else { return nil }
                        switch mediaLibraryStatus {
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
                        switch mediaLibraryStatus {
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
                        actionTitle: mediaActionTitle,
                        action: mediaAction
                    )

                    HelpRow(
                        icon: "play.circle.fill",
                        title: NSLocalizedString("Start Playing Music", comment: ""),
                        subtitle: NSLocalizedString("Start playing music! FastScrobbler will show Now Playing and scrobble when eligible.", comment: "")
                    )

                    HelpRow(
                        icon: "power.circle",
                        title: NSLocalizedString("Start at Login", comment: ""),
                        subtitle: NSLocalizedString("Optional: turn this on in Settings if you want FastScrobbler to launch when you sign in to your Mac.", comment: ""),
                        isChecked: startAtLoginEnabled
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
                    Text("Connect Last.fm and allow Music control before continuing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .padding(.top, MacFloatingBarLayout.circleButtonContentTopPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text("Setup")
                .font(.system(size: 34, weight: .bold))
            Text("A quick checklist to get scrobbling working reliably.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
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
        mediaLibraryStatus = MPMediaLibrary.authorizationStatus()
        startAtLoginEnabled = Self.isStartAtLoginEnabled
        observer.refreshOnceIfAuthorized()
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
            refreshStatuses()
            await maybeStartScrobblingIfSetupAlreadyCompleted()
        }
    }

    private func requestMusicControlPermission() {
        Task { @MainActor in
            await observer.requestMusicControlPermission()
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
        guard auth.sessionKey != nil, observer.authorizationStatus == .authorized else { return }
        await AppModel.shared.startIfNeeded()
    }
}
