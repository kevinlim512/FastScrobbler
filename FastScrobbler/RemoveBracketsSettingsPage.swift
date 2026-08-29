import SwiftUI

struct RemoveBracketsSettingsPage: View {
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

    enum Target {
        case songTitles
        case albumTitles

        private func localized(_ key: String) -> String {
            NSLocalizedString(key, comment: "")
        }

        var settingsLabel: String {
            switch self {
            case .songTitles:
                localized("Remove brackets in song titles")
            case .albumTitles:
                localized("Remove brackets in album titles")
            }
        }

        var toggleLabel: String {
            switch self {
            case .songTitles:
                localized("Remove brackets in song titles")
            case .albumTitles:
                localized("Remove brackets in album titles")
            }
        }

        var descriptionText: String {
            switch self {
            case .songTitles:
                localized("When enabled, brackets containing any of the keywords in the list below will be removed from song titles when scrobbling.")
            case .albumTitles:
                localized("When enabled, brackets containing any of the keywords in the list below will be removed from album titles when scrobbling.")
            }
        }

        var warningText: String {
            switch self {
            case .songTitles:
                localized("This will affect song titles with any brackets in them.")
            case .albumTitles:
                localized("This will affect album titles with any brackets in them.")
            }
        }

        var addKeywordMessage: String {
            switch self {
            case .songTitles:
                localized("Enter a keyword to match inside song-title brackets when scrobbling.")
            case .albumTitles:
                localized("Enter a keyword to match inside album-title brackets when scrobbling.")
            }
        }

        func loadKeywords() -> [String] {
            switch self {
            case .songTitles:
                ProSettings.removeBracketsFromSongTitleKeywords()
            case .albumTitles:
                ProSettings.removeBracketsFromAlbumTitleKeywords()
            }
        }

        func persistKeywords(_ keywords: [String]) {
            switch self {
            case .songTitles:
                ProSettings.setRemoveBracketsFromSongTitleKeywords(keywords)
            case .albumTitles:
                ProSettings.setRemoveBracketsFromAlbumTitleKeywords(keywords)
            }
        }
    }

    private struct KeywordDraft: Identifiable {
        let id: UUID
        var text: String
    }

    let target: Target

    @EnvironmentObject private var pro: ProPurchaseManager

    @AppStorage(ProSettings.Keys.removeBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromAlbumTitlesEnabled = false

    @State private var keywordDrafts: [KeywordDraft]
    @State private var newKeyword = ""
    @State private var isPresentingAddKeywordPrompt = false
    @State private var isAddingKeywordInline = false
    @FocusState private var focusedKeywordID: UUID?
    @FocusState private var isNewKeywordFieldFocused: Bool
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

    init(target: Target) {
        self.target = target
        _keywordDrafts = State(initialValue: target.loadKeywords().map {
            KeywordDraft(id: UUID(), text: $0)
        })
    }

    private var removeBracketsEnabledBinding: Binding<Bool> {
        switch target {
        case .songTitles:
            return $removeBracketsFromSongTitlesEnabled
        case .albumTitles:
            return $removeBracketsFromAlbumTitlesEnabled
        }
    }

    private var removeAllBracketsEnabledBinding: Binding<Bool> {
        switch target {
        case .songTitles:
            return $removeAllBracketsFromSongTitlesEnabled
        case .albumTitles:
            return $removeAllBracketsFromAlbumTitlesEnabled
        }
    }

    private var areKeywordsDisabled: Bool {
        !removeBracketsEnabledBinding.wrappedValue || removeAllBracketsEnabledBinding.wrappedValue
    }

    var body: some View {
        pageContent
            .navigationTitle(target.settingsLabel)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .onDisappear {
                normalizeAndPersistKeywords()
            }
            .onValueChange(of: isPresentingAddKeywordPrompt) { isPresenting in
                if !isPresenting {
                    newKeyword = ""
                }
            }
#if os(iOS)
            .alert("Add Custom Keyword", isPresented: $isPresentingAddKeywordPrompt) {
                TextField("Custom keyword", text: $newKeyword)
                Button("Add") {
                    addKeyword(from: newKeyword)
                }
                Button("Cancel", role: .cancel) {
                    newKeyword = ""
                }
            } message: {
                Text(target.addKeywordMessage)
            }
#endif
    }

    @ViewBuilder
    private var pageContent: some View {
#if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard
                keywordsCard
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
                keywordSectionContent
            } header: {
                Text(localized("Keywords"))
            } footer: {
                Text(localized("Keywords are matched case-insensitively and only as whole words inside () and []."))
            }
            .disabled(areKeywordsDisabled)
            .opacity(areKeywordsDisabled ? 0.5 : 1)
        }
#endif
    }

    @ViewBuilder
    private var toggleSectionContent: some View {
#if os(iOS)
        Toggle(isOn: removeBracketsEnabledBinding) {
            if pro.isPro {
                Text(target.toggleLabel)
            } else {
                HStack {
                    Text(target.toggleLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProFeatureBadge()
                }
            }
        }
        .disabled(!pro.isPro)
        .tint(proYellow)
#else
        Toggle(target.toggleLabel, isOn: removeBracketsEnabledBinding)
#endif
        Text(target.descriptionText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        Toggle(localized("Remove ALL brackets"), isOn: removeAllBracketsEnabledBinding)
            .disabled(!removeBracketsEnabledBinding.wrappedValue)
            .tint(Color.accentColor)
        Text(target.warningText)
            .font(.footnote)
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var keywordSectionContent: some View {
        ForEach($keywordDrafts) { $draft in
            keywordRow(draft: $draft)
        }

        addKeywordRow
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

    private var keywordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Keywords"))
                .font(.title3.weight(.semibold))

            keywordSectionContent

            Text(localized("Keywords are matched case-insensitively and only as whole words inside () and []."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
        .disabled(areKeywordsDisabled)
        .opacity(areKeywordsDisabled ? 0.5 : 1)
    }
#endif

    @ViewBuilder
    private func keywordRow(draft: Binding<KeywordDraft>) -> some View {
        HStack(spacing: 12) {
            TextField("Keyword", text: draft.text)
                .focused($focusedKeywordID, equals: draft.id)
                .onSubmit {
                    normalizeAndPersistKeywords()
                }
#if os(macOS)
                .textFieldStyle(.roundedBorder)
#endif

            Button {
                removeKeyword(id: draft.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .tint(Color.accentColor)
            .accessibilityLabel("Remove keyword")
        }
    }

    private var addKeywordRow: some View {
#if os(macOS)
        Group {
            if isAddingKeywordInline {
                HStack(spacing: 8) {
                    TextField("Custom keyword", text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNewKeywordFieldFocused)
                        .onSubmit {
                            addKeyword(from: newKeyword)
                            isAddingKeywordInline = false
                        }
                    Button("Add") {
                        addKeyword(from: newKeyword)
                        isAddingKeywordInline = false
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        newKeyword = ""
                        isAddingKeywordInline = false
                    }
                }
            } else {
                Button {
                    isAddingKeywordInline = true
                    isNewKeywordFieldFocused = true
                } label: {
                    Label("Add Custom Keyword", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
#else
        Button {
            isPresentingAddKeywordPrompt = true
        } label: {
            Label("Add Custom Keyword", systemImage: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
#endif
    }

    private func addKeyword(from source: String) {
        let candidate = source
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCandidate.isEmpty else { return }
        guard !keywordDrafts.contains(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedCandidate
        }) else {
            newKeyword = ""
            return
        }

        keywordDrafts.append(KeywordDraft(id: UUID(), text: candidate))
        newKeyword = ""
        normalizeAndPersistKeywords()
    }

    private func removeKeyword(id: UUID) {
        keywordDrafts.removeAll { $0.id == id }
        if focusedKeywordID == id {
            focusedKeywordID = nil
        }
        normalizeAndPersistKeywords()
    }

    private func normalizeAndPersistKeywords() {
        let persistedKeywords = ProSettings.sanitizedRemoveBracketsKeywords(keywordDrafts.map(\.text))
        let existingIDs = Dictionary(
            keywordDrafts.map {
                ($0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.id)
            },
            uniquingKeysWith: { first, _ in first }
        )

        target.persistKeywords(persistedKeywords)
        keywordDrafts = persistedKeywords.map { keyword in
            let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return KeywordDraft(id: existingIDs[normalized] ?? UUID(), text: keyword)
        }
    }
}
