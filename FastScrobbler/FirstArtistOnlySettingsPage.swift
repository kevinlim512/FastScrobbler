import SwiftUI

struct FirstArtistOnlySettingsPage: View {
    #if os(macOS)
    private enum CardPalette {
        static let backgroundOverlay = dynamicColor(
            light: NSColor(white: 1.0, alpha: 0.96),
            dark: NSColor(white: 0.10, alpha: 0.86)
        )
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
    #endif

    private struct ArtistDraft: Identifiable {
        let id: UUID
        var text: String
    }

    @EnvironmentObject private var pro: ProPurchaseManager

    @AppStorage(ProSettings.Keys.useFirstArtistOnlyForScrobbling, store: AppGroup.userDefaults) private var useFirstArtistOnlyForScrobbling = false

    @State private var artistDrafts: [ArtistDraft]
    @State private var newArtist = ""
    @State private var isPresentingAddArtistPrompt = false
    @State private var isAddingArtistInline = false
    @FocusState private var focusedArtistID: UUID?
    @FocusState private var isNewArtistFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    #if os(macOS)
    private var contentCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CardPalette.backgroundOverlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CardPalette.border, lineWidth: 1)
            }
    }
    #endif

    init() {
        _artistDrafts = State(initialValue: ProSettings.firstArtistOnlyIgnoredArtists().map {
            ArtistDraft(id: UUID(), text: $0)
        })
    }

    private var isFeatureEnabled: Bool {
        pro.isPro && useFirstArtistOnlyForScrobbling
    }

    private var isIgnoreListDisabled: Bool {
        !isFeatureEnabled
    }

    var body: some View {
        pageContent
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .onDisappear {
                normalizeAndPersistIgnoredArtists()
            }
            .onValueChange(of: isPresentingAddArtistPrompt) { isPresenting in
                if !isPresenting {
                    newArtist = ""
                }
            }
#if os(iOS)
            .alert("Add Ignored Artist", isPresented: $isPresentingAddArtistPrompt) {
                TextField("Artist name", text: $newArtist)
                Button("Add") {
                    addArtist(from: newArtist)
                }
                Button("Cancel", role: .cancel) {
                    newArtist = ""
                }
            } message: {
                Text(localized("Enter an artist name to prevent splitting when scrobbling."))
            }
#endif
    }

    @ViewBuilder
    private var pageContent: some View {
#if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard
                ignoredArtistsCard
            }
            .padding()
            .padding(.top, 44)
        }
        .background(PagePalette.background)
        .overlay(alignment: .topLeading) {
            MacFloatingCircleButton(
                systemImage: "chevron.left",
                help: localized("Back"),
                accessibilityLabel: localized("Back"),
                action: { dismiss() }
            )
            .padding(.top, 10)
            .padding(.leading, 10)
        }
#else
        Form {
            toggleSectionContent

            Section {
                ignoredArtistSectionContent
            } header: {
                Text(localized("Ignored Artists"))
            } footer: {
                Text(localized("Songs by artists in this list will not have their credited artists split when scrobbling."))
            }
            .disabled(isIgnoreListDisabled)
            .opacity(isIgnoreListDisabled ? 0.5 : 1)
        }
#endif
    }

    @ViewBuilder
    private var toggleSectionContent: some View {
#if os(iOS)
        Toggle(isOn: proLockedBoolBinding($useFirstArtistOnlyForScrobbling)) {
            if pro.isPro {
                Text(localized("Scrobble only the first credited artist"))
            } else {
                HStack {
                    Text(localized("Scrobble only the first credited artist"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
        }
        .disabled(!pro.isPro)
        .tint(proYellow)
#else
        Toggle(localized("Scrobble only the first credited artist"), isOn: proLockedBoolBinding($useFirstArtistOnlyForScrobbling))
            .disabled(!pro.isPro)
#endif
        Text(localized("When a song lists multiple artists separated by \"&\" or commas, only scrobble the first artist."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func proLockedBoolBinding(_ storage: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { pro.isPro ? storage.wrappedValue : false },
            set: { newValue in
                guard pro.isPro else { return }
                storage.wrappedValue = newValue
            }
        )
    }

    @ViewBuilder
    private var ignoredArtistSectionContent: some View {
        ForEach($artistDrafts) { $draft in
            artistRow(draft: $draft)
        }
        .onDelete(perform: removeArtistsAtOffset)

        addArtistRow
    }

#if os(macOS)
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleSectionContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    private var ignoredArtistsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Ignored Artists"))
                .font(.title3.weight(.semibold))

            ignoredArtistSectionContent

            Text(localized("Songs by artists in this list will not have their credited artists split when scrobbling."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
        .disabled(isIgnoreListDisabled)
        .opacity(isIgnoreListDisabled ? 0.5 : 1)
    }
#endif

    @ViewBuilder
    private func artistRow(draft: Binding<ArtistDraft>) -> some View {
        HStack(spacing: 12) {
            TextField("Artist name", text: draft.text)
                .focused($focusedArtistID, equals: draft.id)
                .onSubmit {
                    normalizeAndPersistIgnoredArtists()
                }
#if os(macOS)
                .textFieldStyle(.roundedBorder)
#endif

            Button {
                removeArtist(id: draft.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .tint(Color.accentColor)
            .accessibilityLabel("Remove artist")
        }
    }

    private var addArtistRow: some View {
#if os(macOS)
        Group {
            if isAddingArtistInline {
                HStack(spacing: 8) {
                    TextField("Artist name", text: $newArtist)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNewArtistFieldFocused)
                        .onSubmit {
                            addArtist(from: newArtist)
                            isAddingArtistInline = false
                        }
                    Button("Add") {
                        addArtist(from: newArtist)
                        isAddingArtistInline = false
                    }
                    .disabled(newArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        newArtist = ""
                        isAddingArtistInline = false
                    }
                }
            } else {
                Button {
                    isAddingArtistInline = true
                    isNewArtistFieldFocused = true
                } label: {
                    Label(localized("Add Ignored Artist"), systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
#else
        Button {
            isPresentingAddArtistPrompt = true
        } label: {
            Label(localized("Add Ignored Artist"), systemImage: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
#endif
    }

    private func addArtist(from source: String) {
        let candidate = source
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCandidate.isEmpty else { return }
        guard !artistDrafts.contains(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedCandidate
        }) else {
            newArtist = ""
            return
        }

        artistDrafts.append(ArtistDraft(id: UUID(), text: candidate.trimmingCharacters(in: .whitespacesAndNewlines)))
        newArtist = ""
        normalizeAndPersistIgnoredArtists()
    }

    private func removeArtist(id: UUID) {
        artistDrafts.removeAll { $0.id == id }
        if focusedArtistID == id {
            focusedArtistID = nil
        }
        normalizeAndPersistIgnoredArtists()
    }

    private func removeArtistsAtOffset(at offsets: IndexSet) {
        artistDrafts.remove(atOffsets: offsets)
        normalizeAndPersistIgnoredArtists()
    }

    private func normalizeAndPersistIgnoredArtists() {
        let persistedArtists = ProSettings.sanitizedIgnoredArtists(artistDrafts.map(\.text))
        let existingIDs = Dictionary(
            artistDrafts.map {
                ($0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.id)
            },
            uniquingKeysWith: { first, _ in first }
        )

        ProSettings.setFirstArtistOnlyIgnoredArtists(persistedArtists)
        artistDrafts = persistedArtists.map { artist in
            let normalized = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ArtistDraft(id: existingIDs[normalized] ?? UUID(), text: artist)
        }
    }
}
