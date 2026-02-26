import AppKit
import SwiftUI

struct SetupHelpView: View {
    enum Mode {
        case onboarding
        case help
    }

    let mode: Mode
    let onOpenSettings: (() -> Void)?
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL

    init(mode: Mode, onOpenSettings: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.mode = mode
        self.onOpenSettings = onOpenSettings
        self.onDone = onDone
    }

    private struct HelpRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let actionTitle: String?
        let action: (() -> Void)?
        let actionTint: Color?
        let actionProminent: Bool

        init(
            icon: String,
            title: String,
            subtitle: String,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            actionTint: Color? = nil,
            actionProminent: Bool = false
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.actionTitle = actionTitle
            self.action = action
            self.actionTint = actionTint
            self.actionProminent = actionProminent
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
                        subtitle: "Connect your account in Settings to start scrobbling.",
                        actionTitle: onOpenSettings == nil ? nil : "Sign In to Last.fm",
                        action: { onOpenSettings?() },
                        actionTint: .red,
                        actionProminent: true
                    )

                    HelpRow(
                        icon: "music.note",
                        title: "Allow Music Control",
                        subtitle: "When macOS asks to let FastScrobbler control Music, click Allow — this lets FastScrobbler read what’s playing for scrobbling.",
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
}
