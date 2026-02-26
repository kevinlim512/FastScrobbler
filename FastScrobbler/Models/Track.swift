import Foundation

enum AppGroup {
    static let id = "group.com.kevin.FastScrobbler"
    static let userDefaults = UserDefaults(suiteName: id) ?? .standard
}

enum ProSettings {
    enum Keys {
        static let loveOnFavoriteEnabled = "FastScrobbler.Pro.loveOnFavoriteEnabled"
        static let scrobbleThresholdIndex = "FastScrobbler.Pro.scrobbleThresholdIndex"
        static let useAlbumArtistForScrobbling = "FastScrobbler.Pro.useAlbumArtistForScrobbling"
        static let stripEpAndSingleSuffixFromAlbum = "FastScrobbler.Pro.stripEpAndSingleSuffixFromAlbum"
    }

    static let scrobbleThresholdOptions: [Double] = [0.10, 0.25, 0.50, 0.75]
    static let defaultScrobbleThresholdIndex: Int = 2

    static func loveOnFavoriteEnabled() -> Bool {
        if AppGroup.userDefaults.object(forKey: Keys.loveOnFavoriteEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.loveOnFavoriteEnabled)
    }

    static func useAlbumArtistForScrobbling() -> Bool {
        if AppGroup.userDefaults.object(forKey: Keys.useAlbumArtistForScrobbling) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.useAlbumArtistForScrobbling)
    }

    static func stripEpAndSingleSuffixFromAlbum() -> Bool {
        if AppGroup.userDefaults.object(forKey: Keys.stripEpAndSingleSuffixFromAlbum) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.stripEpAndSingleSuffixFromAlbum)
    }

    static func scrobbleThresholdFraction() -> Double {
        let idx = AppGroup.userDefaults.object(forKey: Keys.scrobbleThresholdIndex) as? Int ?? defaultScrobbleThresholdIndex
        let clamped = min(max(idx, 0), scrobbleThresholdOptions.count - 1)
        return scrobbleThresholdOptions[clamped]
    }

    static func scrobbleThresholdPercentText(index: Int) -> String {
        let clamped = min(max(index, 0), scrobbleThresholdOptions.count - 1)
        return "\(Int((scrobbleThresholdOptions[clamped] * 100).rounded()))%"
    }
}

struct Track: Codable, Equatable, Hashable {
    var artist: String
    var title: String
    var album: String?
    var albumArtist: String? = nil
    var durationSeconds: TimeInterval?
    var persistentID: UInt64?
}

extension Track {
    var favoriteID: String {
        if let persistentID, persistentID != 0 { return "pid:\(persistentID)" }
        let albumValue = album ?? ""
        return "meta:\(artist)|\(title)|\(albumValue)"
    }

    var dedupeKey: String {
        if let persistentID, persistentID != 0 {
            return "pid:\(persistentID)"
        }

        let norm: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        let albumValue = album.map(norm) ?? ""
        return "meta:\(norm(artist))|\(norm(title))|\(albumValue)"
    }

    func applyingProScrobblePreferences() -> Track {
        var copy = self

        if ProSettings.useAlbumArtistForScrobbling() {
            copy = copy.applyingAlbumArtistAsArtistIfAvailable()
        }

        if ProSettings.stripEpAndSingleSuffixFromAlbum() {
            copy = copy.strippingEpAndSingleSuffixFromAlbumIfPresent()
        }

        return copy
    }

    func applyingAlbumArtistAsArtistIfAvailable() -> Track {
        guard let a = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return self }
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
}
