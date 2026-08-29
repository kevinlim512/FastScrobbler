import SwiftUI

struct GroupedManualScrobbleEntry: Identifiable {
    let representativeEntry: ScrobbleLogStore.Entry
    let count: Int
    let memberIDs: [UUID]

    var id: UUID {
        representativeEntry.id
    }
}

struct ManualScrobbleView: View {
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

    var onBack: (() -> Void)? = nil

    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore
    @Environment(\.dismiss) private var dismiss

    @State private var artist = ""
    @State private var title = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var useCustomTimestamp = false
    @State private var customDate = Date()
    @State private var quantity = 1
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorText: String?
    @State private var now = Date()

    private static let twoWeeksAgo: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            NSColor(name: nil) { appearance in
                let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
                return bestMatch == .darkAqua ? dark : light
            }
        )
    }

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

    private func truncated(_ text: String) -> String {
        if text.count > 500 {
            return String(text.prefix(500))
        }
        return text
    }

    private var canSubmit: Bool {
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting &&
        !isSubmitted
    }

    private var timestamp: Int {
        let date = useCustomTimestamp ? customDate : Date()
        return Int(date.timeIntervalSince1970)
    }

    private var groupedManualLogEntries: [GroupedManualScrobbleEntry] {
        ConsecutivePlayGrouper.groups(
            from: scrobbleLog.manualEntries(),
            shouldGroup: { _ in true },
            dedupeKey: { "\($0.track.dedupeKey)" },
            memberID: \.id
        ).map {
            GroupedManualScrobbleEntry(
                representativeEntry: $0.representative,
                count: $0.count,
                memberIDs: $0.memberIDs
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localized("Manual Scrobble"))
                    .font(.title.bold())
                    .padding(.top, MacFloatingBarLayout.contentTopPadding)

                manualScrobbleFormCard

                if !groupedManualLogEntries.isEmpty {
                    Divider()

                    Text(localized("Manual Scrobble Log"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedManualLogEntries) { groupedEntry in
                            logEntryRow(groupedEntry, now: now)
                            if groupedEntry.id != groupedManualLogEntries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(contentCardBackground)
                }
            }
            .padding()
        }
        .onValueChange(of: artist) { artist = truncated($0) }
        .onValueChange(of: title) { title = truncated($0) }
        .onValueChange(of: album) { album = truncated($0) }
        .onValueChange(of: albumArtist) { albumArtist = truncated($0) }
        .background(PagePalette.background)
        .overlay(alignment: .topLeading) {
            MacFloatingCircleButton(
                systemImage: "chevron.left",
                help: localized("Back"),
                accessibilityLabel: localized("Back"),
                action: { if let onBack { onBack() } else { dismiss() } }
            )
            .padding(.top, 10)
            .padding(.leading, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var manualScrobbleFormCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            macField(localized("Artist"), text: $artist)
            macField(localized("Song title"), text: $title)
            macField(localized("Album"), text: $album)
            macField(localized("Album artist"), text: $albumArtist)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(localized("Timestamp"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker(localized("Timestamp"), selection: $useCustomTimestamp) {
                    Text(localized("Now")).tag(false)
                    Text(localized("Custom…")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(.headline)
                .frame(height: 64)

                if useCustomTimestamp {
                    DatePicker(
                        localized("Date & Time"),
                        selection: $customDate,
                        in: Self.twoWeeksAgo...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Text(localized("Last.fm will reject scrobbles older than two weeks."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Quantity"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Text("\(quantity)")
                        .font(.body.weight(.medium))
                    Spacer()
                    Stepper("", value: $quantity, in: 1...5)
                        .labelsHidden()
                }
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    Spacer()
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else if isSubmitted {
                        Image(systemName: "checkmark.circle.fill")
                        Text(quantity > 1 ? String(format: localized("Submitted %d Scrobbles"), quantity) : localized("Submitted"))
                    } else {
                        Text(quantity > 1 ? String(format: localized("Submit %d Scrobbles"), quantity) : localized("Submit Scrobble"))
                    }
                    Spacer()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .animation(.easeOut(duration: 0.25), value: isSubmitted)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSubmitted ? .green : .accentColor)
            .disabled(!canSubmit)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(contentCardBackground)
    }

    @ViewBuilder
    private func logEntryRow(_ groupedEntry: GroupedManualScrobbleEntry, now: Date) -> some View {
        let entry = groupedEntry.representativeEntry
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.track.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if groupedEntry.count > 1 {
                        Text("x\(groupedEntry.count)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(entry.track.artist)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.82))
                    .multilineTextAlignment(.leading)

                if let album = entry.track.album, !album.isEmpty {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }

            HStack(spacing: 8) {
                Text(RelativeScrobbleTimeFormatter.string(from: displayDate(for: entry), to: now))
                if entry.lovedOnLastFM == true {
                    Text("Loved")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.top, 2)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceLabel(_ source: ScrobbleLogStore.Source) -> String {
        switch source {
        case .live: return ""
        case .backlog: return NSLocalizedString("Backlog", comment: "")
        case .playbackHistory: return NSLocalizedString("Listening History", comment: "")
        case .recentlyPlayed: return NSLocalizedString("Recently Played API", comment: "")
        case .manual: return NSLocalizedString("Manual", comment: "")
        }
    }

    private func displayDate(for entry: ScrobbleLogStore.Entry) -> Date {
        if entry.source == .playbackHistory || entry.source == .recentlyPlayed {
            return Date(timeIntervalSince1970: TimeInterval(entry.startTimestamp))
        }
        return entry.scrobbledAt
    }

    private func macField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func submit() {
        errorText = nil
        isSubmitting = true
        let ts = timestamp
        Task {
            do {
                try await engine.submitManualScrobble(
                    artist: artist,
                    title: title,
                    album: album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : album,
                    albumArtist: albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : albumArtist,
                    timestamp: ts,
                    quantity: quantity
                )
                isSubmitting = false
                withAnimation(.easeOut(duration: 0.25)) {
                    isSubmitted = true
                }
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeOut(duration: 0.4)) {
                    isSubmitted = false
                }
            } catch {
                isSubmitting = false
                errorText = error.localizedDescription
            }
        }
    }
}
