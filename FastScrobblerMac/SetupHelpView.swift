import AppKit
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if os(macOS)
import ServiceManagement
#endif
import SwiftUI

struct SetupHelpView: View {
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
	            HStack(alignment: .top, spacing: 12) {
	                Image(systemName: icon)
	                    .font(.system(size: 20, weight: .semibold))
	                    .foregroundStyle(.primary)
	                    .frame(width: 40, height: 40)
	                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	                    .overlay {
	                        RoundedRectangle(cornerRadius: 12, style: .continuous)
	                            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
	                    }

	                VStack(alignment: .leading, spacing: 4) {
	                    HStack(alignment: .center, spacing: 10) {
	                        Text(title)
	                            .font(.headline)
	                            .lineLimit(2)
	                            .fixedSize(horizontal: false, vertical: true)
	                            .multilineTextAlignment(.leading)
	                            .layoutPriority(1)

	                        Spacer(minLength: 8)

	                        if isChecked {
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
	                            .layoutPriority(2)
	                        }
	                    }

	                    Text(subtitle)
	                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        Group {
                            if let actionTint {
                                Group {
                                    if actionProminent {
                                        Button(actionTitle) { action() }
                                            .buttonStyle(.borderedProminent)
                                    } else {
                                        Button(actionTitle) { action() }
                                    }
                                }
                                .tint(actionTint)
                            } else {
                                Group {
                                    if actionProminent {
                                        Button(actionTitle) { action() }
                                            .buttonStyle(.borderedProminent)
                                    } else {
                                        Button(actionTitle) { action() }
                                    }
                                }
                            }
                        }
                        .disabled(actionDisabled)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
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
                        title: "Connect Last.fm",
                        subtitle: "Connect your account in Settings to start scrobbling.",
                        isChecked: isConnected,
                        actionTitle: isConnected ? nil : (isSigningInToLastFM ? "Signing In…" : "Sign In to Last.fm"),
                        action: isConnected ? nil : signInToLastFM,
                        actionTint: .red,
                        actionProminent: true,
                        actionDisabled: isSigningInToLastFM
                    )

                    let musicControlAllowed = (observer.authorizationStatus == .authorized)
                    HelpRow(
                        icon: "music.note",
                        title: "Allow Music Control",
                        subtitle: "When macOS asks to let FastScrobbler control Music, click Allow. This lets FastScrobbler read what’s playing for scrobbling.",
                        isChecked: musicControlAllowed,
                        actionTitle: musicControlAllowed ? nil : "Open System Settings",
                        action: musicControlAllowed ? nil : { openPrivacySettings(kind: .automation) }
                    )

                    let mediaAllowed = (mediaLibraryStatus == .authorized)
                    let mediaActionTitle: String? = {
                        guard !mediaAllowed else { return nil }
                        switch mediaLibraryStatus {
                        case .notDetermined:
                            return "Request Access"
                        case .denied, .restricted:
                            return "Open Media Library Settings"
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
                        title: "Media Library Permission",
                        subtitle: "If Media Library access is off, enable it in System Settings.",
                        isChecked: mediaAllowed,
                        actionTitle: mediaActionTitle,
                        action: mediaAction
                    )

                    HelpRow(
                        icon: "play.circle.fill",
                        title: "Start Playing Music",
                        subtitle: "Start playing music! FastScrobbler will show Now Playing and scrobble when eligible."
                    )

                    HelpRow(
                        icon: "power.circle",
                        title: "Start at Login",
                        subtitle: "Optional: turn this on in Settings if you want FastScrobbler to launch when you sign in to your Mac.",
                        isChecked: startAtLoginEnabled
                    )
                }

                Button {
                    onDone()
                } label: {
                    Text(mode == .onboarding ? "Continue" : "Done")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .padding(.top, MacFloatingBarLayout.circleButtonContentTopPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refreshStatuses() }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshStatuses()
        }
        .alert("Couldn't sign in to Last.fm", isPresented: Binding(
            get: { lastFMErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    lastFMErrorText = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastFMErrorText ?? "")
        }
        .overlay(alignment: .topLeading) {
            MacFloatingCircleButton(
                systemImage: "chevron.left",
                help: "Back",
                accessibilityLabel: "Back",
                action: onDone
            )
            .padding(.top, 10)
            .padding(.leading, 10)
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
                engine.start()
            } catch {
                if error is CancellationError { return }
                lastFMErrorText = error.localizedDescription
            }
        }
    }
}
