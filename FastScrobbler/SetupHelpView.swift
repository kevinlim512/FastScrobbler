import ActivityKit
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
            }
        }

        private var background: Color {
            switch level {
            case .good: return .green.opacity(0.12)
            case .warning: return .orange.opacity(0.12)
            case .bad: return .red.opacity(0.12)
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

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        StatusBadge(text: badgeText, level: badgeLevel)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        Button(actionTitle) { action() }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    let mode: Mode
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var mediaStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @State private var backgroundRefreshStatus: UIBackgroundRefreshStatus = .restricted
    @State private var liveActivitiesEnabled: Bool? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, 30)

                    VStack(spacing: 12) {
                        mediaLibraryRow
                        backgroundRefreshRow
                        liveActivitiesRow
                        shortcutsAndControlCenterRow
                        liveActivitiesDelayNote
                    }

                    Button {
                        onDone()
                    } label: {
                        Label(mode == .onboarding ? "Continue" : "Done", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(mode == .help ? .bold : .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(mode == .onboarding && mediaStatus != .authorized)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())

            if mode == .help {
                Button {
                    onDone()
                } label: {
                    IOSCloseButtonLabel()
                        .padding(18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .interactiveDismissDisabled(mode == .onboarding)
        .onAppear { refreshStatuses() }
        .onChange(of: scenePhase) { newValue in
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
            actionTitle = "Enable Media Library"
        case .denied, .restricted:
            action = openAppSettings
            actionTitle = "Open Settings"
        @unknown default:
            action = openAppSettings
            actionTitle = "Open Settings"
        }

        return SettingRow(
            icon: "music.note.list",
            title: "Media Library",
            subtitle: "Required to read Apple Music now-playing metadata.",
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
            title: "Background App Refresh",
            subtitle: "Recommended for timely syncing while the app is in the background.",
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: showAction ? "Open Settings" : nil,
            action: showAction ? openAppSettings : nil
        )
    }

    private var liveActivitiesRow: some View {
        let (badgeText, badgeLevel) = badgeForLiveActivities(liveActivitiesEnabled)
        let showAction = (liveActivitiesEnabled == false)

        return SettingRow(
            icon: "bolt.horizontal.circle",
            title: "Live Activities",
            subtitle: "Optional, but recommended so you can see scrobbling status on the Lock Screen.",
            badgeText: badgeText,
            badgeLevel: badgeLevel,
            actionTitle: showAction ? "Open Settings" : nil,
            action: showAction ? openAppSettings : nil
        )
    }

    private var liveActivitiesDelayNote: some View {
        Text("Note: Live Activities don’t update immediately after you run a Shortcut action or use a Control Center button.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, -4)
    }

    private var shortcutsAndControlCenterRow: some View {
        SettingRow(
            icon: "memories.badge.plus",
            title: "Shortcuts & Control Center",
            subtitle: "Add Shortcut actions and Control Center buttons to scrobble or control playback without opening the app.",
            badgeText: "Tip",
            badgeLevel: .good,
            actionTitle: nil,
            action: nil
        )
    }

    private func refreshStatuses() {
        mediaStatus = MPMediaLibrary.authorizationStatus()
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        if #available(iOS 16.1, *) {
            liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        } else {
            liveActivitiesEnabled = nil
        }
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
            return ("On", .good)
        case .notDetermined:
            return ("Not Set", .warning)
        case .denied:
            return ("Off", .bad)
        case .restricted:
            return ("Restricted", .bad)
        @unknown default:
            return ("Unknown", .warning)
        }
    }

    private func badge(for status: UIBackgroundRefreshStatus) -> (String, StatusLevel) {
        switch status {
        case .available:
            return ("On", .good)
        case .denied:
            return ("Off", .bad)
        case .restricted:
            return ("Restricted", .bad)
        @unknown default:
            return ("Unknown", .warning)
        }
    }

    private func badgeForLiveActivities(_ enabled: Bool?) -> (String, StatusLevel) {
        guard let enabled else { return ("Unsupported", .warning) }
        return enabled ? ("On", .good) : ("Off", .bad)
    }
}
