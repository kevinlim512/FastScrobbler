import AppKit
import SwiftUI

struct ListenBrainzConnectView: View {
    private enum CardPalette {
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

    private static let linksSectionRed = Color(red: 0.72, green: 0.14, blue: 0.14)

    let onBack: () -> Void

    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @EnvironmentObject private var engine: ScrobbleEngine
    @Environment(\.openURL) private var openURL

    @State private var tokenInput = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                    .padding(.top, 16)

                VStack(spacing: 16) {
                    instructionSection
                    tokenInputSection
                    connectButtonCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, MacFloatingBarLayout.circleButtonContentTopPadding)
        }
        .background(PagePalette.background)
        .overlay(alignment: .topLeading) {
            MacFloatingCircleButton(
                systemImage: "chevron.left",
                help: NSLocalizedString("Back", comment: ""),
                accessibilityLabel: NSLocalizedString("Back", comment: ""),
                action: onBack
            )
            .padding(.top, 10)
            .padding(.leading, 10)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("Connect ListenBrainz", comment: ""))
                .font(.title2.bold())
            Text(NSLocalizedString("To connect ListenBrainz, copy your User API Token from your profile page on ListenBrainz.org and paste it below.", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var instructionSection: some View {
        Button {
            openURL(listenBrainzAuth.tokenPageURL)
        } label: {
            Label(NSLocalizedString("Get Token on ListenBrainz.org", comment: ""), systemImage: "arrow.up.right.square")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.bordered)
        .pillButtonBorder()
    }

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("User Token", comment: ""))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField(NSLocalizedString("Paste User Token here", comment: ""), text: $tokenInput)
                    .textFieldStyle(.plain)

                if !tokenInput.isEmpty {
                    Button {
                        tokenInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let pastedString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let pastedString, !pastedString.isEmpty {
                        tokenInput = pastedString
                    }
                } label: {
                    Text(NSLocalizedString("Paste", comment: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Self.linksSectionRed)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CardPalette.border, lineWidth: 1)
            )

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectButtonCard: some View {
        Button {
            Task { @MainActor in
                await performConnect()
            }
        } label: {
            HStack {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isConnecting ? NSLocalizedString("Connecting…", comment: "") : NSLocalizedString("Connect ListenBrainz", comment: ""))
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .buttonStyle(.borderedProminent)
        .pillButtonBorder()
        .tint(Self.linksSectionRed)
        .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
    }

    private func performConnect() async {
        isConnecting = true
        errorText = nil
        do {
            try await listenBrainzAuth.connect(token: tokenInput)
            engine.start()
            onBack()
        } catch {
            errorText = error.localizedDescription
        }
        isConnecting = false
    }
}
