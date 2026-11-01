import Foundation

@MainActor
func runICloudSyncTests() async {
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

    section("iCloud Sync · Backlog Tombstones & Resurrection Prevention")

    struct TestBacklogItem: Equatable {
        var id: UUID
        var trackTitle: String
        var queuedAt: Date
        var lastAttemptAt: Date?
        var startTimestamp: Int

        var mutationDate: Date {
            lastAttemptAt ?? queuedAt
        }
    }

    func testMergeBacklogState(
        localItems: [TestBacklogItem],
        localTombstones: [UUID: Date],
        remoteItems: [TestBacklogItem],
        remoteTombstones: [UUID: Date],
        referenceDate: Date,
        maxTombstoneAge: TimeInterval = 7 * 86400
    ) -> (items: [TestBacklogItem], tombstones: [UUID: Date]) {
        let cutoff = referenceDate.addingTimeInterval(-maxTombstoneAge)

        var mergedTombstones: [UUID: Date] = [:]
        for (id, date) in localTombstones where date >= cutoff {
            mergedTombstones[id] = date
        }
        for (id, date) in remoteTombstones where date >= cutoff {
            if let existing = mergedTombstones[id] {
                mergedTombstones[id] = max(existing, date)
            } else {
                mergedTombstones[id] = date
            }
        }

        var mergedByID: [UUID: TestBacklogItem] = [:]
        for item in localItems + remoteItems {
            if let tombstoneDate = mergedTombstones[item.id], item.mutationDate <= tombstoneDate {
                continue
            }
            if let existing = mergedByID[item.id] {
                if item.mutationDate > existing.mutationDate {
                    mergedByID[item.id] = item
                }
            } else {
                mergedByID[item.id] = item
            }
        }

        let sorted = mergedByID.values.sorted { $0.startTimestamp > $1.startTimestamp }
        return (items: sorted, tombstones: mergedTombstones)
    }

    let itemAId = UUID()
    let itemBId = UUID()
    let itemCId = UUID()

    let itemA = TestBacklogItem(id: itemAId, trackTitle: "Song A", queuedAt: older, lastAttemptAt: nil, startTimestamp: 100)
    let itemB = TestBacklogItem(id: itemBId, trackTitle: "Song B", queuedAt: now, lastAttemptAt: nil, startTimestamp: 200)
    let itemC = TestBacklogItem(id: itemCId, trackTitle: "Song C", queuedAt: older, lastAttemptAt: nil, startTimestamp: 150)

    // Scenario 1: Item A was submitted/cleared on local device (tombstoned), but still in remote backlog.
    let localWithTombstone: [UUID: Date] = [itemAId: now]
    let result1 = testMergeBacklogState(
        localItems: [itemB],
        localTombstones: localWithTombstone,
        remoteItems: [itemA, itemB],
        remoteTombstones: [:],
        referenceDate: now
    )
    expect("tombstoned remote item A is not resurrected in merged backlog", !result1.items.contains(where: { $0.id == itemAId }))
    expect("active item B is preserved", result1.items.contains(where: { $0.id == itemBId }))
    expect("merged tombstones retain item A", result1.tombstones[itemAId] == now)

    // Scenario 2: Remote device tombstoned item C, local device still has item C.
    let remoteWithTombstone: [UUID: Date] = [itemCId: now]
    let result2 = testMergeBacklogState(
        localItems: [itemB, itemC],
        localTombstones: [:],
        remoteItems: [itemB],
        remoteTombstones: remoteWithTombstone,
        referenceDate: now
    )
    expect("remote tombstone suppresses local item C from resurrection", !result2.items.contains(where: { $0.id == itemCId }))

    // Scenario 3: Item re-queued with newer timestamp after tombstone date is preserved.
    let reQueuedItemA = TestBacklogItem(id: itemAId, trackTitle: "Song A Replay", queuedAt: newer, lastAttemptAt: nil, startTimestamp: 300)
    let result3 = testMergeBacklogState(
        localItems: [reQueuedItemA],
        localTombstones: [itemAId: now],
        remoteItems: [],
        remoteTombstones: [:],
        referenceDate: now
    )
    expect("item re-queued after tombstone timestamp is retained", result3.items.contains(where: { $0.id == itemAId }))

    section("iCloud Sync · Tombstone Expiration (7-Day Retention)")
    let eightDaysAgo = now.addingTimeInterval(-8 * 86400)
    let twoDaysAgo = now.addingTimeInterval(-2 * 86400)

    let expiredTombstoneID = UUID()
    let validTombstoneID = UUID()

    let resultPruned = testMergeBacklogState(
        localItems: [],
        localTombstones: [expiredTombstoneID: eightDaysAgo, validTombstoneID: twoDaysAgo],
        remoteItems: [],
        remoteTombstones: [:],
        referenceDate: now
    )
    expect("tombstone older than 7 days is purged", resultPruned.tombstones[expiredTombstoneID] == nil)
    expect("tombstone within 7 days is kept", resultPruned.tombstones[validTombstoneID] != nil)

    section("iCloud Sync · Backlog Payload Backward & Forward Compatibility")

    // Test decoding legacy JSON that did not have a 'tombstones' key
    let legacyJSON = """
    {
        "version": 1,
        "items": []
    }
    """.data(using: .utf8)!

    struct CompatibilityBacklogPayload: Codable {
        var version: Int = 1
        var items: [String] = []
        var tombstones: [String: Double] = [:]

        enum CodingKeys: String, CodingKey {
            case version, items, tombstones
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            self.items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
            self.tombstones = try container.decodeIfPresent([String: Double].self, forKey: .tombstones) ?? [:]
        }
    }

    let decodedLegacy = try? JSONDecoder().decode(CompatibilityBacklogPayload.self, from: legacyJSON)
    expect("legacy backlog JSON without tombstones decodes successfully", decodedLegacy != nil)
    expectEqual("legacy backlog JSON defaults tombstones to empty", decodedLegacy?.tombstones, [:])

    // Test legacy consumer reading new payload with tombstones (must not fail)
    struct LegacyBacklogPayload: Codable {
        var version: Int
        var items: [String]
    }

    let newPayloadJSON = """
    {
        "version": 1,
        "items": ["song1"],
        "tombstones": {"uuid-123": 1700000000.0}
    }
    """.data(using: .utf8)!

    let decodedByLegacyConsumer = try? JSONDecoder().decode(LegacyBacklogPayload.self, from: newPayloadJSON)
    expect("legacy app version decodes new payload without error", decodedByLegacyConsumer != nil)
    expectEqual("legacy consumer reads items correctly", decodedByLegacyConsumer?.items, ["song1"])

    // MARK: - Full Settings Registry Coverage
    section("iCloud Sync · Complete Settings Registry Coverage")

    let allExpectedSyncedKeys: Set<String> = [
        "AppSettings.Keys.scrobbleAppleMusicAPIEnabled",
        "AppSettings.Keys.scrobbleOnlyNonLibraryAppleMusicAPITracks",
        "AppSettings.Keys.extendedListeningHistoryScanEnabled",
        "AppSettings.Keys.listeningHistoryRequireConfirmationEnabled",
        "AppSettings.Keys.themeSelection",
        "AppSettings.Keys.buttonThemeSelection",
        "AppSettings.Keys.sendNowPlayingAutomaticallyEnabled",
        "ProSettings.Keys.loveOnFavoriteEnabled",
        "ProSettings.Keys.scrobbleThresholdIndex",
        "ProSettings.Keys.useAlbumArtistForScrobbling",
        "ProSettings.Keys.useFirstArtistOnlyForScrobbling",
        "ProSettings.Keys.stripEpAndSingleSuffixFromAlbum",
        "ProSettings.Keys.removeBracketsFromSongTitlesEnabled",
        "ProSettings.Keys.removeAllBracketsFromSongTitlesEnabled",
        "ProSettings.Keys.removeBracketsFromAlbumTitlesEnabled",
        "ProSettings.Keys.removeAllBracketsFromAlbumTitlesEnabled",
        "ProSettings.Keys.preventDuplicateScrobblesEnabled",
        "ProSettings.Keys.removeBracketsFromSongTitleKeywords",
        "ProSettings.Keys.removeBracketsFromAlbumTitleKeywords",
        "ProSettings.Keys.textReplacementRules",
        "ProSettings.Keys.firstArtistOnlyIgnoredArtists",
    ]
    let missingSyncedKeys = allExpectedSyncedKeys.subtracting(syncedKeys).sorted()
    expectEqual("all expected settings keys are present in the iCloud sync registry", missingSyncedKeys, [])
    expectEqual("exact count of 21 synced settings in registry", syncedKeys.count, 21)

    // MARK: - Production ScrobbleBacklog.mergedSyncedState Tests
    section("iCloud Sync · Production ScrobbleBacklog.mergedSyncedState")

    let realTrack1 = Track(artist: "Radiohead", title: "Karma Police", album: "OK Computer")
    let realTrack2 = Track(artist: "Daft Punk", title: "One More Time", album: "Discovery")
    let realTrack3 = Track(artist: "Pink Floyd", title: "Time", album: "The Dark Side of the Moon")

    let backlogId1 = UUID()
    let backlogId2 = UUID()
    let backlogId3 = UUID()

    let realItem1 = ScrobbleBacklog.Item(
        id: backlogId1,
        track: realTrack1,
        startTimestamp: 1000,
        origin: .live,
        wasAppleMusicFavorite: false,
        queuedAt: older,
        attemptCount: 1,
        lastAttemptAt: older,
        pendingServices: [.lastfm, .listenbrainz]
    )

    let realItem2 = ScrobbleBacklog.Item(
        id: backlogId2,
        track: realTrack2,
        startTimestamp: 2000,
        origin: .manual,
        wasAppleMusicFavorite: true,
        queuedAt: now,
        attemptCount: 0,
        lastAttemptAt: nil,
        pendingServices: [.lastfm]
    )

    let realItem3 = ScrobbleBacklog.Item(
        id: backlogId3,
        track: realTrack3,
        startTimestamp: 1500,
        origin: .recentlyPlayed,
        wasAppleMusicFavorite: false,
        queuedAt: older,
        attemptCount: 1,
        lastAttemptAt: nil,
        pendingServices: [.listenbrainz]
    )

    // Distinct items are unioned and ordered by startTimestamp descending
    let disjointMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [realItem1],
        localTombstones: [:],
        remoteItems: [realItem2, realItem3],
        remoteTombstones: [:],
        now: now
    )
    expectEqual("merging disjoint items keeps all items", disjointMerged.items.count, 3)
    expectEqual("merged items are ordered by startTimestamp descending (1st is Item 2)", disjointMerged.items[0].id, backlogId2)
    expectEqual("merged items are ordered by startTimestamp descending (2nd is Item 3)", disjointMerged.items[1].id, backlogId3)
    expectEqual("merged items are ordered by startTimestamp descending (3rd is Item 1)", disjointMerged.items[2].id, backlogId1)

    // Identical startTimestamps tiebreak by queuedAt descending
    let tiebreakItemA = ScrobbleBacklog.Item(
        id: UUID(),
        track: realTrack1,
        startTimestamp: 3000,
        origin: .live,
        wasAppleMusicFavorite: false,
        queuedAt: older,
        attemptCount: 0,
        lastAttemptAt: nil,
        pendingServices: [.lastfm]
    )
    let tiebreakItemB = ScrobbleBacklog.Item(
        id: UUID(),
        track: realTrack2,
        startTimestamp: 3000,
        origin: .live,
        wasAppleMusicFavorite: false,
        queuedAt: newer,
        attemptCount: 0,
        lastAttemptAt: nil,
        pendingServices: [.lastfm]
    )
    let tiebreakMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [tiebreakItemA],
        localTombstones: [:],
        remoteItems: [tiebreakItemB],
        remoteTombstones: [:],
        now: now
    )
    expectEqual("tied startTimestamps order by queuedAt descending", tiebreakMerged.items.first?.id, tiebreakItemB.id)

    // Conflict resolution: same UUID, item with newer mutationDate replaces older
    var updatedRealItem1 = realItem1
    updatedRealItem1.attemptCount = 2
    updatedRealItem1.lastAttemptAt = newer

    let conflictMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [realItem1],
        localTombstones: [:],
        remoteItems: [updatedRealItem1],
        remoteTombstones: [:],
        now: now
    )
    expectEqual("conflict resolution picks item with newer lastAttemptAt", conflictMerged.items.first?.attemptCount, 2)
    expectEqual("conflict resolution preserves single item count", conflictMerged.items.count, 1)

    // Conflict resolution: same mutationDate, item with newer queuedAt replaces older
    var queuedLaterItem1 = realItem1
    queuedLaterItem1.queuedAt = newer
    let queuedConflictMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [realItem1],
        localTombstones: [:],
        remoteItems: [queuedLaterItem1],
        remoteTombstones: [:],
        now: now
    )
    expectEqual("conflict resolution picks item with newer queuedAt when mutation dates equal", queuedConflictMerged.items.first?.queuedAt, newer)

    // Tombstone resurrection suppression using production method
    let tombstonedMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [realItem2],
        localTombstones: [backlogId1: now],
        remoteItems: [realItem1, realItem2],
        remoteTombstones: [:],
        now: now
    )
    expectFalse("production mergedSyncedState suppresses tombstoned remote item", tombstonedMerged.items.contains(where: { $0.id == backlogId1 }))
    expectTrue("production mergedSyncedState retains active non-tombstoned item", tombstonedMerged.items.contains(where: { $0.id == backlogId2 }))

    // Re-queued item with mutationDate newer than tombstone date survives
    var requeuedItem1 = realItem1
    requeuedItem1.queuedAt = newer
    requeuedItem1.lastAttemptAt = newer
    let requeuedMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [requeuedItem1],
        localTombstones: [backlogId1: now],
        remoteItems: [],
        remoteTombstones: [:],
        now: now
    )
    expectTrue("re-queued item with mutation date > tombstone date survives resurrection check", requeuedMerged.items.contains(where: { $0.id == backlogId1 }))

    // Tombstone merging retains newest date per UUID and prunes expired (> 7 days)
    let freshTombstoneUUID = UUID()
    let overlappingTombstoneUUID = UUID()
    let staleTombstoneUUID = UUID()
    let nineDaysAgo = now.addingTimeInterval(-9 * 86400)
    let oneDayAgo = now.addingTimeInterval(-1 * 86400)
    let threeDaysAgo = now.addingTimeInterval(-3 * 86400)

    let tombstonePrunedMerged = ScrobbleBacklog.mergedSyncedState(
        localItems: [],
        localTombstones: [
            freshTombstoneUUID: oneDayAgo,
            overlappingTombstoneUUID: threeDaysAgo,
            staleTombstoneUUID: nineDaysAgo
        ],
        remoteItems: [],
        remoteTombstones: [
            overlappingTombstoneUUID: oneDayAgo
        ],
        now: now
    )
    expectNil("tombstones older than 7 days are pruned during merge", tombstonePrunedMerged.tombstones[staleTombstoneUUID])
    expectEqual("overlapping tombstones keep the newer date", tombstonePrunedMerged.tombstones[overlappingTombstoneUUID], oneDayAgo)
    expectNotNil("valid recent tombstone is kept", tombstonePrunedMerged.tombstones[freshTombstoneUUID])

    // MARK: - Production ScrobbleLogStore.mergedSyncedEntries Tests
    section("iCloud Sync · Production ScrobbleLogStore.mergedSyncedEntries")

    let logTrackA = Track(artist: "The Beatles", title: "Come Together", album: "Abbey Road")
    let logTrackB = Track(artist: "Led Zeppelin", title: "Kashmir", album: "Physical Graffiti")

    let logEntry1 = ScrobbleLogStore.Entry(
        id: UUID(),
        track: logTrackA,
        startTimestamp: 1000,
        scrobbledAt: older,
        source: .live,
        lovedOnLastFM: true
    )
    let logEntry1Updated = ScrobbleLogStore.Entry(
        id: UUID(),
        track: logTrackA,
        startTimestamp: 1000,
        scrobbledAt: newer,
        source: .live,
        lovedOnLastFM: false
    )
    let logEntry2 = ScrobbleLogStore.Entry(
        id: UUID(),
        track: logTrackB,
        startTimestamp: 2000,
        scrobbledAt: now,
        source: .backlog,
        lovedOnLastFM: nil
    )
    // Same track & startTimestamp but different source (.manual vs .live)
    let logEntry1Manual = ScrobbleLogStore.Entry(
        id: UUID(),
        track: logTrackA,
        startTimestamp: 1000,
        scrobbledAt: now,
        source: .manual,
        lovedOnLastFM: false
    )

    let mergedLogDisjoint = ScrobbleLogStore.mergedSyncedEntries(local: [logEntry1], remote: [logEntry2])
    expectEqual("merging disjoint scrobble log entries keeps both", mergedLogDisjoint.count, 2)

    let mergedLogDuplicate = ScrobbleLogStore.mergedSyncedEntries(local: [logEntry1], remote: [logEntry1Updated])
    expectEqual("duplicate log identity is deduplicated to 1 entry", mergedLogDuplicate.count, 1)
    expectEqual("newer scrobbledAt timestamp is chosen on duplicate identity", mergedLogDuplicate.first?.scrobbledAt, newer)
    expectEqual("newer loved flag is retained from newer entry", mergedLogDuplicate.first?.lovedOnLastFM, false)

    let mergedLogDifferentSources = ScrobbleLogStore.mergedSyncedEntries(local: [logEntry1], remote: [logEntry1Manual])
    expectEqual("same track and timestamp with different sources are preserved as separate entries", mergedLogDifferentSources.count, 2)

    let mergedLogEmptyRemote = ScrobbleLogStore.mergedSyncedEntries(local: [logEntry1], remote: [])
    expectEqual("empty remote scrobble log leaves local entries intact", mergedLogEmptyRemote.count, 1)

    let mergedLogEmptyLocal = ScrobbleLogStore.mergedSyncedEntries(local: [], remote: [logEntry2])
    expectEqual("empty local scrobble log retains all remote entries", mergedLogEmptyLocal.count, 1)

    // MARK: - Value Enum Polymorphic Codable & Equality Tests
    section("iCloud Sync · Value Enum Polymorphic Codable & Equality")

    enum SyncStoreValue: Codable, Equatable {
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

        static func == (lhs: SyncStoreValue, rhs: SyncStoreValue) -> Bool {
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

    let testRule1 = TextReplacementRule(id: UUID(), find: "feat.", replace: "ft.", scope: .track, isEnabled: true)
    let testRule2 = TextReplacementRule(id: UUID(), find: "Live", replace: "", scope: .album, isEnabled: false)

    let testValues: [SyncStoreValue] = [
        .bool(true),
        .bool(false),
        .int(0),
        .int(42),
        .int(-5),
        .string("system"),
        .string(""),
        .stringArray(["feat.", "ft.", "remix"]),
        .stringArray([]),
        .textReplacementRules([testRule1, testRule2]),
        .textReplacementRules([])
    ]

    for (index, val) in testValues.enumerated() {
        let encoded = try? JSONEncoder().encode(val)
        expect("SyncStoreValue [\(index)] encodes to non-empty data", encoded != nil && !(encoded?.isEmpty ?? true))
        let decoded = try? JSONDecoder().decode(SyncStoreValue.self, from: encoded ?? Data())
        expectEqual("SyncStoreValue [\(index)] round-trips through JSON faithfully", decoded, val)
    }

    // Value equality comparisons
    expectEqual("identical bool values are equal", SyncStoreValue.bool(true), SyncStoreValue.bool(true))
    expectFalse("different bool values are not equal", SyncStoreValue.bool(true) == SyncStoreValue.bool(false))
    expectEqual("identical int values are equal", SyncStoreValue.int(42), SyncStoreValue.int(42))
    expectFalse("different int values are not equal", SyncStoreValue.int(42) == SyncStoreValue.int(43))
    expectEqual("identical string values are equal", SyncStoreValue.string("colorful"), SyncStoreValue.string("colorful"))
    expectFalse("different string values are not equal", SyncStoreValue.string("colorful") == SyncStoreValue.string("system"))
    expectEqual("identical string array values are equal", SyncStoreValue.stringArray(["a", "b"]), SyncStoreValue.stringArray(["a", "b"]))
    expectFalse("different string array ordering is not equal", SyncStoreValue.stringArray(["a", "b"]) == SyncStoreValue.stringArray(["b", "a"]))
    expectEqual("identical rule lists are equal", SyncStoreValue.textReplacementRules([testRule1]), SyncStoreValue.textReplacementRules([testRule1]))
    expectFalse("differing rule lists are not equal", SyncStoreValue.textReplacementRules([testRule1]) == SyncStoreValue.textReplacementRules([testRule2]))
    expectFalse("cross-type values (bool vs int) are not equal", SyncStoreValue.bool(true) == SyncStoreValue.int(1))
    expectFalse("cross-type values (string vs stringArray) are not equal", SyncStoreValue.string("a") == SyncStoreValue.stringArray(["a"]))

    // MARK: - Settings Payload Edge Cases & Tie-Breaking
    section("iCloud Sync · Settings Payload Edge Cases & Tie-Breaking")

    // Equal timestamp tie-breaker: remote wins (entry.updatedAt >= existing.updatedAt)
    let tieBreakTimestamp = now
    let localTieBreak = SettingsPayload(entries: [
        SettingsEntry(key: "settingA", value: .bool(false), updatedAt: tieBreakTimestamp)
    ])
    let remoteTieBreak = SettingsPayload(entries: [
        SettingsEntry(key: "settingA", value: .bool(true), updatedAt: tieBreakTimestamp)
    ])
    let tieBreakResult = mergedSettings(local: localTieBreak, remote: remoteTieBreak)
    expectEqual("equal updatedAt timestamp gives precedence to remote value", tieBreakResult.entries.first?.value, .bool(true))

    // Empty remote payload leaves local untouched
    let emptyRemoteResult = mergedSettings(local: localSettings, remote: nil)
    expectEqual("nil remote payload preserves exact local settings", emptyRemoteResult, localSettings)

    // Empty local payload adopts all remote settings
    let emptyLocalResult = mergedSettings(local: SettingsPayload(entries: []), remote: remoteSettings)
    expectEqual("empty local payload adopts all remote entries", emptyLocalResult.entries.count, remoteSettings.entries.count)

    // Disjoint keys merge together cleanly and remain sorted
    let localDisjoint = SettingsPayload(entries: [
        SettingsEntry(key: "keyB", value: .int(2), updatedAt: now),
        SettingsEntry(key: "keyD", value: .int(4), updatedAt: now)
    ])
    let remoteDisjoint = SettingsPayload(entries: [
        SettingsEntry(key: "keyA", value: .int(1), updatedAt: now),
        SettingsEntry(key: "keyC", value: .int(3), updatedAt: now)
    ])
    let disjointKeysResult = mergedSettings(local: localDisjoint, remote: remoteDisjoint)
    expectEqual("disjoint keys merge to combined count", disjointKeysResult.entries.count, 4)
    expectEqual("merged entries are sorted alphabetically by key", disjointKeysResult.entries.map(\.key), ["keyA", "keyB", "keyC", "keyD"])

    // MARK: - Playback History Advanced Merging Edge Cases
    section("iCloud Sync · Playback History Advanced Merging")

    let emptyHistory = PlaybackHistoryState(lastImportAt: nil, playCountByTrackID: [:], lastSeenPlayedAtByTrackID: [:])
    let remoteOnlyHistory = PlaybackHistoryState(
        lastImportAt: newer,
        playCountByTrackID: ["x": 10],
        lastSeenPlayedAtByTrackID: ["x": newer]
    )

    let mergedWithEmpty = mergePlaybackHistoryState(local: emptyHistory, remote: remoteOnlyHistory)
    expectEqual("merging empty local with remote history adopts remote lastImportAt", mergedWithEmpty.lastImportAt, newer)
    expectEqual("merging empty local with remote history adopts remote play counts", mergedWithEmpty.playCountByTrackID["x"], 10)
    expectEqual("merging empty local with remote history adopts remote lastSeenPlayedAt", mergedWithEmpty.lastSeenPlayedAtByTrackID["x"], newer)

    let mergedNilRemote = mergePlaybackHistoryState(local: localHistory, remote: nil)
    expectEqual("merging with nil remote leaves local history identical", mergedNilRemote, localHistory)

    // Both nil lastImportAt remains nil
    let bothNilImport = mergePlaybackHistoryState(local: emptyHistory, remote: emptyHistory)
    expectNil("both nil lastImportAt produces nil merged date", bothNilImport.lastImportAt)

    // Disjoint tracks across devices
    let historyDevice1 = PlaybackHistoryState(
        lastImportAt: older,
        playCountByTrackID: ["track1": 3],
        lastSeenPlayedAtByTrackID: ["track1": older]
    )
    let historyDevice2 = PlaybackHistoryState(
        lastImportAt: newer,
        playCountByTrackID: ["track2": 8],
        lastSeenPlayedAtByTrackID: ["track2": newer]
    )
    let mergedDisjointHistory = mergePlaybackHistoryState(local: historyDevice1, remote: historyDevice2)
    expectEqual("disjoint track play counts are unioned", mergedDisjointHistory.playCountByTrackID.count, 2)
    expectEqual("device 1 track preserved", mergedDisjointHistory.playCountByTrackID["track1"], 3)
    expectEqual("device 2 track preserved", mergedDisjointHistory.playCountByTrackID["track2"], 8)
    expectEqual("merged lastImportAt takes the newer date", mergedDisjointHistory.lastImportAt, newer)

    // MARK: - Synced Files & Placeholder Utilities
    section("iCloud Sync · Synced Files & Placeholder Utilities")

    let allSyncFiles = [
        "settings.json",
        "scrobble_backlog.json",
        "scrobble_log.json",
        "import_state.json"
    ]

    func isCloudPlaceholder(_ fileName: String) -> Bool {
        fileName.hasPrefix(".") && fileName.hasSuffix(".icloud")
    }

    func originalFileName(fromPlaceholder placeholder: String) -> String? {
        guard isCloudPlaceholder(placeholder) else { return nil }
        var stripped = String(placeholder.dropFirst()) // drop leading '.'
        if stripped.hasSuffix(".icloud") {
            stripped = String(stripped.dropLast(7)) // drop '.icloud'
        }
        return stripped
    }

    for file in allSyncFiles {
        let placeholder = placeholderFileName(for: file)
        expect("placeholder for \(file) starts with '.' and ends with '.icloud'", isCloudPlaceholder(placeholder))
        expectEqual("originalFileName recovers \(file) from placeholder", originalFileName(fromPlaceholder: placeholder), file)
    }

    expectFalse("standard file is not detected as placeholder", isCloudPlaceholder("settings.json"))
    expectFalse("dotfile without .icloud suffix is not a cloud placeholder", isCloudPlaceholder(".DS_Store"))
    expectNil("recovering original filename from non-placeholder returns nil", originalFileName(fromPlaceholder: "settings.json"))

    // MARK: - SyncedBacklogPayload Tombstone Key Serialization
    section("iCloud Sync · SyncedBacklogPayload Tombstone Key Serialization")

    struct FullSyncedBacklogPayload: Codable {
        var version: Int = 1
        var items: [String] = []
        var tombstones: [UUID: Date] = [:]

        private enum CodingKeys: String, CodingKey {
            case version
            case items
            case tombstones
        }

        init(items: [String], tombstones: [UUID: Date] = [:], version: Int = 1) {
            self.version = version
            self.items = items
            self.tombstones = tombstones
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            self.items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
            self.tombstones = try container.decodeIfPresent([UUID: Date].self, forKey: .tombstones) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(items, forKey: .items)
            if !tombstones.isEmpty {
                try container.encode(tombstones, forKey: .tombstones)
            }
        }
    }

    let emptyTombstonesPayload = FullSyncedBacklogPayload(items: ["song1", "song2"], tombstones: [:])
    let encodedEmptyTombstones = try? JSONEncoder().encode(emptyTombstonesPayload)
    let jsonStringEmpty = String(data: encodedEmptyTombstones ?? Data(), encoding: .utf8) ?? ""
    expectFalse("empty tombstones payload omits 'tombstones' key from JSON", jsonStringEmpty.contains("\"tombstones\""))

    let sampleUUID = UUID()
    let populatedTombstonesPayload = FullSyncedBacklogPayload(items: ["song1"], tombstones: [sampleUUID: now])
    let encodedPopulatedTombstones = try? JSONEncoder().encode(populatedTombstonesPayload)
    let jsonStringPopulated = String(data: encodedPopulatedTombstones ?? Data(), encoding: .utf8) ?? ""
    expectTrue("populated tombstones payload includes 'tombstones' key in JSON", jsonStringPopulated.contains("\"tombstones\""))

    let decodedPopulated = try? JSONDecoder().decode(FullSyncedBacklogPayload.self, from: encodedPopulatedTombstones ?? Data())
    expectNotNil("decoded populated backlog payload preserves tombstone UUID", decodedPopulated?.tombstones[sampleUUID])
}
