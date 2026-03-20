import Foundation

enum AppGroup {
    static let id = "group.com.kevin.FastScrobbler"
    static let userDefaults = UserDefaults(suiteName: id) ?? .standard
}

enum AppSettings {
    enum Keys {
        static let scrobbleListeningHistoryEnabled = "FastScrobbler.App.scrobbleListeningHistoryEnabled"
    }

    static func scrobbleListeningHistoryEnabled() -> Bool {
        if AppGroup.userDefaults.object(forKey: Keys.scrobbleListeningHistoryEnabled) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.scrobbleListeningHistoryEnabled)
    }
}

enum WhatsNewRelease {
    private enum Keys {
        static let lastSeenVersion = "FastScrobbler.WhatsNew.lastSeenVersion"
    }

    /// Release notes only exist for version 3.0; later versions should not reuse this screen automatically.
    static let version = "3.0"

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

enum ProEntitlement {
    static let productID = "com.kevin.FastScrobbler.pro"

    private static let purchasedDefaultsKey = "FastScrobbler.Pro.purchased"

    static var isPro: Bool {
        get {
#if os(macOS)
            true
#else
            AppGroup.userDefaults.bool(forKey: purchasedDefaultsKey)
#endif
        }
        set {
#if os(macOS)
            // Pro is always enabled on macOS.
#else
            AppGroup.userDefaults.set(newValue, forKey: purchasedDefaultsKey)
#endif
        }
    }
}

enum ProSettings {
    enum Keys {
        static let loveOnFavoriteEnabled = "FastScrobbler.Pro.loveOnFavoriteEnabled"
        static let scrobbleThresholdIndex = "FastScrobbler.Pro.scrobbleThresholdIndex"
        static let useAlbumArtistForScrobbling = "FastScrobbler.Pro.useAlbumArtistForScrobbling"
        static let stripEpAndSingleSuffixFromAlbum = "FastScrobbler.Pro.stripEpAndSingleSuffixFromAlbum"
        static let removeParenthesesEnabled = "FastScrobbler.Pro.removeParenthesesEnabled"
        static let removeAllParenthesesEnabled = "FastScrobbler.Pro.removeAllParenthesesEnabled"
        static let removeParenthesesKeywords = "FastScrobbler.Pro.removeParenthesesKeywords"
        static let preventDuplicateScrobblesEnabled = "FastScrobbler.Pro.preventDuplicateScrobblesEnabled"
        static let scrobbleListeningHistoryFromAllDevicesEnabled = "FastScrobbler.Pro.scrobbleListeningHistoryFromAllDevicesEnabled"
    }

    static let scrobbleThresholdOptions: [Double] = [0.10, 0.25, 0.50, 0.75]
    static let defaultScrobbleThresholdIndex: Int = 2
    static let defaultRemoveParenthesesKeywords: [String] = [
        "feat. ",
        "with ",
        "Remix",
        "Live",
        "Remaster",
        "Remastered",
        "from",
        "Radio Edit"
    ]

    static func loveOnFavoriteEnabled() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.loveOnFavoriteEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.loveOnFavoriteEnabled)
    }

    static func useAlbumArtistForScrobbling() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.useAlbumArtistForScrobbling) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.useAlbumArtistForScrobbling)
    }

    static func stripEpAndSingleSuffixFromAlbum() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.stripEpAndSingleSuffixFromAlbum) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.stripEpAndSingleSuffixFromAlbum)
    }

    static func removeParenthesesEnabled() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeParenthesesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeParenthesesEnabled)
    }

    static func removeAllParenthesesEnabled() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeAllParenthesesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeAllParenthesesEnabled)
    }

    static func preventDuplicateScrobblesEnabled() -> Bool {
        if AppGroup.userDefaults.object(forKey: Keys.preventDuplicateScrobblesEnabled) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.preventDuplicateScrobblesEnabled)
    }

    static func scrobbleListeningHistoryFromAllDevicesEnabled() -> Bool {
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.scrobbleListeningHistoryFromAllDevicesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.scrobbleListeningHistoryFromAllDevicesEnabled)
    }

    static func scrobbleThresholdFraction() -> Double {
        guard ProEntitlement.isPro else { return scrobbleThresholdOptions[defaultScrobbleThresholdIndex] }
        let idx = AppGroup.userDefaults.object(forKey: Keys.scrobbleThresholdIndex) as? Int ?? defaultScrobbleThresholdIndex
        let clamped = min(max(idx, 0), scrobbleThresholdOptions.count - 1)
        return scrobbleThresholdOptions[clamped]
    }

    static func scrobbleThresholdPercentText(index: Int) -> String {
        let clamped = min(max(index, 0), scrobbleThresholdOptions.count - 1)
        return "\(Int((scrobbleThresholdOptions[clamped] * 100).rounded()))%"
    }

    static func removeParenthesesKeywords() -> [String] {
        guard let data = AppGroup.userDefaults.data(forKey: Keys.removeParenthesesKeywords) else {
            return defaultRemoveParenthesesKeywords
        }

        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultRemoveParenthesesKeywords
        }

        return sanitizedRemoveParenthesesKeywords(decoded)
    }

    static func setRemoveParenthesesKeywords(_ keywords: [String]) {
        let sanitized = sanitizedRemoveParenthesesKeywords(keywords)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        AppGroup.userDefaults.set(data, forKey: Keys.removeParenthesesKeywords)
    }

    static func sanitizedRemoveParenthesesKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var sanitized: [String] = []

        for keyword in keywords {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            sanitized.append(keyword)
        }

        return sanitized
    }
}

struct Track: Codable, Equatable, Hashable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var albumArtist: String? = nil
    var durationSeconds: TimeInterval?
    var persistentID: UInt64?
    var playbackStoreID: String? = nil
    var isCompilation: Bool? = nil
}

extension Track {
    private static func normalizedMetadataComponent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func stableLibraryIdentity(
        persistentID: UInt64?,
        playbackStoreID: String?,
        artist: String,
        title: String,
        album: String?
    ) -> String {
        if let persistentID, persistentID != 0 {
            return "pid:\(persistentID)"
        }

        if let playbackStoreID {
            let trimmed = playbackStoreID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "sid:\(trimmed.lowercased())"
            }
        }

        let albumValue = album.map(normalizedMetadataComponent) ?? ""
        return "meta:\(normalizedMetadataComponent(artist))|\(normalizedMetadataComponent(title))|\(albumValue)"
    }

    static func usableAlbumArtistForArtistSubstitution(_ albumArtist: String?, isCompilation: Bool?) -> String? {
        guard let trimmed = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard isCompilation != true else { return nil }
        guard trimmed.compare("Various Artists", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else {
            return nil
        }
        return trimmed
    }

    static func albumArtistForScrobbleMetadata(_ albumArtist: String?) -> String? {
        guard let trimmed = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    var favoriteID: String {
        libraryIdentityKey
    }

    var libraryIdentityKey: String {
        Self.stableLibraryIdentity(
            persistentID: persistentID,
            playbackStoreID: playbackStoreID,
            artist: artist,
            title: title,
            album: album
        )
    }

    var dedupeKey: String {
        libraryIdentityKey
    }

    func applyingProScrobblePreferences() -> Track {
        var copy = self

        if ProSettings.useAlbumArtistForScrobbling() {
            copy = copy.applyingAlbumArtistAsArtistIfAvailable()
        }

        if ProSettings.stripEpAndSingleSuffixFromAlbum() {
            copy = copy.strippingEpAndSingleSuffixFromAlbumIfPresent()
        }

        if ProSettings.removeParenthesesEnabled() {
            copy = copy.removingConfiguredParentheticalTitleSegments()
        }

        return copy
    }

    func applyingAlbumArtistAsArtistIfAvailable() -> Track {
        guard let a = Self.usableAlbumArtistForArtistSubstitution(albumArtist, isCompilation: isCompilation) else {
            return self
        }
        var copy = self
        copy.artist = a
        return copy
    }

    func strippingEpAndSingleSuffixFromAlbumIfPresent() -> Track {
        guard let album, !album.isEmpty else { return self }

        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["- EP", "- Single"]
        let stripped: String = {
            for suffix in suffixes {
                if trimmed.hasSuffix(suffix) {
                    return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return trimmed
        }()

        var copy = self
        copy.album = stripped.isEmpty ? nil : stripped
        return copy
    }

    func removingConfiguredParentheticalTitleSegments() -> Track {
        let cleanedTitle = Self.cleanedTitleByRemovingParentheticalSegments(
            from: title,
            removeAll: ProSettings.removeAllParenthesesEnabled(),
            keywords: ProSettings.removeParenthesesKeywords()
        )
        guard cleanedTitle != title else { return self }

        var copy = self
        copy.title = cleanedTitle
        return copy
    }

    private static func cleanedTitleByRemovingParentheticalSegments(
        from title: String,
        removeAll: Bool,
        keywords: [String]
    ) -> String {
        guard removeAll || !keywords.isEmpty else { return title }

        let pattern = #"\([^()]*\)|\[[^\[\]]*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return title }

        var workingTitle = title
        var removedAnySegment = false

        while true {
            let matches = regex.matches(
                in: workingTitle,
                range: NSRange(workingTitle.startIndex..<workingTitle.endIndex, in: workingTitle)
            )
            guard !matches.isEmpty else { break }

            var rebuilt = ""
            var currentIndex = workingTitle.startIndex
            var removedOnThisPass = false

            for match in matches {
                guard let range = Range(match.range, in: workingTitle) else { continue }
                let segment = String(workingTitle[range])
                let inner = String(segment.dropFirst().dropLast())
                let shouldRemove = removeAll || keywords.contains { keyword in
                    parentheticalContent(inner, matchesWholeWordKeyword: keyword)
                }

                if shouldRemove {
                    rebuilt += String(workingTitle[currentIndex..<range.lowerBound])
                    removedOnThisPass = true
                } else {
                    rebuilt += String(workingTitle[currentIndex..<range.upperBound])
                }

                currentIndex = range.upperBound
            }

            rebuilt += String(workingTitle[currentIndex...])

            guard removedOnThisPass else { break }
            workingTitle = rebuilt
            removedAnySegment = true
        }

        guard removedAnySegment else { return title }

        let normalizedWhitespace = workingTitle.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedWhitespace.isEmpty ? title : normalizedWhitespace
    }

    private static func parentheticalContent(_ content: String, matchesWholeWordKeyword keyword: String) -> Bool {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return false }

        let escapedKeyword = NSRegularExpression.escapedPattern(for: trimmedKeyword)
        let pattern = #"(?i)(?<![\p{L}\p{N}])\#(escapedKeyword)(?![\p{L}\p{N}])"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }
}
