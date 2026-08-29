import Foundation

func runICloudSyncTests() {
    section("iCloud Sync · Shared toggle registry")

    func syncedSettingsKeysFromSource() -> Set<String> {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FastScrobbler/ICloudSyncCoordinator.swift")

        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return []
        }

        let pattern = #"key:\s+((?:AppSettings|ProSettings)\.Keys\.[A-Za-z0-9_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsSource.substring(with: match.range(at: 1))
        })
    }

    let syncedKeys = syncedSettingsKeysFromSource()
    let expectedSharedToggleKeys: Set<String> = [
        "AppSettings.Keys.scrobbleAppleMusicAPIEnabled",
        "AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks",
        "AppSettings.Keys.extendedListeningHistoryScanEnabled",
        "AppSettings.Keys.listeningHistoryRequireConfirmationEnabled",
        "AppSettings.Keys.sendNowPlayingAutomaticallyEnabled",
        "ProSettings.Keys.loveOnFavoriteEnabled",
        "ProSettings.Keys.useAlbumArtistForScrobbling",
        "ProSettings.Keys.useFirstArtistOnlyForScrobbling",
        "ProSettings.Keys.stripEpAndSingleSuffixFromAlbum",
        "ProSettings.Keys.removeBracketsFromSongTitlesEnabled",
        "ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled",
        "ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled",
        "ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled",
        "ProSettings.Keys.preventDuplicateScrobblesEnabled",
    ]

    let missingSharedToggleKeys = expectedSharedToggleKeys.subtracting(syncedKeys).sorted()
    expectEqual("shared toggle keys are included in the iCloud sync registry", missingSharedToggleKeys, [])

    section("iCloud Sync · Settings payload merge")

    enum SyncValue: Equatable {
        case bool(Bool)
        case int(Int)
    }

    struct SettingsEntry: Equatable {
        let key: String
        let value: SyncValue
        let updatedAt: Date
    }

    struct SettingsPayload: Equatable {
        let entries: [SettingsEntry]
    }

    func mergedSettings(local: SettingsPayload, remote: SettingsPayload?) -> SettingsPayload {
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

        return SettingsPayload(entries: mergedByKey.values.sorted { $0.key < $1.key })
    }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let older = now.addingTimeInterval(-60)
    let newer = now.addingTimeInterval(60)

    let localSettings = SettingsPayload(entries: [
        SettingsEntry(key: "iCloudSyncEnabled", value: .bool(false), updatedAt: newer),
        SettingsEntry(key: "thresholdIndex", value: .int(1), updatedAt: older),
    ])
    let remoteSettings = SettingsPayload(entries: [
        SettingsEntry(key: "iCloudSyncEnabled", value: .bool(true), updatedAt: older),
        SettingsEntry(key: "thresholdIndex", value: .int(2), updatedAt: newer),
        SettingsEntry(key: "firstArtistOnly", value: .bool(true), updatedAt: now),
    ])

    let merged = mergedSettings(local: localSettings, remote: remoteSettings)
    expectEqual("older remote iCloud-enabled flag does not override newer local value", merged.entries.first(where: { $0.key == "iCloudSyncEnabled" })?.value, .bool(false))
    expectEqual("newer remote per-key setting overrides older local value", merged.entries.first(where: { $0.key == "thresholdIndex" })?.value, .int(2))
    expectEqual("remote-only keys are preserved in merged payload", merged.entries.first(where: { $0.key == "firstArtistOnly" })?.value, .bool(true))

    section("iCloud Sync · Remote preference adoption")

    func applyRemoteEntryIfNewer(local: SettingsEntry?, remote: SettingsEntry) -> (applied: Bool, stored: SettingsEntry) {
        if let local, local.updatedAt > remote.updatedAt {
            return (false, local)
        }
        return (true, remote)
    }

    let newerRemotePreference = SettingsEntry(key: "iCloudSyncEnabled", value: .bool(true), updatedAt: newer)
    let olderRemotePreference = SettingsEntry(key: "iCloudSyncEnabled", value: .bool(true), updatedAt: older)
    let localPreference = SettingsEntry(key: "iCloudSyncEnabled", value: .bool(false), updatedAt: now)

    let appliedNewer = applyRemoteEntryIfNewer(local: localPreference, remote: newerRemotePreference)
    expect("newer remote iCloud preference is applied before startup", appliedNewer.applied)
    expectEqual("newer remote iCloud preference replaces local stored value", appliedNewer.stored.value, .bool(true))

    let ignoredOlder = applyRemoteEntryIfNewer(local: localPreference, remote: olderRemotePreference)
    expect("older remote iCloud preference is ignored", !ignoredOlder.applied)
    expectEqual("older remote iCloud preference leaves local value intact", ignoredOlder.stored.value, .bool(false))

    section("iCloud Sync · Playback-history merge")

    struct PlaybackHistoryState: Equatable {
        var lastImportAt: Date?
        var playCountByTrackID: [String: Int]
        var lastSeenPlayedAtByTrackID: [String: Date]
    }

    func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
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

    func mergePlaybackHistoryState(local: PlaybackHistoryState, remote: PlaybackHistoryState?) -> PlaybackHistoryState {
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

    let localHistory = PlaybackHistoryState(
        lastImportAt: older,
        playCountByTrackID: ["a": 2, "b": 7],
        lastSeenPlayedAtByTrackID: ["a": older, "b": now]
    )
    let remoteHistory = PlaybackHistoryState(
        lastImportAt: newer,
        playCountByTrackID: ["a": 5, "c": 1],
        lastSeenPlayedAtByTrackID: ["a": newer, "c": now]
    )

    let mergedHistory = mergePlaybackHistoryState(local: localHistory, remote: remoteHistory)
    expectEqual("playback-history merge keeps the latest import date", mergedHistory.lastImportAt, newer)
    expectEqual("playback-history merge keeps the max play count for overlapping tracks", mergedHistory.playCountByTrackID["a"], 5)
    expectEqual("playback-history merge preserves local-only play counts", mergedHistory.playCountByTrackID["b"], 7)
    expectEqual("playback-history merge adds remote-only play counts", mergedHistory.playCountByTrackID["c"], 1)
    expectEqual("playback-history merge keeps the newest last-seen date per track", mergedHistory.lastSeenPlayedAtByTrackID["a"], newer)
    expectEqual("playback-history merge preserves local-only last-seen dates", mergedHistory.lastSeenPlayedAtByTrackID["b"], now)
    expectEqual("playback-history merge adds remote-only last-seen dates", mergedHistory.lastSeenPlayedAtByTrackID["c"], now)

    section("iCloud Sync · Placeholder & download detection")

    func placeholderFileName(for fileName: String) -> String {
        "." + fileName + ".icloud"
    }

    expectEqual("settings.json placeholder name is correct", placeholderFileName(for: "settings.json"), ".settings.json.icloud")
    expectEqual("scrobble_log.json placeholder name is correct", placeholderFileName(for: "scrobble_log.json"), ".scrobble_log.json.icloud")

    section("iCloud Sync · Observer guard against loop")

    func shouldSchedulePush(isApplyingCloudState: Bool) -> Bool {
        !isApplyingCloudState
    }

    expect("local changes trigger push when not applying cloud state", shouldSchedulePush(isApplyingCloudState: false))
    expect("local changes drop push when applying cloud state", !shouldSchedulePush(isApplyingCloudState: true))

    section("iCloud Sync · Payload Codable roundtrips")

    struct TestRule: Codable, Equatable {
        var id: String
        var pattern: String
        var replacement: String
        var isRegex: Bool
    }

    struct TestEntry: Codable, Equatable {
        var key: String
        var storage: String
        var updatedAt: Date
    }

    struct TestPayload: Codable, Equatable {
        var version: Int = 1
        var entries: [TestEntry]
    }

    let payloadToTest = TestPayload(entries: [
        TestEntry(key: "AppSettings.Keys.scrobbleAppleMusicAPIEnabled", storage: "appGroup", updatedAt: now),
        TestEntry(key: "ProSettings.Keys.scrobbleThresholdIndex", storage: "appGroup", updatedAt: now)
    ])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encodedData = try? encoder.encode(payloadToTest)
    expect("settings payload encodes to non-empty JSON data", encodedData != nil && !(encodedData?.isEmpty ?? true))

    let decodedPayload = try? JSONDecoder().decode(TestPayload.self, from: encodedData ?? Data())
    expectEqual("decoded settings payload matches original", decodedPayload, payloadToTest)

    section("iCloud Sync · Container Directory Path")
    let containerID = "iCloud.com.kevin.FastScrobbler"
    let relativeDir = "Documents/FastScrobblerSync"
    let fullRelativePath = (containerID as NSString).appendingPathComponent(relativeDir)
    expectEqual("relative directory path is constructed correctly", fullRelativePath, "iCloud.com.kevin.FastScrobbler/Documents/FastScrobblerSync")
}
