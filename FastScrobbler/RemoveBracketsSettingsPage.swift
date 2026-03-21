import SwiftUI

struct RemoveBracketsSettingsPage: View {
    enum Target {
        case songTitles
        case albumTitles

        var settingsLabel: LocalizedStringKey {
            switch self {
            case .songTitles:
                "Remove brackets for song titles"
            case .albumTitles:
                "Remove brackets for album titles"
            }
        }

        var toggleLabel: LocalizedStringKey {
            switch self {
            case .songTitles:
                "Remove brackets for song titles"
            case .albumTitles:
                "Remove brackets for album titles"
            }
        }

        var descriptionText: LocalizedStringKey {
            switch self {
            case .songTitles:
                "When enabled, brackets containing any of the keywords in the list below will be removed from song titles when scrobbling."
            case .albumTitles:
                "When enabled, brackets containing any of the keywords in the list below will be removed from album titles when scrobbling."
            }
        }

        var warningText: LocalizedStringKey {
            switch self {
            case .songTitles:
                "This will affect song titles with any brackets in them."
            case .albumTitles:
                "This will affect album titles with any brackets in them."
            }
        }

        var addKeywordMessage: LocalizedStringKey {
            switch self {
            case .songTitles:
                "Enter a keyword to match inside song-title brackets when scrobbling."
            case .albumTitles:
                "Enter a keyword to match inside album-title brackets when scrobbling."
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

    @AppStorage(ProSettings.Keys.removeBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromSongTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeBracketsFromAlbumTitlesEnabled = false
    @AppStorage(ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled, store: AppGroup.userDefaults) private var removeAllBracketsFromAlbumTitlesEnabled = false

    @State private var keywordDrafts: [KeywordDraft]
    @State private var newKeyword = ""
    @State private var isPresentingAddKeywordPrompt = false
    @FocusState private var focusedKeywordID: UUID?
    @Environment(\.dismiss) private var dismiss

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
            .padding(.top, MacFloatingBarLayout.circleButtonContentTopPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topLeading) {
            MacFloatingCircleButton(
                systemImage: "chevron.left",
                help: "Back",
                accessibilityLabel: "Back",
                action: {
                    dismiss()
                }
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
                Text("Keywords")
            } footer: {
                Text("Keywords are matched case-insensitively and only as whole words inside () and [].")
            }
            .disabled(areKeywordsDisabled)
            .opacity(areKeywordsDisabled ? 0.5 : 1)
        }
#endif
    }

    @ViewBuilder
    private var toggleSectionContent: some View {
        Toggle(target.toggleLabel, isOn: removeBracketsEnabledBinding)
        Text(target.descriptionText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        Toggle("Remove ALL brackets", isOn: removeAllBracketsEnabledBinding)
            .disabled(!removeBracketsEnabledBinding.wrappedValue)
            .tint(.red)
        Text(target.warningText)
            .font(.footnote)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private var keywordSectionContent: some View {
        ForEach(Array(keywordDrafts.indices), id: \.self) { index in
            keywordRow(index: index)
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
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var keywordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keywords")
                .font(.title3.weight(.semibold))

            keywordSectionContent

            Text("Keywords are matched case-insensitively and only as whole words inside () and [].")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .disabled(areKeywordsDisabled)
        .opacity(areKeywordsDisabled ? 0.5 : 1)
    }
#endif

    @ViewBuilder
    private func keywordRow(index: Int) -> some View {
        HStack(spacing: 12) {
            TextField("Keyword", text: $keywordDrafts[index].text)
                .focused($focusedKeywordID, equals: keywordDrafts[index].id)
                .onSubmit {
                    normalizeAndPersistKeywords()
                }
#if os(macOS)
                .textFieldStyle(.roundedBorder)
#endif

            Button(role: .destructive) {
                removeKeyword(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .tint(.red)
            .accessibilityLabel("Remove keyword")
        }
    }

    private var addKeywordRow: some View {
        Button {
            isPresentingAddKeywordPrompt = true
        } label: {
            Label("Add Custom Keyword", systemImage: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
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

    private func removeKeyword(at index: Int) {
        guard keywordDrafts.indices.contains(index) else { return }
        let removedID = keywordDrafts[index].id
        keywordDrafts.remove(at: index)
        if focusedKeywordID == removedID {
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
