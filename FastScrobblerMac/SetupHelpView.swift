import AppKit
import SwiftUI

struct SetupHelpView: View {
    enum Mode {
        case onboarding
        case help
    }

    let mode: Mode
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL

    private struct HelpRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let actionTitle: String?
        let action: (() -> Void)?

        init(icon: String, title: String, subtitle: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.actionTitle = actionTitle
            self.action = action
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
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let actionTitle, let action {
                        Button(actionTitle) { action() }
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
                    .padding(.top, 30)

                VStack(spacing: 12) {
                    HelpRow(
                        icon: "person.crop.circle",
                        title: "Connect Last.fm",
                        subtitle: "Connect your account in Settings to start scrobbling."
                    )

                    HelpRow(
                        icon: "music.note",
                        title: "Allow Music Control",
                        subtitle: "Allow FastScrobbler to control the Music app when prompted.",
                        actionTitle: "Open System Settings",
                        action: { openPrivacySettings(kind: .automation) }
                    )

                    HelpRow(
                        icon: "music.note.list",
                        title: "Media Library Permission",
                        subtitle: "If Media Library access is off, enable it in System Settings.",
                        actionTitle: "Open Media Library Settings",
                        action: { openPrivacySettings(kind: .media) }
                    )

                    HelpRow(
                        icon: "play.circle.fill",
                        title: "Start Playing Music",
                        subtitle: "Start playing music — FastScrobbler will show Now Playing and scrobble when eligible."
                    )
                }

                Button {
                    onDone()
                } label: {
                    Text(mode == .onboarding ? "Continue" : "Done")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .pillButtonBorder()
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .padding(.top, MacFloatingBarLayout.contentTopPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            Text(mode == .onboarding ? "Setup" : "Help")
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
}
