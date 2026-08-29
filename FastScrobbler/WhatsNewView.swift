import SwiftUI

struct WhatsNewView: View {
    struct VersionSection: Identifiable {
        let id: String
        let version: String
        let features: [Feature]
    }

    struct Feature: Identifiable {
        var id: String { title }
        let systemImage: String
        let title: String
        let boldPrefix: String?
        let showsProBadge: Bool
    }

    private let currentSections: [VersionSection] = [
        VersionSection(
            id: "7.0",
            version: "7.0",
            features: [
                Feature(
                    systemImage: "waveform.path.ecg",
                    title: "\nYou can now connect and scrobble your listening history to ListenBrainz.",
                    boldPrefix: "ListenBrainz support",
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "checkmark.circle",
                    title: "\nFor new users, and users who had Auto-scrobble disabled.",
                    boldPrefix: "\"Scrobble Recently Played from API\" is now ON by default",
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "person.crop.rectangle.badge.plus",
                    title: "Ignored artists list for \"Scrobble only the first credited artist\" feature",
                    boldPrefix: nil,
                    showsProBadge: true
                ),
                Feature(
                    systemImage: "platter.filled.top.iphone",
                    title: "Compact Live Activity size option",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "clock.arrow.circlepath",
                    title: "New options for \"Scan Listening History\" shortcut button",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        )
    ]

    private let previousSections: [VersionSection] = [
        VersionSection(
            id: "6.2",
            version: "6.2",
            features: [
                Feature(
                    systemImage: "checkmark.circle",
                    title: "\nPlays detected from Listening History now require confirmation before they are scrobbled.",
                    boldPrefix: "Auto-scrobbling for Listening History is now OFF by default",
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "checkmark.circle",
                    title: "To restore the previous behavior, turn on the new \"Auto-scrobble Listening History\" toggle.",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "6.0",
            version: "6.0",
            features: [
                Feature(
                    systemImage: "music.note.tv",
                    title: "Tap the \"Now Playing\" card to open a full-screen view",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "paintpalette",
                    title: "Choose between colourful and monochrome button themes",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "5.7",
            version: "5.7",
            features: [
                Feature(
                    systemImage: "icloud",
                    title: "Option to sync stored app data to iCloud (under \"App Storage\")",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "music.note.square.stack",
                    title: "\"Only scrobble non-library songs\" toggle for the \"Scrobble Recently Played from Apple Music API\" feature",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "5.4",
            version: "5.4",
            features: [
                Feature(
                    systemImage: "square.and.arrow.down.badge.clock",
                    title: "\"Scrobble Recently Played from Apple Music API\" feature",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "person.crop.rectangle",
                    title: "\"Scrobble only the first credited artist\" feature",
                    boldPrefix: nil,
                    showsProBadge: true
                )
            ]
        ),
        VersionSection(
            id: "4.0",
            version: "4.0",
            features: [
                Feature(
                    systemImage: "textformat.abc",
                    title: "Text replacement feature: Find and replace keywords when scrobbling",
                    boldPrefix: nil,
                    showsProBadge: true
                ),
                Feature(
                    systemImage: "plus.circle",
                    title: "Manual scrobbling feature",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "hand.tap",
                    title: "Tap and hold on a scrobbled song to scrobble it again",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "3.3",
            version: "3.3",
            features: [
                Feature(
                    systemImage: "person.2.wave.2",
                    title: "Added links to the r/FastScrobbler subreddit in the Settings page.\n\nFor any questions or bug reports, submit a post to r/FastScrobbler and FastScrobbler will respond to you.",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "3.2",
            version: "3.2",
            features: [
                Feature(
                    systemImage: "parentheses",
                    title: "\"Remove brackets in album titles\" feature",
                    boldPrefix: nil,
                    showsProBadge: true
                )
            ]
        ),
        VersionSection(
            id: "3.0",
            version: "3.0",
            features: [
                Feature(
                    systemImage: "parentheses",
                    title: "\"Remove brackets in song titles\" feature",
                    boldPrefix: nil,
                    showsProBadge: true
                ),
                Feature(
                    systemImage: "clock.arrow.circlepath",
                    title: "Toggle to disable the \"Scrobble from Listening History\" functionality",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "2.0",
            version: "2.0",
            features: [
                Feature(
                    systemImage: "globe",
                    title: "Support for Chinese (Simplified), French, Japanese, and Spanish",
                    boldPrefix: nil,
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "person.2",
                    title: "Album artist scrobbling support",
                    boldPrefix: nil,
                    showsProBadge: false
                )
            ]
        )
    ]

    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    VersionSectionList(sections: currentSections)

                    NavigationLink {
                        WhatsNewPreviousVersionsView(sections: previousSections)
                    } label: {
                        Text(NSLocalizedString("View Previous Versions", comment: ""))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    Button(action: onContinue) {
                        Text(NSLocalizedString("Done", comment: ""))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onContinue()
                    } label: {
                        IOSCloseButtonLabel(style: .plain)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("What's New", comment: ""))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    struct VersionSectionList: View {
        let sections: [VersionSection]

        var body: some View {
            VStack(spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Version %@", comment: ""), section.version))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                            ForEach(section.features) { feature in
                                WhatsNewFeatureCard(
                                    systemImage: feature.systemImage,
                                    boldPrefix: feature.boldPrefix,
                                    title: feature.title,
                                    showsProBadge: feature.showsProBadge
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WhatsNewPreviousVersionsView: View {
    let sections: [WhatsNewView.VersionSection]

    var body: some View {
        ScrollView {
            WhatsNewView.VersionSectionList(sections: sections)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("Previous Versions", comment: ""))
    }
}

private struct WhatsNewFeatureCard: View {
    let systemImage: String
    let boldPrefix: String?
    let title: String
    let showsProBadge: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            featureText
                .font(.body)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsProBadge {
                Text("Pro")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(proYellow, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var featureText: Text {
        guard let boldPrefix else {
            return Text(title)
        }

        return Text(boldPrefix).bold() + Text(title)
    }
}
