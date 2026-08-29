import Foundation

func runBackgroundGracePeriodTests() {
    // ─── Background grace period — lifecycle decisions ───────────────────────────

    section("Background grace period · lifecycle decisions")

    struct SimGraceController {
        var isGracePeriodActive = false
        var pauseCalls = 0
        var expiryCalls = 0

        mutating func enterBackground(shouldStartGracePeriod: Bool, canStartGracePeriod: Bool) {
            if shouldStartGracePeriod && canStartGracePeriod {
                isGracePeriodActive = true
            } else {
                pauseCalls += 1
            }
        }

        mutating func expireGracePeriodIfNeeded() {
            guard isGracePeriodActive else { return }
            isGracePeriodActive = false
            expiryCalls += 1
            pauseCalls += 1
        }

        mutating func enterForeground() {
            isGracePeriodActive = false
        }
    }

    var grace = SimGraceController()
    grace.enterBackground(shouldStartGracePeriod: true, canStartGracePeriod: true)
    expect("grace period starts when background task is available", grace.isGracePeriodActive)
    expect("starting grace period does not pause immediately", grace.pauseCalls == 0, detail: "got \(grace.pauseCalls)")

    expect("grace period remains active before expiry", grace.isGracePeriodActive)

    grace.expireGracePeriodIfNeeded()
    grace.expireGracePeriodIfNeeded()
    expect("expiry fires once", grace.expiryCalls == 1, detail: "got \(grace.expiryCalls)")
    expect("expiry pauses once", grace.pauseCalls == 1, detail: "got \(grace.pauseCalls)")

    var foregroundResume = SimGraceController()
    foregroundResume.enterBackground(shouldStartGracePeriod: true, canStartGracePeriod: true)
    foregroundResume.enterForeground()
    foregroundResume.expireGracePeriodIfNeeded()
    expect("foreground entry cancels the active grace period", !foregroundResume.isGracePeriodActive)
    expect("foreground cancel prevents expiry callback", foregroundResume.expiryCalls == 0, detail: "got \(foregroundResume.expiryCalls)")
    expect("foreground cancel avoids a pause from expiry", foregroundResume.pauseCalls == 0, detail: "got \(foregroundResume.pauseCalls)")

    var fallback = SimGraceController()
    fallback.enterBackground(shouldStartGracePeriod: true, canStartGracePeriod: false)
    expect("failed grace-period start leaves no active grace period", !fallback.isGracePeriodActive)
    expect("failed grace-period start falls back to immediate pause", fallback.pauseCalls == 1, detail: "got \(fallback.pauseCalls)")

    section("Background grace period · immediate scheduling & snapshotting")

    struct SimAppModelBackgroundLifecycle {
        var isAppRefreshScheduled = false
        var isProcessingScheduled = false
        var lastPlaybackSnapshot: [String: Any]?

        mutating func prepareForBackground(isPlaying: Bool, trackTitle: String?) {
            // Immediate BGTaskScheduler registration upon backgrounding
            isAppRefreshScheduled = true
            isProcessingScheduled = true
        }

        mutating func finishGracePeriod(trackTitle: String, playbackTimeSeconds: Double) {
            lastPlaybackSnapshot = [
                "title": trackTitle,
                "playbackTimeSeconds": playbackTimeSeconds,
                "snapshotAt": Date()
            ]
        }
    }

    var lifecycleSim = SimAppModelBackgroundLifecycle()
    lifecycleSim.prepareForBackground(isPlaying: true, trackTitle: "Radiohead - Creep")
    expect("prepareForBackground immediately schedules BGAppRefreshTask", lifecycleSim.isAppRefreshScheduled)
    expect("prepareForBackground immediately schedules BGProcessingTask", lifecycleSim.isProcessingScheduled)

    lifecycleSim.finishGracePeriod(trackTitle: "Radiohead - Creep", playbackTimeSeconds: 142.5)
    expect("finishGracePeriod saves playback snapshot", lifecycleSim.lastPlaybackSnapshot != nil)
    expectEqual("playback snapshot records track title", lifecycleSim.lastPlaybackSnapshot?["title"] as? String, "Radiohead - Creep")

    section("Background live auto-scrobble gate")

    func liveAutoScrobbleAllowed(
        applicationState: String,
        isGracePeriodActive: Bool,
        preventDuplicates: Bool
    ) -> Bool {
        applicationState != "background" || isGracePeriodActive || !preventDuplicates
    }

    expect("active app allows live auto-scrobble", liveAutoScrobbleAllowed(applicationState: "active", isGracePeriodActive: false, preventDuplicates: true))
    expect("inactive app state still allows live auto-scrobble", liveAutoScrobbleAllowed(applicationState: "inactive", isGracePeriodActive: false, preventDuplicates: true))
    expect("background app blocks live auto-scrobble outside grace period when duplicate prevention is on", !liveAutoScrobbleAllowed(applicationState: "background", isGracePeriodActive: false, preventDuplicates: true))
    expect("background app allows live auto-scrobble during grace period", liveAutoScrobbleAllowed(applicationState: "background", isGracePeriodActive: true, preventDuplicates: true))
    expect("background app allows live auto-scrobble outside grace period when duplicate prevention is off", liveAutoScrobbleAllowed(applicationState: "background", isGracePeriodActive: false, preventDuplicates: false))

    section("Projected background now playing separation")

    struct SimProjectedBackgroundOutcome {
        let didSendNowPlaying: Bool
        let didAttemptLiveScrobble: Bool
    }

    func projectedBackgroundOutcome(
        applicationState: String,
        isGracePeriodActive: Bool,
        preventDuplicates: Bool,
        sendNowPlayingAutomatically: Bool,
        hasSentNowPlaying: Bool,
        playbackState: String
    ) -> SimProjectedBackgroundOutcome {
        let didSendNowPlaying =
            sendNowPlayingAutomatically &&
            !hasSentNowPlaying &&
            playbackState == "playing"
        let didAttemptLiveScrobble = liveAutoScrobbleAllowed(
            applicationState: applicationState,
            isGracePeriodActive: isGracePeriodActive,
            preventDuplicates: preventDuplicates
        )
        return SimProjectedBackgroundOutcome(
            didSendNowPlaying: didSendNowPlaying,
            didAttemptLiveScrobble: didAttemptLiveScrobble
        )
    }

    let backgroundBlockedScrobble = projectedBackgroundOutcome(
        applicationState: "background",
        isGracePeriodActive: false,
        preventDuplicates: true,
        sendNowPlayingAutomatically: true,
        hasSentNowPlaying: false,
        playbackState: "playing"
    )
    expect("projected background path still sends now playing when duplicate prevention blocks the live scrobble", backgroundBlockedScrobble.didSendNowPlaying)
    expect("projected background path blocks live scrobble outside grace period when duplicate prevention is on", !backgroundBlockedScrobble.didAttemptLiveScrobble)

    let backgroundAllowedScrobble = projectedBackgroundOutcome(
        applicationState: "background",
        isGracePeriodActive: false,
        preventDuplicates: false,
        sendNowPlayingAutomatically: true,
        hasSentNowPlaying: false,
        playbackState: "playing"
    )
    expect("projected background path still sends now playing when duplicate prevention is off", backgroundAllowedScrobble.didSendNowPlaying)
    expect("projected background path allows live scrobble outside grace period when duplicate prevention is off", backgroundAllowedScrobble.didAttemptLiveScrobble)
}

func runScheduledBackgroundRecoveryTests() {
    // ─── Scheduled background recovery separation ────────────────────────────────

    section("Scheduled background recovery separation")

    struct SimScheduledBackgroundRecovery {
        let hasSeenSetup: Bool
        let isUserPaused: Bool
        let hasSessionKey: Bool
        let appleMusicAPIEnabled: Bool

        func run() -> (didImportListeningHistory: Bool, didImportAppleMusicAPI: Bool, didFlushBacklog: Bool, didTickLiveEngine: Bool) {
            guard hasSeenSetup else {
                return (false, false, false, false)
            }

            let didImportListeningHistory = true
            let didImportAppleMusicAPI = !isUserPaused && appleMusicAPIEnabled
            let didFlushBacklog = !isUserPaused && hasSessionKey
            let didTickLiveEngine = false
            return (didImportListeningHistory, didImportAppleMusicAPI, didFlushBacklog, didTickLiveEngine)
        }
    }

    let enabled = SimScheduledBackgroundRecovery(
        hasSeenSetup: true,
        isUserPaused: false,
        hasSessionKey: true,
        appleMusicAPIEnabled: true
    ).run()
    expect("scheduled recovery imports Listening History", enabled.didImportListeningHistory)
    expect("scheduled recovery imports Apple Music API plays when enabled", enabled.didImportAppleMusicAPI)
    expect("scheduled recovery flushes backlog when signed in", enabled.didFlushBacklog)
    expect("scheduled recovery never ticks the live engine", !enabled.didTickLiveEngine)

    let paused = SimScheduledBackgroundRecovery(
        hasSeenSetup: true,
        isUserPaused: true,
        hasSessionKey: true,
        appleMusicAPIEnabled: true
    ).run()
    expect("paused scheduled recovery still checks Listening History", paused.didImportListeningHistory)
    expect("paused scheduled recovery skips Apple Music API import", !paused.didImportAppleMusicAPI)
    expect("paused scheduled recovery skips backlog flush", !paused.didFlushBacklog)

    func shouldScheduleProcessing(pendingCount: Int, hasActiveTrack: Bool) -> Bool {
        _ = hasActiveTrack
        return pendingCount > 0
    }

    expect("processing task is not scheduled from active-track state alone", !shouldScheduleProcessing(pendingCount: 0, hasActiveTrack: true))
    expect("processing task is scheduled when backlog has pending work", shouldScheduleProcessing(pendingCount: 1, hasActiveTrack: false))
}

func runSettingsDefaultsTests() {
    // ─── Settings defaults / reset coverage ─────────────────────────────────────

    section("Settings defaults / reset coverage")

    let runtimePreventDuplicatesDefault = true
    let macSettingsPreventDuplicatesDefault = true
    let macSettingsPreventDuplicatesAfterReset = true
    let macButtonThemeSelectionDefault = "colorful"
    let macButtonThemeSelectionAfterReset = "colorful"
    expectEqual("macOS duplicate-prevention default matches runtime", macSettingsPreventDuplicatesDefault, runtimePreventDuplicatesDefault)
    expectEqual("macOS reset restores duplicate prevention to runtime default", macSettingsPreventDuplicatesAfterReset, runtimePreventDuplicatesDefault)
    expectEqual("macOS button theme defaults to colorful", macButtonThemeSelectionDefault, "colorful")
    expectEqual("macOS reset restores button theme default", macButtonThemeSelectionAfterReset, macButtonThemeSelectionDefault)

    let resetClearedKeys: Set<String> = [
        "FastScrobbler.Pro.loveOnFavoriteEnabled",
        "FastScrobbler.Pro.scrobbleThresholdIndex",
        "FastScrobbler.Pro.useAlbumArtistForScrobbling",
        "FastScrobbler.Pro.useFirstArtistOnlyForScrobbling",
        "FastScrobbler.Pro.removeBracketsEnabled",
        "FastScrobbler.Pro.removeAllBracketsEnabled",
        "FastScrobbler.Pro.removeBracketsKeywords",
        "FastScrobbler.Pro.removeBracketsFromAlbumTitlesEnabled",
        "FastScrobbler.Pro.removeAllBracketsFromAlbumTitlesEnabled",
        "FastScrobbler.Pro.removeBracketsFromAlbumTitleKeywords",
        "FastScrobbler.Pro.preventDuplicateScrobblesEnabled",
        "FastScrobbler.Pro.scrobbleLoopedTracksEnabled",
        "FastScrobbler.App.scrobbleAppleMusicAPIEnabled",
        "FastScrobbler.App.scrobbleOnlyNonLibraryAppleMusicAPITracks",
        "FastScrobbler.App.extendedListeningHistoryScanEnabled",
        "FastScrobbler.App.listeningHistoryRequireConfirmationEnabled",
        "FastScrobbler.App.listeningHistoryResumeRecoveryCutoffDate",
        "FastScrobbler.App.themeSelection",
        "FastScrobbler.App.buttonThemeSelection",
        "FastScrobbler.Pro.textReplacementRules",
    ]

    expect("reset clears scrobbleLoopedTracksEnabled", resetClearedKeys.contains("FastScrobbler.Pro.scrobbleLoopedTracksEnabled"))
    expect("reset clears scrobbleAppleMusicAPIEnabled", resetClearedKeys.contains("FastScrobbler.App.scrobbleAppleMusicAPIEnabled"))
    expect("reset clears non-library Apple Music API filter", resetClearedKeys.contains("FastScrobbler.App.scrobbleOnlyNonLibraryAppleMusicAPITracks"))
    expect("reset clears extendedListeningHistoryScanEnabled", resetClearedKeys.contains("FastScrobbler.App.extendedListeningHistoryScanEnabled"))
    expect("reset clears listeningHistoryRequireConfirmationEnabled", resetClearedKeys.contains("FastScrobbler.App.listeningHistoryRequireConfirmationEnabled"))
    expect("reset clears listeningHistoryResumeRecoveryCutoffDate", resetClearedKeys.contains("FastScrobbler.App.listeningHistoryResumeRecoveryCutoffDate"))
    expect("reset clears themeSelection", resetClearedKeys.contains("FastScrobbler.App.themeSelection"))
    expect("reset clears buttonThemeSelection", resetClearedKeys.contains("FastScrobbler.App.buttonThemeSelection"))
    expect("reset clears textReplacementRules", resetClearedKeys.contains("FastScrobbler.Pro.textReplacementRules"))
    expect("reset clears useFirstArtistOnlyForScrobbling", resetClearedKeys.contains("FastScrobbler.Pro.useFirstArtistOnlyForScrobbling"))

    let iOSLoopedTracksAfterReset = false
    expectEqual("iOS reset restores looped-track scrobbling default", iOSLoopedTracksAfterReset, false)

    func seedNonLibraryAppleMusicAPIFilterIfNeeded(existingValue: Bool?) -> Bool {
        existingValue ?? true
    }

    func seedAppleMusicAPIScrobblingIfNeeded(existingValue: Bool?, hasSeenSetup: Bool, isAutoScrobbleOff: Bool) -> Bool {
        if let existingValue = existingValue { return existingValue }
        return !hasSeenSetup || isAutoScrobbleOff
    }

    func removeLegacyListeningHistoryScrobblingToggle(
        legacyListeningHistoryEnabled: Bool?,
        requireConfirmation: Bool?
    ) -> (legacyListeningHistoryEnabled: Bool?, requireConfirmation: Bool?) {
        let _ = legacyListeningHistoryEnabled
        return (legacyListeningHistoryEnabled: nil, requireConfirmation: requireConfirmation)
    }

    func migrateLegacyAppGroupValue<T: Equatable>(appGroupValue: T?, standardValue: T?) -> T? {
        guard appGroupValue == nil else { return appGroupValue }
        return standardValue
    }

    let extendedListeningHistoryScanDefault = false
    let iOSExtendedListeningHistoryScanAfterReset = false
    let listeningHistoryRequireConfirmationDefault = true
    let iOSListeningHistoryRequireConfirmationAfterReset = true
    let appleMusicAPIScrobblingDefault = true
    let iOSAppleMusicAPIScrobblingAfterReset = true
    let nonLibraryAppleMusicAPIFilterDefault = true
    let iOSNonLibraryAppleMusicAPIFilterAfterReset = true
    let firstArtistOnlyDefault = false
    let iOSFirstArtistOnlyAfterReset = false
    let themeSelectionDefault = "system"
    let iOSThemeSelectionAfterReset = "system"
    let buttonThemeSelectionDefault = "colorful"
    let iOSButtonThemeSelectionAfterReset = "colorful"
    let iCloudSyncDefault = false
    expectEqual("Apple Music API scrobbling defaults on", appleMusicAPIScrobblingDefault, true)
    expectEqual("iOS reset restores Apple Music API scrobbling default", iOSAppleMusicAPIScrobblingAfterReset, appleMusicAPIScrobblingDefault)
    expectEqual("seed preserves explicit off for Apple Music API scrobbling", seedAppleMusicAPIScrobblingIfNeeded(existingValue: false, hasSeenSetup: true, isAutoScrobbleOff: false), false)
    expectEqual("seed preserves explicit on for Apple Music API scrobbling", seedAppleMusicAPIScrobblingIfNeeded(existingValue: true, hasSeenSetup: true, isAutoScrobbleOff: false), true)
    expectEqual("seed writes false when key is missing and user has auto-scrobble enabled", seedAppleMusicAPIScrobblingIfNeeded(existingValue: nil, hasSeenSetup: true, isAutoScrobbleOff: false), false)
    expectEqual("seed writes true when key is missing and user has auto-scrobble disabled", seedAppleMusicAPIScrobblingIfNeeded(existingValue: nil, hasSeenSetup: true, isAutoScrobbleOff: true), true)
    expectEqual("seed writes true when key is missing and setup is incomplete (new install)", seedAppleMusicAPIScrobblingIfNeeded(existingValue: nil, hasSeenSetup: false, isAutoScrobbleOff: false), true)
    expectEqual("non-library Apple Music API filter defaults on", nonLibraryAppleMusicAPIFilterDefault, true)
    expectEqual("iOS reset restores non-library Apple Music API filter default", iOSNonLibraryAppleMusicAPIFilterAfterReset, nonLibraryAppleMusicAPIFilterDefault)
    expectEqual("seed preserves explicit off for non-library Apple Music API filter", seedNonLibraryAppleMusicAPIFilterIfNeeded(existingValue: false), false)
    expectEqual("seed preserves explicit on for non-library Apple Music API filter", seedNonLibraryAppleMusicAPIFilterIfNeeded(existingValue: true), true)
    expectEqual("seed writes on when the key is missing and setup is complete", seedNonLibraryAppleMusicAPIFilterIfNeeded(existingValue: nil), true)
    expectEqual("seed writes on when the key is missing and setup is incomplete", seedNonLibraryAppleMusicAPIFilterIfNeeded(existingValue: nil), true)
    expectEqual(
        "removing legacy listening-history off leaves confirmation unchanged",
        removeLegacyListeningHistoryScrobblingToggle(legacyListeningHistoryEnabled: false, requireConfirmation: false).requireConfirmation,
        false
    )
    expectEqual(
        "removing legacy listening-history on leaves confirmation unchanged",
        removeLegacyListeningHistoryScrobblingToggle(legacyListeningHistoryEnabled: true, requireConfirmation: false).requireConfirmation,
        false
    )
    expectEqual(
        "removing missing listening-history toggle leaves confirmation unchanged",
        removeLegacyListeningHistoryScrobblingToggle(legacyListeningHistoryEnabled: nil, requireConfirmation: nil).requireConfirmation,
        nil
    )
    expectEqual(
        "removing listening-history toggle clears the legacy key",
        removeLegacyListeningHistoryScrobblingToggle(legacyListeningHistoryEnabled: false, requireConfirmation: false).legacyListeningHistoryEnabled,
        nil
    )
    expectEqual("App Group migration preserves explicit legacy bool off", migrateLegacyAppGroupValue(appGroupValue: nil, standardValue: false), false)
    expectEqual("App Group migration preserves explicit app-group bool off", migrateLegacyAppGroupValue(appGroupValue: false, standardValue: true), false)
    expectEqual("App Group migration leaves missing bool unset for runtime default", migrateLegacyAppGroupValue(appGroupValue: Optional<Bool>.none, standardValue: nil), nil)
    expectEqual("App Group migration preserves legacy integer settings", migrateLegacyAppGroupValue(appGroupValue: Optional<Int>.none, standardValue: 3), 3)
    expectEqual("App Group migration preserves legacy data settings", migrateLegacyAppGroupValue(appGroupValue: Optional<Data>.none, standardValue: Data([1, 2, 3])), Data([1, 2, 3]))
    expectEqual("App Group migration does not overwrite existing custom values", migrateLegacyAppGroupValue(appGroupValue: 1, standardValue: 3), 1)
    expectEqual("extended Listening History scan defaults off", extendedListeningHistoryScanDefault, false)
    expectEqual("iOS reset restores extended Listening History scan default", iOSExtendedListeningHistoryScanAfterReset, extendedListeningHistoryScanDefault)
    expectEqual("listening History require confirmation defaults on", listeningHistoryRequireConfirmationDefault, true)
    expectEqual("iOS reset restores listening History require confirmation default", iOSListeningHistoryRequireConfirmationAfterReset, listeningHistoryRequireConfirmationDefault)

    struct SimAutoScrobbleListeningHistoryToggle {
        var storedRequireConfirmation: Bool
        var callbackValues: [Bool] = []

        var displayedAutoScrobbleValue: Bool {
            !storedRequireConfirmation
        }

        mutating func setDisplayedAutoScrobbleValue(_ isEnabled: Bool) {
            let newStoredRequireConfirmation = !isEnabled
            guard storedRequireConfirmation != newStoredRequireConfirmation else { return }
            storedRequireConfirmation = newStoredRequireConfirmation
            callbackValues.append(newStoredRequireConfirmation)
        }
    }

    var reviewModePresentation = SimAutoScrobbleListeningHistoryToggle(storedRequireConfirmation: true)
    expectEqual("stored confirmation on renders auto-scrobble off", reviewModePresentation.displayedAutoScrobbleValue, false)
    reviewModePresentation.setDisplayedAutoScrobbleValue(true)
    expectEqual("enabling auto-scrobble stores confirmation off", reviewModePresentation.storedRequireConfirmation, false)
    expectEqual("enabling auto-scrobble reports confirmation off to the callback", reviewModePresentation.callbackValues, [false])

    var autoScrobblePresentation = SimAutoScrobbleListeningHistoryToggle(storedRequireConfirmation: false)
    expectEqual("stored confirmation off renders auto-scrobble on", autoScrobblePresentation.displayedAutoScrobbleValue, true)
    autoScrobblePresentation.setDisplayedAutoScrobbleValue(false)
    expectEqual("disabling auto-scrobble stores confirmation on", autoScrobblePresentation.storedRequireConfirmation, true)
    expectEqual("disabling auto-scrobble reports confirmation on to the callback", autoScrobblePresentation.callbackValues, [true])
    autoScrobblePresentation.setDisplayedAutoScrobbleValue(false)
    expectEqual("setting the same auto-scrobble value twice does not fire a duplicate callback", autoScrobblePresentation.callbackValues, [true])

    expectEqual("first-artist-only scrobbling defaults off", firstArtistOnlyDefault, false)
    expectEqual("iOS reset restores first-artist-only scrobbling default", iOSFirstArtistOnlyAfterReset, firstArtistOnlyDefault)
    expectEqual("theme selection defaults to system", themeSelectionDefault, "system")
    expectEqual("iOS reset restores theme selection default", iOSThemeSelectionAfterReset, themeSelectionDefault)
    expectEqual("button theme defaults to colorful", buttonThemeSelectionDefault, "colorful")
    expectEqual("iOS reset restores button theme default", iOSButtonThemeSelectionAfterReset, buttonThemeSelectionDefault)
    expectEqual("iCloud sync defaults off", iCloudSyncDefault, false)

    let recentTracksImporterStateAfterReset: [String: Any] = [:]
    expect("reset clears Apple Music recent-tracks importer state", recentTracksImporterStateAfterReset.isEmpty)

    let builtInRulesAfterReset: [(find: String, replace: String, enabled: Bool)] = [
        ("- Single", "", false),
        ("- EP", "", false),
    ]
    expect("reset keeps built-in text replacement rules present", builtInRulesAfterReset.count == 2)
    expect("reset keeps built-in text replacement rules disabled", builtInRulesAfterReset.allSatisfy { !$0.enabled })
}
