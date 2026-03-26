import SwiftUI

// MARK: - WhatsNewRelease

enum WhatsNewRelease {
    private enum Keys {
        static let lastSeenVersion = "FastScrobbler.WhatsNew.lastSeenVersion"
    }

    /// Present the current release notes automatically once for users updating to this version.
    static let version = "3.3"

    static func currentAppVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func shouldPresent() -> Bool {
        let defaults = UserDefaults.standard
        guard let currentVersion = currentAppVersion(), !currentVersion.isEmpty else {
            return false
        }

        guard let lastSeenVersion = defaults.string(forKey: Keys.lastSeenVersion) else {
            defaults.set(currentVersion, forKey: Keys.lastSeenVersion)
            return false
        }

        guard currentVersion == version else {
            if lastSeenVersion != currentVersion {
                defaults.set(currentVersion, forKey: Keys.lastSeenVersion)
            }
            return false
        }

        return lastSeenVersion != currentVersion
    }

    static func markSeen() {
        guard let currentVersion = currentAppVersion(), !currentVersion.isEmpty else { return }
        UserDefaults.standard.set(currentVersion, forKey: Keys.lastSeenVersion)
    }
}

// MARK: - WhatsNewView

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
        let showsProBadge: Bool
    }

    private let currentSections: [VersionSection] = [
        VersionSection(
            id: "3.3",
            version: "3.3",
            features: [
                Feature(
                    systemImage: "person.2.wave.2",
                    title: "Added links to the r/FastScrobbler subreddit in the Settings page.\n\nFor any questions or bug reports, submit a post to r/FastScrobbler and FastScrobbler will respond to you.",
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
                    title: "\"Remove brackets for album titles\" feature",
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
                    title: "\"Remove brackets for song titles\" feature",
                    showsProBadge: true
                ),
                Feature(
                    systemImage: "clock.arrow.circlepath",
                    title: "Toggle to disable the \"Scrobble from Listening History\" functionality",
                    showsProBadge: false
                )
            ]
        )
    ]

    private let previousSections: [VersionSection] = [
        VersionSection(
            id: "2.0",
            version: "2.0",
            features: [
                Feature(
                    systemImage: "globe",
                    title: "Support for Chinese (Simplified), French, Japanese, and Spanish",
                    showsProBadge: false
                ),
                Feature(
                    systemImage: "person.2",
                    title: "Album artist scrobbling support",
                    showsProBadge: false
                )
            ]
        ),
        VersionSection(
            id: "1.2",
            version: "1.2",
            features: [
                Feature(
                    systemImage: "clock.arrow.circlepath",
                    title: "\"Scrobble Listening History from all devices\" feature",
                    showsProBadge: true
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
#if os(iOS)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
#else
            .background(Color(nsColor: .windowBackgroundColor))
#endif
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .cancel) {
                        onContinue()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
#endif
        }
#if os(macOS)
        .frame(width: 560, height: 620)
#endif
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
                        Text("Version \(section.version)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 12) {
                            ForEach(section.features) { feature in
                                WhatsNewFeatureCard(
                                    systemImage: feature.systemImage,
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

// MARK: - WhatsNewPreviousVersionsView

private struct WhatsNewPreviousVersionsView: View {
    let sections: [WhatsNewView.VersionSection]

    var body: some View {
        ScrollView {
            WhatsNewView.VersionSectionList(sections: sections)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
        }
#if os(iOS)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
#else
        .background(Color(nsColor: .windowBackgroundColor))
#endif
        .navigationTitle(NSLocalizedString("Previous Versions", comment: ""))
    }
}

// MARK: - WhatsNewFeatureCard

private struct WhatsNewFeatureCard: View {
    let systemImage: String
    let title: String
    let showsProBadge: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
#if os(iOS)
                .background(Color(.tertiarySystemGroupedBackground))
#else
                .background(.thinMaterial)
#endif
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
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
                    .background(Color.yellow, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
#if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
#else
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
#endif
    }
}
