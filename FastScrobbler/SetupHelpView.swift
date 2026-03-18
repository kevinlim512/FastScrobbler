import MediaPlayer
import SwiftUI
import UIKit

struct SetupHelpView: View {
    enum Mode {
        case onboarding
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

    private struct SettingRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let badgeText: String
        let badgeLevel: StatusLevel
        let actionTitle: String?
        let action: (() -> Void)?
        let actionDisabled: Bool
        let actionProminent: Bool
        let actionTint: Color?

        init(
            icon: String,
            title: String,
            subtitle: String,
            badgeText: String,
            badgeLevel: StatusLevel,
            actionTitle: String?,
            action: (() -> Void)?,
            actionDisabled: Bool = false,
            actionProminent: Bool = false,
            actionTint: Color? = nil
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.badgeText = badgeText
            self.badgeLevel = badgeLevel
            self.actionTitle = actionTitle
            self.action = action
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

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        if actionProminent {
                            Button {
                                action()
                            } label: {
                                Label(actionTitle, systemImage: "music.note")
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

    private struct GiantPillButtonStyle: ButtonStyle {
        let tint: Color

        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
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

    @EnvironmentObject private var auth: LastFMAuthManager
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var mediaStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .restricted
    @State private var isSigningInToLastFM = false
    @State private var lastFMErrorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, mode == .help ? 12 : 30)

                    VStack(spacing: 12) {
                        lastFMRow
                        mediaLibraryRow
                        backgroundRefreshRow
                        shortcutsAndControlCenterRow
                        liveActivitiesRow
                        liveActivitiesDelayNote
                        listeningHistoryLibraryOnlyNoteRow
                        autoMixListeningHistoryNoteRow
                        scrobblingIssuesNoteRow
                    }

                    Button {
                        onDone()
                    } label: {
                        Label(mode == .onboarding ? NSLocalizedString("Continue", comment: "") : NSLocalizedString("Done", comment: ""), systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(mode == .help ? .bold : .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(auth.sessionKey == nil || (mode == .onboarding && mediaStatus != .authorized))
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .help {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .cancel) {
                            onDone()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
        .toolbar(mode == .help ? .visible : .hidden, for: .navigationBar)
        .interactiveDismissDisabled(mode == .onboarding)
        .alert(
            NSLocalizedString("Last.fm Sign-in", comment: ""),
            isPresented: Binding(
                get: { lastFMErrorText != nil },
                set: { if !$0 { lastFMErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastFMErrorText ?? "")
        }
        .onAppear { refreshStatuses() }
        .onValueChange(of: scenePhase) { newValue in
            if newValue == .active {
                refreshStatuses()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Setup")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text("FastScrobbler needs a few permissions and settings to work reliably.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var lastFMRow: some View {
        let isConnected = (auth.sessionKey != nil)
        let badgeText = isConnected ? NSLocalizedString("Connected", comment: "") : NSLocalizedString("Required", comment: "")
        let badgeLevel: StatusLevel = isConnected ? .good : .bad

        return SettingRow(
            icon: "person.crop.circle",
            title: NSLocalizedString("Last.fm", comment: ""),
            subtitle: NSLocalizedString("Sign in to start scrobbling to your Last.fm account.", comment: ""),
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: isConnected ? nil : (isSigningInToLastFM ? NSLocalizedString("Signing In…", comment: "") : NSLocalizedString("Sign In to Last.fm", comment: "")),
            action: isConnected ? nil : {
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
            actionDisabled: isSigningInToLastFM,
            actionProminent: true,
            actionTint: .red
        )
    }

    private var mediaLibraryRow: some View {
        let (badgeText, badgeLevel) = badge(for: mediaStatus)
        let action: (() -> Void)?
        let actionTitle: String?

        switch mediaStatus {
        case .authorized:
            action = nil
            actionTitle = nil
        case .notDetermined:
            action = { Task { await requestMediaLibraryPermission() } }
            actionTitle = NSLocalizedString("Enable Media Library", comment: "")
        case .denied, .restricted:
            action = openAppSettings
            actionTitle = NSLocalizedString("Open Settings", comment: "")
        @unknown default:
            action = openAppSettings
            actionTitle = NSLocalizedString("Open Settings", comment: "")
        }

        return SettingRow(
            icon: "music.note.list",
            title: NSLocalizedString("Media Library", comment: ""),
            subtitle: NSLocalizedString("Required to read Apple Music now-playing metadata.", comment: ""),
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: actionTitle,
            action: action
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

    private var liveActivitiesRow: some View {
        return SettingRow(
            icon: "bolt.horizontal.circle",
            title: NSLocalizedString("Live Activities", comment: ""),
            subtitle: NSLocalizedString("Optional, but recommended so you can see scrobbling status on the Lock Screen.", comment: ""),
            badgeText: NSLocalizedString("Tip", comment: ""),
            badgeLevel: .tip,
            actionTitle: nil,
            action: nil
        )
    }

    private var liveActivitiesDelayNote: some View {
        Text("Note: The Live Activity will not update immediately after you run a Shortcut action or use a Control Center button.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, -4)
    }

    private var shortcutsAndControlCenterRow: some View {
        SettingRow(
            icon: "memories.badge.plus",
            title: NSLocalizedString("Shortcuts & Control Center", comment: ""),
            subtitle: NSLocalizedString("Add Shortcut actions and Control Center buttons to scrobble or control playback without opening the app.", comment: ""),
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

    private var scrobblingIssuesNoteRow: some View {
        SettingRow(
            icon: "exclamationmark.circle",
            title: NSLocalizedString("Issues Scrobbling?", comment: ""),
            subtitle: NSLocalizedString("Try signing out of Last.fm and signing in again.", comment: ""),
            badgeText: NSLocalizedString("Note", comment: ""),
            badgeLevel: .warning,
            actionTitle: nil,
            action: nil
        )
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
