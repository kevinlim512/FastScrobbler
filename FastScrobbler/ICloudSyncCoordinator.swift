import Foundation
import OSLog

private enum ICloudSyncContainer {
    static let identifier = "iCloud.com.kevin.FastScrobbler"
    static let relativeDirectory = "Documents/FastScrobblerSync"
}

private enum SyncedSettingsStore {
    enum Storage: String, Codable {
        case appGroup
        case standard
    }

    struct Entry: Codable {
        var key: String
        var storage: Storage
        var value: Value
        var updatedAt: Date
    }

    struct Payload: Codable {
        var version: Int = 1
        var entries: [Entry]
    }

    enum Value: Codable, Equatable {
        case bool(Bool)
        case int(Int)
        case string(String)
        case stringArray([String])
        case textReplacementRules([TextReplacementRule])

        private enum CodingKeys: String, CodingKey {
            case kind
            case boolValue
            case intValue
            case stringValue
            case stringArrayValue
            case textReplacementRulesValue
        }

        private enum Kind: String, Codable {
            case bool
            case int
            case string
            case stringArray
            case textReplacementRules
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .bool:
                self = .bool(try container.decode(Bool.self, forKey: .boolValue))
            case .int:
                self = .int(try container.decode(Int.self, forKey: .intValue))
            case .string:
                self = .string(try container.decode(String.self, forKey: .stringValue))
            case .stringArray:
                self = .stringArray(try container.decode([String].self, forKey: .stringArrayValue))
            case .textReplacementRules:
                self = .textReplacementRules(try container.decode([TextReplacementRule].self, forKey: .textReplacementRulesValue))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bool(let value):
                try container.encode(Kind.bool, forKey: .kind)
                try container.encode(value, forKey: .boolValue)
            case .int(let value):
                try container.encode(Kind.int, forKey: .kind)
                try container.encode(value, forKey: .intValue)
            case .string(let value):
                try container.encode(Kind.string, forKey: .kind)
                try container.encode(value, forKey: .stringValue)
            case .stringArray(let value):
                try container.encode(Kind.stringArray, forKey: .kind)
                try container.encode(value, forKey: .stringArrayValue)
            case .textReplacementRules(let value):
                try container.encode(Kind.textReplacementRules, forKey: .kind)
                try container.encode(value, forKey: .textReplacementRulesValue)
            }
        }

        static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.bool(left), .bool(right)):
                return left == right
            case let (.int(left), .int(right)):
                return left == right
            case let (.string(left), .string(right)):
                return left == right
            case let (.stringArray(left), .stringArray(right)):
                return left == right
            case let (.textReplacementRules(left), .textReplacementRules(right)):
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                return (try? encoder.encode(left)) == (try? encoder.encode(right))
            default:
                return false
            }
        }
    }

    private struct Definition {
        let key: String
        let storage: Storage
        let read: () -> Value
        let apply: (Value) -> Void
    }

    private static let localMetadataKey = "FastScrobbler.ICloudSync.settingsMetadata"

    private static let definitions: [Definition] = [
        Definition(
            key: AppSettings.Keys.scrobbleAppleMusicAPIEnabled,
            storage: .appGroup,
            read: { .bool(AppSettings.scrobbleAppleMusicAPIEnabled()) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: AppSettings.Keys.scrobbleAppleMusicAPIEnabled) } }
        ),
        Definition(
            key: AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks,
            storage: .appGroup,
            read: { .bool(AppSettings.scrobbleOnlyNonLibraryAppleMusicAPITracks()) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks) } }
        ),
        Definition(
            key: AppSettings.Keys.extendedListeningHistoryScanEnabled,
            storage: .appGroup,
            read: { .bool(AppSettings.extendedListeningHistoryScanEnabled()) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: AppSettings.Keys.extendedListeningHistoryScanEnabled) } }
        ),
        Definition(
            key: AppSettings.Keys.listeningHistoryRequireConfirmationEnabled,
            storage: .appGroup,
            read: { .bool(AppSettings.listeningHistoryRequireConfirmationEnabled()) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: AppSettings.Keys.listeningHistoryRequireConfirmationEnabled) } }
        ),
        Definition(
            key: AppSettings.Keys.themeSelection,
            storage: .standard,
            read: { .string(UserDefaults.standard.string(forKey: AppSettings.Keys.themeSelection) ?? AppTheme.system.rawValue) },
            apply: {
                guard case .string(let value) = $0 else { return }
                if value == AppTheme.system.rawValue {
                    UserDefaults.standard.removeObject(forKey: AppSettings.Keys.themeSelection)
                } else {
                    UserDefaults.standard.set(value, forKey: AppSettings.Keys.themeSelection)
                }
            }
        ),
        Definition(
            key: AppSettings.Keys.buttonThemeSelection,
            storage: .standard,
            read: { .string(UserDefaults.standard.string(forKey: AppSettings.Keys.buttonThemeSelection) ?? ButtonTheme.colorful.rawValue) },
            apply: {
                guard case .string(let value) = $0 else { return }
                if value == ButtonTheme.colorful.rawValue {
                    UserDefaults.standard.removeObject(forKey: AppSettings.Keys.buttonThemeSelection)
                } else {
                    UserDefaults.standard.set(value, forKey: AppSettings.Keys.buttonThemeSelection)
                }
            }
        ),
        Definition(
            key: ProSettings.Keys.loveOnFavoriteEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.loveOnFavoriteEnabled) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.loveOnFavoriteEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.scrobbleThresholdIndex,
            storage: .appGroup,
            read: { .int(AppGroup.userDefaults.object(forKey: ProSettings.Keys.scrobbleThresholdIndex) as? Int ?? ProSettings.defaultScrobbleThresholdIndex) },
            apply: { if case .int(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.scrobbleThresholdIndex) } }
        ),
        Definition(
            key: ProSettings.Keys.useAlbumArtistForScrobbling,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.useAlbumArtistForScrobbling) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.useAlbumArtistForScrobbling) } }
        ),
        Definition(
            key: ProSettings.Keys.useFirstArtistOnlyForScrobbling,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.useFirstArtistOnlyForScrobbling) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.useFirstArtistOnlyForScrobbling) } }
        ),
        Definition(
            key: ProSettings.Keys.stripEpAndSingleSuffixFromAlbum,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.stripEpAndSingleSuffixFromAlbum) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.stripEpAndSingleSuffixFromAlbum) } }
        ),
        Definition(
            key: ProSettings.Keys.removeBracketsFromSongTitlesEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.removeBracketsFromSongTitlesEnabled) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.removeBracketsFromSongTitlesEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled) as? Bool ?? false) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.preventDuplicateScrobblesEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: ProSettings.Keys.preventDuplicateScrobblesEnabled) as? Bool ?? true) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: ProSettings.Keys.preventDuplicateScrobblesEnabled) } }
        ),
        Definition(
            key: AppSettings.Keys.sendNowPlayingAutomaticallyEnabled,
            storage: .appGroup,
            read: { .bool(AppGroup.userDefaults.object(forKey: AppSettings.Keys.sendNowPlayingAutomaticallyEnabled) as? Bool ?? true) },
            apply: { if case .bool(let value) = $0 { AppGroup.userDefaults.set(value, forKey: AppSettings.Keys.sendNowPlayingAutomaticallyEnabled) } }
        ),
        Definition(
            key: ProSettings.Keys.removeBracketsFromSongTitleKeywords,
            storage: .appGroup,
            read: { .stringArray(ProSettings.removeBracketsFromSongTitleKeywords()) },
            apply: { if case .stringArray(let value) = $0 { ProSettings.setRemoveBracketsFromSongTitleKeywords(value) } }
        ),
        Definition(
            key: ProSettings.Keys.removeBracketsFromAlbumTitleKeywords,
            storage: .appGroup,
            read: { .stringArray(ProSettings.removeBracketsFromAlbumTitleKeywords()) },
            apply: { if case .stringArray(let value) = $0 { ProSettings.setRemoveBracketsFromAlbumTitleKeywords(value) } }
        ),
        Definition(
            key: ProSettings.Keys.textReplacementRules,
            storage: .appGroup,
            read: { .textReplacementRules(ProSettings.textReplacementRules()) },
            apply: { if case .textReplacementRules(let value) = $0 { ProSettings.setTextReplacementRules(value) } }
        ),
        Definition(
            key: ProSettings.Keys.firstArtistOnlyIgnoredArtists,
            storage: .appGroup,
            read: { .stringArray(ProSettings.firstArtistOnlyIgnoredArtists()) },
            apply: { if case .stringArray(let value) = $0 { ProSettings.setFirstArtistOnlyIgnoredArtists(value) } }
        ),
    ]

    private static let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0) })

    static func captureLocalPayload(now: Date = Date()) -> Payload {
        let localMetadata = loadLocalMetadata()
        let isFirstCapture = localMetadata.entries.isEmpty
        var existingByKey = Dictionary(uniqueKeysWithValues: localMetadata.entries.map { ($0.key, $0) })

        for definition in definitions {
            let currentValue = definition.read()
            if let existing = existingByKey[definition.key], existing.value == currentValue {
                continue
            }

            existingByKey[definition.key] = Entry(
                key: definition.key,
                storage: definition.storage,
                value: currentValue,
                updatedAt: now
            )
        }

        let payload = Payload(entries: sortedEntries(Array(existingByKey.values)))
        saveLocalMetadata(payload)
        return payload
    }

    static func apply(_ payload: Payload) {
        for entry in payload.entries {
            definitionsByKey[entry.key]?.apply(entry.value)
        }
        saveLocalMetadata(payload)
    }

    static func merged(local: Payload, remote: Payload?) -> Payload {
        guard let remote else { return local }

        var mergedByKey = Dictionary(uniqueKeysWithValues: local.entries.map { ($0.key, $0) })
        for entry in remote.entries {
            if let existing = mergedByKey[entry.key] {
                if entry.updatedAt >= existing.updatedAt {
                    mergedByKey[entry.key] = entry
                }
            } else {
                mergedByKey[entry.key] = entry
            }
        }

        return Payload(entries: sortedEntries(Array(mergedByKey.values)))
    }

    private static func loadLocalMetadata() -> Payload {
        guard let data = AppGroup.userDefaults.data(forKey: localMetadataKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(entries: [])
        }
        return payload
    }

    private static func saveLocalMetadata(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        AppGroup.userDefaults.set(data, forKey: localMetadataKey)
    }

    private static func sortedEntries(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.key < $1.key }
    }
}

private struct SyncedBacklogPayload: Codable {
    var version: Int = 1
    var items: [ScrobbleBacklog.Item]
}

private struct SyncedScrobbleLogPayload: Codable {
    var version: Int = 1
    var entries: [ScrobbleLogStore.Entry]
}

private struct SyncedImporterStatePayload: Codable {
    var version: Int = 1
    var playbackHistory: PlaybackHistoryImporter.SyncState
}

@MainActor
final class ICloudSyncCoordinator: NSObject, ObservableObject {
    enum SyncError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return NSLocalizedString("iCloud is unavailable on this device.", comment: "")
            }
        }
    }

    static let shared = ICloudSyncCoordinator()

    private enum FileName {
        static let settings = "settings.json"
        static let backlog = "scrobble_backlog.json"
        static let scrobbleLog = "scrobble_log.json"
        static let importerState = "import_state.json"

        static let all = [settings, backlog, scrobbleLog, importerState]
    }

    @Published private(set) var isSyncEnabled = AppSettings.iCloudSyncEnabled()
    @Published private(set) var isICloudAvailable = false
    @Published private(set) var hasCloudData = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastErrorMessage: String?

    private let logger = Logger(subsystem: "FastScrobbler", category: "ICloudSync")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private var hasStarted = false
    private var isApplyingCloudState = false
    private var metadataQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var localPushTask: Task<Void, Never>?
    private var cloudPullTask: Task<Void, Never>?
    private var lastWrittenDataByFile: [String: Data] = [:]

    func startIfNeeded() async {
        await refreshStatus()
        guard isSyncEnabled else { return }

        do {
            try await startSyncInfrastructureIfNeeded(reason: "startup")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshStatus() async {
        isSyncEnabled = AppSettings.iCloudSyncEnabled()
        isICloudAvailable = syncDirectoryURL() != nil
        hasCloudData = cloudDataExists()
    }

    func enableSync() async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        lastErrorMessage = nil
        statusMessage = nil
        await refreshStatus()

        guard isICloudAvailable else {
            throw SyncError.unavailable
        }

        AppSettings.setICloudSyncEnabled(true)
        isSyncEnabled = true

        do {
            try await startSyncInfrastructureIfNeeded(reason: "enable")
            await refreshStatus()
        } catch {
            AppSettings.setICloudSyncEnabled(false)
            isSyncEnabled = false
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func disableSync() async {
        AppSettings.setICloudSyncEnabled(false)
        isSyncEnabled = false
        lastErrorMessage = nil
        statusMessage = nil

        await writePayload(
            SyncedSettingsStore.captureLocalPayload(),
            fileName: FileName.settings,
            reason: "disable"
        )

        stopSyncInfrastructure()
        hasCloudData = cloudDataExists()
    }

    func deleteCloudData() async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        lastErrorMessage = nil
        statusMessage = nil

        AppSettings.setICloudSyncEnabled(false)
        isSyncEnabled = false
        stopSyncInfrastructure()

        guard let directoryURL = syncDirectoryURL() else {
            await refreshStatus()
            throw SyncError.unavailable
        }

        do {
            for fileName in FileName.all {
                let fileURL = directoryURL.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                lastWrittenDataByFile.removeValue(forKey: fileName)
            }

            let remainingFiles = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
            if remainingFiles.isEmpty, FileManager.default.fileExists(atPath: directoryURL.path) {
                try? FileManager.default.removeItem(at: directoryURL)
            }

            await refreshStatus()
            statusMessage = NSLocalizedString("iCloud data deleted. Sync remains off on this device.", comment: "")
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func startSyncInfrastructureIfNeeded(reason: String) async throws {
        guard syncDirectoryURL() != nil else {
            throw SyncError.unavailable
        }

        if !hasStarted {
            registerLocalObservers()
            startMetadataQuery()
            hasStarted = true
        }

        await pullMergeAndPersist(reason: reason)
        await refreshStatus()
    }

    private func stopSyncInfrastructure() {
        localPushTask?.cancel()
        localPushTask = nil
        cloudPullTask?.cancel()
        cloudPullTask = nil

        metadataQuery?.stop()
        metadataQuery = nil

        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        hasStarted = false
    }

    private func registerLocalObservers() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: UserDefaults.didChangeNotification, object: AppGroup.userDefaults, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isApplyingCloudState else { return }
                    self.schedulePush()
                }
            }
        )

        observers.append(
            center.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isApplyingCloudState else { return }
                    self.schedulePush()
                }
            }
        )

        observers.append(
            center.addObserver(forName: ICloudSyncLocalChangeNotifier.name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isApplyingCloudState else { return }
                    self.schedulePush()
                }
            }
        )
    }

    private func startMetadataQuery() {
        guard metadataQuery == nil, let directoryURL = syncDirectoryURL() else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, directoryURL.path)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.schedulePull()
                }
            }
        )
        observers.append(
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.schedulePull()
                }
            }
        )

        metadataQuery = query
        query.start()
    }

    private func schedulePush() {
        guard isSyncEnabled else { return }
        guard !isApplyingCloudState else { return }
        guard syncDirectoryURL() != nil else { return }

        localPushTask?.cancel()
        localPushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushLocalState(reason: "local change")
        }
    }

    private func schedulePull() {
        guard isSyncEnabled else { return }
        guard syncDirectoryURL() != nil else { return }

        cloudPullTask?.cancel()
        cloudPullTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            await self?.pullMergeAndPersist(reason: "cloud update")
        }
    }

    private func pushLocalState(reason: String) async {
        guard isSyncEnabled else { return }

        let settings = SyncedSettingsStore.captureLocalPayload()
        let backlogItems = await ScrobbleBacklog.shared.syncedItemsSnapshot()
        let scrobbleLogEntries = ScrobbleLogStore.shared.syncedEntriesSnapshot()
        let playbackHistoryState = PlaybackHistoryImporter.shared.exportSyncState()

        await writePayload(settings, fileName: FileName.settings, reason: reason)
        await writePayload(SyncedBacklogPayload(items: backlogItems), fileName: FileName.backlog, reason: reason)
        await writePayload(SyncedScrobbleLogPayload(entries: scrobbleLogEntries), fileName: FileName.scrobbleLog, reason: reason)
        await writePayload(
            SyncedImporterStatePayload(playbackHistory: playbackHistoryState),
            fileName: FileName.importerState,
            reason: reason
        )
        hasCloudData = cloudDataExists()
    }

    private func pullMergeAndPersist(reason: String) async {
        guard isSyncEnabled else { return }

        let localSettings = SyncedSettingsStore.captureLocalPayload()
        let localBacklog = await ScrobbleBacklog.shared.syncedItemsSnapshot()
        let localScrobbleLog = ScrobbleLogStore.shared.syncedEntriesSnapshot()
        let localPlaybackHistoryState = PlaybackHistoryImporter.shared.exportSyncState()

        let cloudSettings: SyncedSettingsStore.Payload? = readPayload(fileName: FileName.settings)
        let cloudBacklog: SyncedBacklogPayload? = readPayload(fileName: FileName.backlog)
        let cloudScrobbleLog: SyncedScrobbleLogPayload? = readPayload(fileName: FileName.scrobbleLog)
        let cloudImporterState: SyncedImporterStatePayload? = readPayload(fileName: FileName.importerState)

        let mergedSettings = SyncedSettingsStore.merged(local: localSettings, remote: cloudSettings)
        let mergedBacklogItems = ScrobbleBacklog.mergedSyncedItems(local: localBacklog, remote: cloudBacklog?.items ?? [])
        let mergedScrobbleLogEntries = ScrobbleLogStore.mergedSyncedEntries(local: localScrobbleLog, remote: cloudScrobbleLog?.entries ?? [])
        let mergedPlaybackHistoryState = mergePlaybackHistoryState(local: localPlaybackHistoryState, remote: cloudImporterState?.playbackHistory)

        isApplyingCloudState = true
        SyncedSettingsStore.apply(mergedSettings)
        await ScrobbleBacklog.shared.replaceItemsForSync(mergedBacklogItems)
        ScrobbleLogStore.shared.replaceEntriesForSync(mergedScrobbleLogEntries)
        PlaybackHistoryImporter.shared.mergeSyncState(mergedPlaybackHistoryState)
        isApplyingCloudState = false

        logger.info("applied merged iCloud state (\(reason, privacy: .public))")

        await writePayload(mergedSettings, fileName: FileName.settings, reason: reason)
        await writePayload(SyncedBacklogPayload(items: mergedBacklogItems), fileName: FileName.backlog, reason: reason)
        await writePayload(SyncedScrobbleLogPayload(entries: mergedScrobbleLogEntries), fileName: FileName.scrobbleLog, reason: reason)
        await writePayload(
            SyncedImporterStatePayload(playbackHistory: mergedPlaybackHistoryState),
            fileName: FileName.importerState,
            reason: reason
        )
        hasCloudData = cloudDataExists()
    }

    private func mergePlaybackHistoryState(
        local: PlaybackHistoryImporter.SyncState,
        remote: PlaybackHistoryImporter.SyncState?
    ) -> PlaybackHistoryImporter.SyncState {
        guard let remote else { return local }

        var merged = local
        merged.lastImportAt = maxOptionalDate(local.lastImportAt, remote.lastImportAt)
        for (trackID, count) in remote.playCountByTrackID {
            merged.playCountByTrackID[trackID] = max(merged.playCountByTrackID[trackID] ?? 0, count)
        }
        for (trackID, date) in remote.lastSeenPlayedAtByTrackID {
            merged.lastSeenPlayedAtByTrackID[trackID] = maxOptionalDate(merged.lastSeenPlayedAtByTrackID[trackID], date)
        }
        return merged
    }

    private func readPayload<T: Decodable>(fileName: String) -> T? {
        guard let directoryURL = syncDirectoryURL() else { return nil }
        let fileURL = directoryURL.appendingPathComponent(fileName)
        let placeholderURL = directoryURL.appendingPathComponent("." + fileName + ".icloud")

        if !FileManager.default.fileExists(atPath: fileURL.path) && FileManager.default.fileExists(atPath: placeholderURL.path) {
            logger.info("iCloud payload \(fileName, privacy: .public) is not downloaded locally; triggering download.")
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.warning("failed to decode iCloud payload \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writePayload<T: Encodable>(_ payload: T, fileName: String, reason: String) async {
        guard let directoryURL = syncDirectoryURL() else { return }

        do {
            let data = try encoder.encode(payload)
            let fileURL = directoryURL.appendingPathComponent(fileName)
            let existingData = lastWrittenDataByFile[fileName] ?? (try? Data(contentsOf: fileURL))
            guard existingData != data else { return }

            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            lastWrittenDataByFile[fileName] = data
            logger.debug("wrote iCloud payload \(fileName, privacy: .public) (\(reason, privacy: .public))")
        } catch {
            logger.warning("failed to write iCloud payload \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncDirectoryURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: ICloudSyncContainer.identifier)?
            .appendingPathComponent(ICloudSyncContainer.relativeDirectory, isDirectory: true)
    }

    private func cloudDataExists() -> Bool {
        guard let directoryURL = syncDirectoryURL() else { return false }

        for fileName in FileName.all {
            let fileURL = directoryURL.appendingPathComponent(fileName)
            let placeholderURL = directoryURL.appendingPathComponent("." + fileName + ".icloud")
            if FileManager.default.fileExists(atPath: fileURL.path) || FileManager.default.fileExists(atPath: placeholderURL.path) {
                return true
            }
        }

        return false
    }

    private func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return max(left, right)
        case (.some, .none):
            return lhs
        case (.none, .some):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func minOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return min(left, right)
        case (.some, .none):
            return lhs
        case (.none, .some):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    private func maxOptionalInt(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return max(left, right)
        case (.some, .none):
            return lhs
        case (.none, .some):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}
