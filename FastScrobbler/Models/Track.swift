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
    }

    static let scrobbleThresholdOptions: [Double] = [0.10, 0.25, 0.50, 0.75]
    static let defaultScrobbleThresholdIndex: Int = 2

    static func loveOnFavoriteEnabled(isPro: Bool) -> Bool {
        guard isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.loveOnFavoriteEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.loveOnFavoriteEnabled)
    }

    static func useAlbumArtistForScrobbling(isPro: Bool) -> Bool {
        guard isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.useAlbumArtistForScrobbling) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.useAlbumArtistForScrobbling)
    }

    static func scrobbleThresholdFraction(isPro: Bool) -> Double {
        guard isPro else { return 0.50 }
        let idx = AppGroup.userDefaults.object(forKey: Keys.scrobbleThresholdIndex) as? Int ?? defaultScrobbleThresholdIndex
        let clamped = min(max(idx, 0), scrobbleThresholdOptions.count - 1)
        return scrobbleThresholdOptions[clamped]
    }

    static func scrobbleThresholdPercentText(index: Int) -> String {
        let clamped = min(max(index, 0), scrobbleThresholdOptions.count - 1)
        return "\(Int((scrobbleThresholdOptions[clamped] * 100).rounded()))%"
    }
}

enum ProEntitlement {
    static let cachedEntitledKey = "FastScrobbler.Pro.entitled"

    static func cachedIsPro() -> Bool {
#if os(macOS)
        true
#else
        AppGroup.userDefaults.bool(forKey: cachedEntitledKey)
#endif
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

    func applyingAlbumArtistAsArtistIfAvailable() -> Track {
        guard let a = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty else { return self }
        var copy = self
        copy.artist = a
        return copy
    }
}
