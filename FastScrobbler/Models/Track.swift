import Foundation

// Shared app group used by the main app, extensions, and widgets to access common UserDefaults and the shared container.
enum AppGroup {
    static let id = "group.com.kevin.FastScrobbler"
    // Falls back to .standard so the app still functions outside an app group (e.g. unit tests).

    static let userDefaults = UserDefaults(suiteName: id) ?? .standard

    static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static func sharedDataDirectoryURL() -> URL? {
        sharedContainerURL()?.appendingPathComponent("FastScrobblerShared", isDirectory: true)
    }
}

enum ICloudSyncLocalStore: String {
    case backlog
    case scrobbleLog
}

enum ICloudSyncLocalChangeNotifier {
    private static let notificationName = Notification.Name("FastScrobbler.ICloudSync.localStoreDidChange")

    static func post(_ store: ICloudSyncLocalStore) {
        NotificationCenter.default.post(name: notificationName, object: store.rawValue)
    }

    static var name: Notification.Name {
        notificationName
    }
}

enum AppSettings {
    enum PendingListeningHistoryLaunchRequest: String {
        case openReviewOnly
        case scanAndOpenReview
        case scanAndShowResult
    }

    enum Keys {
        // Retired in favor of Listening History confirmation mode. Kept only for legacy key cleanup.
        static let scrobbleListeningHistoryEnabled = "FastScrobbler.App.scrobbleListeningHistoryEnabled"
        static let scrobbleAppleMusicAPIEnabled = "FastScrobbler.App.scrobbleAppleMusicAPIEnabled"
        static let scrobbleOnlyNonLibraryAppleMusicAPITracks = "FastScrobbler.App.scrobbleOnlyNonLibraryAppleMusicAPITracks"
        static let extendedListeningHistoryScanEnabled = "FastScrobbler.App.extendedListeningHistoryScanEnabled"
        static let listeningHistoryRequireConfirmationEnabled = "FastScrobbler.App.listeningHistoryRequireConfirmationEnabled"
        static let listeningHistoryResumeRecoveryCutoffDate = "FastScrobbler.App.listeningHistoryResumeRecoveryCutoffDate"
        static let pendingListeningHistoryLaunchRequest = "FastScrobbler.App.pendingListeningHistoryLaunchRequest"
        static let pendingListeningHistoryReviewOpenRequestToken = "FastScrobbler.App.pendingListeningHistoryReviewOpenRequestToken"
        static let pendingManualScrobbleLaunchRequest = "FastScrobbler.App.pendingManualScrobbleLaunchRequest"
        static let pendingHelpLaunchRequest = "FastScrobbler.App.pendingHelpLaunchRequest"
        static let sendNowPlayingAutomaticallyEnabled = "FastScrobbler.App.sendNowPlayingAutomaticallyEnabled"
        static let themeSelection = "FastScrobbler.App.themeSelection"
        static let buttonThemeSelection = "FastScrobbler.App.buttonThemeSelection"
        static let scanButtonLocation = "FastScrobbler.App.scanButtonLocation"
        static let iCloudSyncEnabled = "FastScrobbler.App.iCloudSyncEnabled"
    }

    static func migrateLegacyAppGroupSettingsIfNeeded() {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleListeningHistoryEnabled)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleAppleMusicAPIEnabled)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.extendedListeningHistoryScanEnabled)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.listeningHistoryRequireConfirmationEnabled)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.listeningHistoryResumeRecoveryCutoffDate)
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.sendNowPlayingAutomaticallyEnabled)
    }

    static func extendedListeningHistoryScanEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.extendedListeningHistoryScanEnabled)
        if AppGroup.userDefaults.object(forKey: Keys.extendedListeningHistoryScanEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.extendedListeningHistoryScanEnabled)
    }

    static func listeningHistoryRequireConfirmationEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.listeningHistoryRequireConfirmationEnabled)
        if AppGroup.userDefaults.object(forKey: Keys.listeningHistoryRequireConfirmationEnabled) == nil {
#if os(iOS)
            return true
#else
            return false
#endif
        }
        return AppGroup.userDefaults.bool(forKey: Keys.listeningHistoryRequireConfirmationEnabled)
    }

    static func listeningHistoryResumeRecoveryCutoffDate() -> Date? {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.listeningHistoryResumeRecoveryCutoffDate)
        return AppGroup.userDefaults.object(forKey: Keys.listeningHistoryResumeRecoveryCutoffDate) as? Date
    }

    static func setListeningHistoryResumeRecoveryCutoffDate(_ date: Date?) {
        if let date {
            AppGroup.userDefaults.set(date, forKey: Keys.listeningHistoryResumeRecoveryCutoffDate)
        } else {
            AppGroup.userDefaults.removeObject(forKey: Keys.listeningHistoryResumeRecoveryCutoffDate)
        }
    }

    static func noteListeningHistoryRecoveryResumeNow() {
        setListeningHistoryResumeRecoveryCutoffDate(Date())
    }

    static func requestPendingListeningHistoryLaunch(_ request: PendingListeningHistoryLaunchRequest) {
        AppGroup.userDefaults.set(request.rawValue, forKey: Keys.pendingListeningHistoryLaunchRequest)
    }

    static func consumePendingListeningHistoryLaunchRequest() -> PendingListeningHistoryLaunchRequest? {
        if let rawValue = AppGroup.userDefaults.string(forKey: Keys.pendingListeningHistoryLaunchRequest) {
            AppGroup.userDefaults.removeObject(forKey: Keys.pendingListeningHistoryLaunchRequest)
            if let request = PendingListeningHistoryLaunchRequest(rawValue: rawValue) {
                return request
            }
        }

        guard AppGroup.userDefaults.object(forKey: Keys.pendingListeningHistoryReviewOpenRequestToken) != nil else {
            return nil
        }
        AppGroup.userDefaults.removeObject(forKey: Keys.pendingListeningHistoryReviewOpenRequestToken)
        return .openReviewOnly
    }

    static func requestOpeningListeningHistoryReview() {
        requestPendingListeningHistoryLaunch(.openReviewOnly)
    }

    static func consumePendingListeningHistoryReviewOpenRequest() -> Bool {
        consumePendingListeningHistoryLaunchRequest() == .openReviewOnly
    }

    static func requestPendingManualScrobbleLaunch() {
        AppGroup.userDefaults.set(true, forKey: Keys.pendingManualScrobbleLaunchRequest)
    }

    static func consumePendingManualScrobbleLaunchRequest() -> Bool {
        guard AppGroup.userDefaults.bool(forKey: Keys.pendingManualScrobbleLaunchRequest) else { return false }
        AppGroup.userDefaults.removeObject(forKey: Keys.pendingManualScrobbleLaunchRequest)
        return true
    }

    static func requestPendingHelpLaunch() {
        AppGroup.userDefaults.set(true, forKey: Keys.pendingHelpLaunchRequest)
    }

    static func consumePendingHelpLaunchRequest() -> Bool {
        guard AppGroup.userDefaults.bool(forKey: Keys.pendingHelpLaunchRequest) else { return false }
        AppGroup.userDefaults.removeObject(forKey: Keys.pendingHelpLaunchRequest)
        return true
    }

    static func scrobbleAppleMusicAPIEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleAppleMusicAPIEnabled)
        if AppGroup.userDefaults.object(forKey: Keys.scrobbleAppleMusicAPIEnabled) == nil {
            let hasSeenSetup = UserDefaults.standard.bool(forKey: "FastScrobbler.Setup.hasSeen") || AppGroup.userDefaults.bool(forKey: "FastScrobbler.Setup.hasSeen")
            let isAutoScrobbleOff = listeningHistoryRequireConfirmationEnabled()
            return !hasSeenSetup || isAutoScrobbleOff
        }
        return AppGroup.userDefaults.bool(forKey: Keys.scrobbleAppleMusicAPIEnabled)
    }

    static func seedScrobbleAppleMusicAPIEnabledIfNeeded() {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleAppleMusicAPIEnabled)
        let migrationKey = "FastScrobbler.App.didMigrateApiScrobbleForAutoScrobbleOff_v2"
        if !AppGroup.userDefaults.bool(forKey: migrationKey) {
            let hasSeenSetup = UserDefaults.standard.bool(forKey: "FastScrobbler.Setup.hasSeen") || AppGroup.userDefaults.bool(forKey: "FastScrobbler.Setup.hasSeen")
            let isAutoScrobbleOff = listeningHistoryRequireConfirmationEnabled()
            let shouldEnable = !hasSeenSetup || isAutoScrobbleOff
            AppGroup.userDefaults.set(shouldEnable, forKey: Keys.scrobbleAppleMusicAPIEnabled)
            AppGroup.userDefaults.set(true, forKey: migrationKey)
            return
        }

        guard AppGroup.userDefaults.object(forKey: Keys.scrobbleAppleMusicAPIEnabled) == nil else { return }
        let hasSeenSetup = UserDefaults.standard.bool(forKey: "FastScrobbler.Setup.hasSeen") || AppGroup.userDefaults.bool(forKey: "FastScrobbler.Setup.hasSeen")
        let isAutoScrobbleOff = listeningHistoryRequireConfirmationEnabled()
        AppGroup.userDefaults.set(!hasSeenSetup || isAutoScrobbleOff, forKey: Keys.scrobbleAppleMusicAPIEnabled)
    }

    static func scrobbleOnlyNonLibraryAppleMusicAPITracks() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
        if AppGroup.userDefaults.object(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
    }

    static func seedScrobbleOnlyNonLibraryAppleMusicAPITracksIfNeeded() {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
        guard AppGroup.userDefaults.object(forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks) == nil else { return }
        AppGroup.userDefaults.set(true, forKey: Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks)
    }

    static func removeLegacyListeningHistoryScrobblingToggleIfNeeded() {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleListeningHistoryEnabled)
        AppGroup.userDefaults.removeObject(forKey: Keys.scrobbleListeningHistoryEnabled)
        UserDefaults.standard.removeObject(forKey: Keys.scrobbleListeningHistoryEnabled)
    }

    static func sendNowPlayingAutomaticallyEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.sendNowPlayingAutomaticallyEnabled)
        if AppGroup.userDefaults.object(forKey: Keys.sendNowPlayingAutomaticallyEnabled) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.sendNowPlayingAutomaticallyEnabled)
    }

    static func themeSelection() -> AppTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: Keys.themeSelection) else {
            return .system
        }
        return AppTheme(rawValue: rawValue) ?? .system
    }

    static func buttonThemeSelection() -> ButtonTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: Keys.buttonThemeSelection) else {
            return .colorful
        }
        return ButtonTheme(rawValue: rawValue) ?? .colorful
    }

    static func iCloudSyncEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)
    }

    static func setICloudSyncEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Keys.iCloudSyncEnabled)
    }

    private static func migrateLegacyAppGroupValueIfNeeded(forKey key: String) {
        guard AppGroup.userDefaults.object(forKey: key) == nil else { return }
        guard let legacyValue = UserDefaults.standard.object(forKey: key) else { return }
        AppGroup.userDefaults.set(legacyValue, forKey: key)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }
}

enum ButtonTheme: String, CaseIterable, Identifiable {
    case colorful
    case monochrome

    var id: String {
        rawValue
    }
}

enum ScanButtonLocation: String, CaseIterable, Identifiable {
    case recentScrobbles
    case homeTabActions
    case disabled

    var id: String {
        rawValue
    }

    var localizedName: String {
        switch self {
        case .recentScrobbles:
            return NSLocalizedString("Recent Scrobbles List", comment: "")
        case .homeTabActions:
            return NSLocalizedString("Home Tab Actions", comment: "")
        case .disabled:
            return NSLocalizedString("Off", comment: "")
        }
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
        static let useFirstArtistOnlyForScrobbling = "FastScrobbler.Pro.useFirstArtistOnlyForScrobbling"
        static let firstArtistOnlyIgnoredArtists = "FastScrobbler.Pro.firstArtistOnlyIgnoredArtists"
        static let stripEpAndSingleSuffixFromAlbum = "FastScrobbler.Pro.stripEpAndSingleSuffixFromAlbum"
        static let removeBracketsFromSongTitlesEnabled = "FastScrobbler.Pro.removeBracketsEnabled"
        static let removeAllBracketsFromSongTitlesEnabled = "FastScrobbler.Pro.removeAllBracketsEnabled"
        static let removeBracketsFromSongTitleKeywords = "FastScrobbler.Pro.removeBracketsKeywords"
        static let removeBracketsFromAlbumTitlesEnabled = "FastScrobbler.Pro.removeBracketsFromAlbumTitlesEnabled"
        static let removeAllBracketsFromAlbumTitlesEnabled = "FastScrobbler.Pro.removeAllBracketsFromAlbumTitlesEnabled"
        static let removeBracketsFromAlbumTitleKeywords = "FastScrobbler.Pro.removeBracketsFromAlbumTitleKeywords"
        static let preventDuplicateScrobblesEnabled = "FastScrobbler.Pro.preventDuplicateScrobblesEnabled"
        static let textReplacementRules = "FastScrobbler.Pro.textReplacementRules"
    }

    static let scrobbleThresholdOptions: [Double] = {
#if os(macOS)
        [0.10, 0.25, 0.50, 0.75, 0.90]
#else
        [0.10, 0.25, 0.50, 0.75]
#endif
    }()
    static let defaultScrobbleThresholdIndex: Int = 2
    static let defaultRemoveBracketsKeywords: [String] = [
        "feat. ",
        "with ",
        "Remix",
        "Live",
        "Remaster",
        "Remastered",
        "from",
        "Radio Edit"
    ]
    static let defaultRemoveBracketsFromAlbumTitleKeywords: [String] = [
        "Deluxe",
        "Edition",
        "Remastered",
        "Remaster",
        "Bonus",
        "Special"
    ]

    static func migrateLegacyAppGroupSettingsIfNeeded() {
        for key in appGroupBackedKeys {
            migrateLegacyAppGroupValueIfNeeded(forKey: key)
        }
    }

    static func loveOnFavoriteEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.loveOnFavoriteEnabled)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.loveOnFavoriteEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.loveOnFavoriteEnabled)
    }

    static func useAlbumArtistForScrobbling() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.useAlbumArtistForScrobbling)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.useAlbumArtistForScrobbling) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.useAlbumArtistForScrobbling)
    }

    static func useFirstArtistOnlyForScrobbling() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.useFirstArtistOnlyForScrobbling)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.useFirstArtistOnlyForScrobbling) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.useFirstArtistOnlyForScrobbling)
    }

    static func stripEpAndSingleSuffixFromAlbum() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.stripEpAndSingleSuffixFromAlbum)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.stripEpAndSingleSuffixFromAlbum) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.stripEpAndSingleSuffixFromAlbum)
    }

    static func removeBracketsFromSongTitlesEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeBracketsFromSongTitlesEnabled)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeBracketsFromSongTitlesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeBracketsFromSongTitlesEnabled)
    }

    static func removeAllBracketsFromSongTitlesEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeAllBracketsFromSongTitlesEnabled)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeAllBracketsFromSongTitlesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeAllBracketsFromSongTitlesEnabled)
    }

    static func removeBracketsFromAlbumTitlesEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeBracketsFromAlbumTitlesEnabled)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeBracketsFromAlbumTitlesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeBracketsFromAlbumTitlesEnabled)
    }

    static func removeAllBracketsFromAlbumTitlesEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeAllBracketsFromAlbumTitlesEnabled)
        guard ProEntitlement.isPro else { return false }
        if AppGroup.userDefaults.object(forKey: Keys.removeAllBracketsFromAlbumTitlesEnabled) == nil { return false }
        return AppGroup.userDefaults.bool(forKey: Keys.removeAllBracketsFromAlbumTitlesEnabled)
    }

    static func preventDuplicateScrobblesEnabled() -> Bool {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.preventDuplicateScrobblesEnabled)
        // Default to true — safer to skip a duplicate scrobble than to send one.
        if AppGroup.userDefaults.object(forKey: Keys.preventDuplicateScrobblesEnabled) == nil { return true }
        return AppGroup.userDefaults.bool(forKey: Keys.preventDuplicateScrobblesEnabled)
    }

    static func scrobbleThresholdFraction() -> Double {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.scrobbleThresholdIndex)
        guard ProEntitlement.isPro else { return scrobbleThresholdOptions[defaultScrobbleThresholdIndex] }
        let idx = AppGroup.userDefaults.object(forKey: Keys.scrobbleThresholdIndex) as? Int ?? defaultScrobbleThresholdIndex
        let clamped = min(max(idx, 0), scrobbleThresholdOptions.count - 1)
        return scrobbleThresholdOptions[clamped]
    }

    static func scrobbleThresholdPercentText(index: Int) -> String {
        let clamped = min(max(index, 0), scrobbleThresholdOptions.count - 1)
        return "\(Int((scrobbleThresholdOptions[clamped] * 100).rounded()))%"
    }

    static func removeBracketsFromSongTitleKeywords() -> [String] {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeBracketsFromSongTitleKeywords)
        guard let data = AppGroup.userDefaults.data(forKey: Keys.removeBracketsFromSongTitleKeywords) else {
            return defaultRemoveBracketsKeywords
        }

        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultRemoveBracketsKeywords
        }

        return sanitizedRemoveBracketsKeywords(decoded)
    }

    static func setRemoveBracketsFromSongTitleKeywords(_ keywords: [String]) {
        let sanitized = sanitizedRemoveBracketsKeywords(keywords)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        AppGroup.userDefaults.set(data, forKey: Keys.removeBracketsFromSongTitleKeywords)
    }

    static func removeBracketsFromAlbumTitleKeywords() -> [String] {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.removeBracketsFromAlbumTitleKeywords)
        guard let data = AppGroup.userDefaults.data(forKey: Keys.removeBracketsFromAlbumTitleKeywords) else {
            return defaultRemoveBracketsFromAlbumTitleKeywords
        }

        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultRemoveBracketsFromAlbumTitleKeywords
        }

        return sanitizedRemoveBracketsKeywords(decoded)
    }

    static func setRemoveBracketsFromAlbumTitleKeywords(_ keywords: [String]) {
        let sanitized = sanitizedRemoveBracketsKeywords(keywords)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        AppGroup.userDefaults.set(data, forKey: Keys.removeBracketsFromAlbumTitleKeywords)
    }

    // Stable IDs for built-in rules so they can be matched across saves without relying on position.
    static let builtInRuleIDs: Set<UUID> = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    ]
    // Shipped disabled by default; users must explicitly opt in.
    private static let builtInRules: [TextReplacementRule] = [
        TextReplacementRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, find: "- Single", replace: "", scope: .album, isEnabled: false),
        TextReplacementRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, find: "- EP", replace: "", scope: .album, isEnabled: false),
    ]

    static func textReplacementRules() -> [TextReplacementRule] {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.textReplacementRules)
        let saved = AppGroup.userDefaults.data(forKey: Keys.textReplacementRules)
            .flatMap { try? JSONDecoder().decode([TextReplacementRule].self, from: $0) } ?? []
        // Merge persisted enabled-state into built-in rules so they always appear first (pinned).
        var pinned = builtInRules
        for (i, rule) in pinned.enumerated() {
            if let savedRule = saved.first(where: { $0.id == rule.id }) {
                pinned[i].isEnabled = savedRule.isEnabled
            }
        }
        let userRules = saved.filter { !builtInRuleIDs.contains($0.id) }
        return pinned + userRules
    }

    static func firstArtistOnlyIgnoredArtists() -> [String] {
        migrateLegacyAppGroupValueIfNeeded(forKey: Keys.firstArtistOnlyIgnoredArtists)
        guard let data = AppGroup.userDefaults.data(forKey: Keys.firstArtistOnlyIgnoredArtists) else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return sanitizedIgnoredArtists(decoded)
    }

    static func setFirstArtistOnlyIgnoredArtists(_ artists: [String]) {
        let sanitized = sanitizedIgnoredArtists(artists)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        AppGroup.userDefaults.set(data, forKey: Keys.firstArtistOnlyIgnoredArtists)
    }

    static func sanitizedIgnoredArtists(_ artists: [String]) -> [String] {
        var seen = Set<String>()
        var sanitized: [String] = []

        for artist in artists {
            let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            sanitized.append(trimmed)
        }

        return sanitized
    }

    static func setTextReplacementRules(_ rules: [TextReplacementRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        AppGroup.userDefaults.set(data, forKey: Keys.textReplacementRules)
    }

    private static let appGroupBackedKeys = [
        Keys.loveOnFavoriteEnabled,
        Keys.scrobbleThresholdIndex,
        Keys.useAlbumArtistForScrobbling,
        Keys.useFirstArtistOnlyForScrobbling,
        Keys.firstArtistOnlyIgnoredArtists,
        Keys.stripEpAndSingleSuffixFromAlbum,
        Keys.removeBracketsFromSongTitlesEnabled,
        Keys.removeAllBracketsFromSongTitlesEnabled,
        Keys.removeBracketsFromSongTitleKeywords,
        Keys.removeBracketsFromAlbumTitlesEnabled,
        Keys.removeAllBracketsFromAlbumTitlesEnabled,
        Keys.removeBracketsFromAlbumTitleKeywords,
        Keys.preventDuplicateScrobblesEnabled,
        Keys.textReplacementRules,
    ]

    private static func migrateLegacyAppGroupValueIfNeeded(forKey key: String) {
        guard AppGroup.userDefaults.object(forKey: key) == nil else { return }
        guard let legacyValue = UserDefaults.standard.object(forKey: key) else { return }
        AppGroup.userDefaults.set(legacyValue, forKey: key)
    }

    static func sanitizedRemoveBracketsKeywords(_ keywords: [String]) -> [String] {
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

enum TextReplacementScope: String, Codable, CaseIterable, Sendable {
    case all
    case artist
    case track
    case album

    var displayName: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "Text replacement scope: all fields")
        case .artist: return NSLocalizedString("Artist", comment: "Text replacement scope: artist field")
        case .track: return NSLocalizedString("Song", comment: "Text replacement scope: track/song field")
        case .album: return NSLocalizedString("Album", comment: "Text replacement scope: album field")
        }
    }
}

struct StorageUsageSnapshot: Sendable {
    var backlogCount: Int
    var backlogBytes: Int64
    var scrobbleLogCount: Int
    var scrobbleLogBytes: Int64
    var playbackHistoryStateBytes: Int64
    var recentTracksStateBytes: Int64
}

struct TextReplacementRule: Codable, Identifiable, Sendable {
    var id: UUID
    var find: String
    var replace: String
    var scope: TextReplacementScope
    var isEnabled: Bool

    init(id: UUID, find: String, replace: String, scope: TextReplacementScope, isEnabled: Bool = true) {
        self.id = id
        self.find = find
        self.replace = replace
        self.scope = scope
        self.isEnabled = isEnabled
    }
}

struct Track: Codable, Equatable, Hashable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var albumArtist: String? = nil
    var durationSeconds: TimeInterval?
    var usesFallbackDuration: Bool? = nil
    var persistentID: UInt64?
    var playbackStoreID: String? = nil
    var isCompilation: Bool? = nil
}

struct ScrobbleMetadataPreferences: Sendable {
    var useAlbumArtistForScrobbling: Bool
    var useFirstArtistOnlyForScrobbling: Bool
    var firstArtistOnlyIgnoredArtists: [String]
    var removeBracketsFromSongTitles: Bool
    var removeAllBracketsFromSongTitles: Bool
    var songTitleBracketKeywords: [String]
    var removeBracketsFromAlbumTitles: Bool
    var removeAllBracketsFromAlbumTitles: Bool
    var albumTitleBracketKeywords: [String]
    var textReplacementRules: [TextReplacementRule]

    static var current: ScrobbleMetadataPreferences {
        ScrobbleMetadataPreferences(
            useAlbumArtistForScrobbling: ProSettings.useAlbumArtistForScrobbling(),
            useFirstArtistOnlyForScrobbling: ProSettings.useFirstArtistOnlyForScrobbling(),
            firstArtistOnlyIgnoredArtists: ProSettings.firstArtistOnlyIgnoredArtists(),
            removeBracketsFromSongTitles: ProSettings.removeBracketsFromSongTitlesEnabled(),
            removeAllBracketsFromSongTitles: ProSettings.removeAllBracketsFromSongTitlesEnabled(),
            songTitleBracketKeywords: ProSettings.removeBracketsFromSongTitleKeywords(),
            removeBracketsFromAlbumTitles: ProSettings.removeBracketsFromAlbumTitlesEnabled(),
            removeAllBracketsFromAlbumTitles: ProSettings.removeAllBracketsFromAlbumTitlesEnabled(),
            albumTitleBracketKeywords: ProSettings.removeBracketsFromAlbumTitleKeywords(),
            textReplacementRules: ProSettings.textReplacementRules()
        )
    }

    func apply(to track: Track) -> Track {
        var copy = track

        if useAlbumArtistForScrobbling {
            copy = copy.applyingAlbumArtistAsArtistIfAvailable()
        }

        if useFirstArtistOnlyForScrobbling {
            copy = copy.applyingFirstArtistOnlyIfNeeded(ignoredArtists: firstArtistOnlyIgnoredArtists)
        }

        if removeBracketsFromAlbumTitles {
            copy = copy.removingConfiguredParentheticalAlbumSegments(
                removeAll: removeAllBracketsFromAlbumTitles,
                keywords: albumTitleBracketKeywords
            )
        }

        if removeBracketsFromSongTitles {
            copy = copy.removingConfiguredParentheticalTitleSegments(
                removeAll: removeAllBracketsFromSongTitles,
                keywords: songTitleBracketKeywords
            )
        }

        if !textReplacementRules.isEmpty {
            copy = copy.applyingTextReplacements(textReplacementRules)
        }

        return copy
    }
}

extension Track {
    private static func normalizedMetadataComponent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Returns a stable string key that uniquely identifies a track across app launches.
    // Priority: local persistentID > store ID > metadata fingerprint (least stable, used as fallback).
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

    // Returns the album artist only if it's suitable to substitute for the track artist.
    // Rejects "Various Artists" to avoid scrobbling under a generic name.
    static func usableAlbumArtistForArtistSubstitution(
        _ albumArtist: String?,
        isCompilation: Bool? = nil,
        respectsCompilationFlag: Bool = false
    ) -> String? {
        guard let trimmed = albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
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
        applyingScrobbleMetadataPreferences(.current)
    }

    func applyingScrobbleMetadataPreferences(_ preferences: ScrobbleMetadataPreferences) -> Track {
        preferences.apply(to: self)
    }

    func applyingTextReplacements(_ rules: [TextReplacementRule]) -> Track {
        var copy = self
        for rule in rules {
            guard !rule.find.isEmpty, rule.isEnabled else { continue }
            switch rule.scope {
            case .all:
                copy.artist = copy.artist.replacingOccurrences(of: rule.find, with: rule.replace)
                copy.title = copy.title.replacingOccurrences(of: rule.find, with: rule.replace)
                copy.album = copy.album?.replacingOccurrences(of: rule.find, with: rule.replace)
            case .artist:
                copy.artist = copy.artist.replacingOccurrences(of: rule.find, with: rule.replace)
            case .track:
                copy.title = copy.title.replacingOccurrences(of: rule.find, with: rule.replace)
            case .album:
                copy.album = copy.album?.replacingOccurrences(of: rule.find, with: rule.replace)
            }
        }
        return copy
    }

    func applyingAlbumArtistAsArtistIfAvailable() -> Track {
        guard let a = Self.usableAlbumArtistForArtistSubstitution(
            albumArtist, isCompilation: isCompilation
        ) else {
            return self
        }
        var copy = self
        copy.artist = a
        copy.albumArtist = nil  // artist field now carries the album artist; avoid sending it twice
        return copy
    }

    func applyingFirstArtistOnlyIfNeeded(ignoredArtists: [String] = ProSettings.firstArtistOnlyIgnoredArtists()) -> Track {
        guard let firstArtist = Self.firstArtistOnly(from: artist, ignoredArtists: ignoredArtists) else {
            return self
        }

        var copy = self
        copy.artist = firstArtist
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
        removingConfiguredParentheticalTitleSegments(
            removeAll: ProSettings.removeAllBracketsFromSongTitlesEnabled(),
            keywords: ProSettings.removeBracketsFromSongTitleKeywords()
        )
    }

    func removingConfiguredParentheticalTitleSegments(removeAll: Bool, keywords: [String]) -> Track {
        let cleanedTitle = Self.cleanedMetadataByRemovingParentheticalSegments(
            from: title,
            removeAll: removeAll,
            keywords: keywords
        )
        guard cleanedTitle != title else { return self }

        var copy = self
        copy.title = cleanedTitle
        return copy
    }

    func removingConfiguredParentheticalAlbumSegments() -> Track {
        removingConfiguredParentheticalAlbumSegments(
            removeAll: ProSettings.removeAllBracketsFromAlbumTitlesEnabled(),
            keywords: ProSettings.removeBracketsFromAlbumTitleKeywords()
        )
    }

    func removingConfiguredParentheticalAlbumSegments(removeAll: Bool, keywords: [String]) -> Track {
        guard let album, !album.isEmpty else { return self }

        let cleanedAlbum = Self.cleanedMetadataByRemovingParentheticalSegments(
            from: album,
            removeAll: removeAll,
            keywords: keywords
        )
        guard cleanedAlbum != album else { return self }

        var copy = self
        copy.album = cleanedAlbum
        return copy
    }

    // Matches one level of (…) or […] — nested brackets require multiple passes.
    private static let parentheticalSegmentRegex = try? NSRegularExpression(pattern: #"\([^()]*\)|\[[^\[\]]*\]"#)

    static func firstArtistOnly(from artist: String, ignoredArtists: [String] = []) -> String? {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty else { return nil }

        let normalizedArtist = trimmedArtist.lowercased()
        for ignored in ignoredArtists {
            if ignored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedArtist {
                return nil
            }
        }

        let separators: [Character] = ["&", ","]
        var earliestSeparatorIndex: String.Index?

        for separator in separators {
            guard let index = trimmedArtist.firstIndex(of: separator) else { continue }
            if let currentEarliest = earliestSeparatorIndex {
                if index < currentEarliest {
                    earliestSeparatorIndex = index
                }
            } else {
                earliestSeparatorIndex = index
            }
        }

        guard let splitIndex = earliestSeparatorIndex else { return trimmedArtist == artist ? nil : trimmedArtist }

        let firstArtist = trimmedArtist[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstArtist.isEmpty else { return nil }
        return firstArtist == artist ? nil : firstArtist
    }

    private static func cleanedMetadataByRemovingParentheticalSegments(
        from value: String,
        removeAll: Bool,
        keywords: [String]
    ) -> String {
        guard removeAll || !keywords.isEmpty else { return value }

        guard let regex = parentheticalSegmentRegex else { return value }

        var workingValue = value
        var removedAnySegment = false
        // Cap passes to guard against pathological inputs with many nested brackets.
        var passesRemaining = 5

        while passesRemaining > 0 {
            passesRemaining -= 1
            let matches = regex.matches(
                in: workingValue,
                range: NSRange(workingValue.startIndex..<workingValue.endIndex, in: workingValue)
            )
            guard !matches.isEmpty else { break }

            var rebuilt = ""
            var currentIndex = workingValue.startIndex
            var removedOnThisPass = false

            for match in matches {
                guard let range = Range(match.range, in: workingValue) else { continue }
                let segment = String(workingValue[range])
                let inner = String(segment.dropFirst().dropLast())
                let shouldRemove = removeAll || keywords.contains { keyword in
                    parentheticalContent(inner, matchesWholeWordKeyword: keyword)
                }

                if shouldRemove {
                    rebuilt += String(workingValue[currentIndex..<range.lowerBound])
                    removedOnThisPass = true
                } else {
                    rebuilt += String(workingValue[currentIndex..<range.upperBound])
                }

                currentIndex = range.upperBound
            }

            rebuilt += String(workingValue[currentIndex...])

            guard removedOnThisPass else { break }
            workingValue = rebuilt
            removedAnySegment = true
        }

        guard removedAnySegment else { return value }

        let normalizedWhitespace = workingValue.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Fall back to the original value if stripping everything would leave an empty string.
        return normalizedWhitespace.isEmpty ? value : normalizedWhitespace
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
