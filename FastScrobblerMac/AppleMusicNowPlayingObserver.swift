import Foundation
import OSLog
import AppKit
import CoreServices

@MainActor
final class AppleMusicNowPlayingObserver: ObservableObject {
    nonisolated private static let fallbackTrackDurationSeconds: TimeInterval = 180

    enum ObserverError: Error, LocalizedError {
        case musicAutomationDenied
        case noNowPlayingItem

        var errorDescription: String? {
            switch self {
            case .musicAutomationDenied:
                return NSLocalizedString("Permission is required to control the Music app and read now-playing metadata.", comment: "")
            case .noNowPlayingItem:
                return NSLocalizedString("No now-playing item found.", comment: "")
            }
        }
    }

    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published private(set) var track: Track?
    @Published private(set) var playbackState: MPMusicPlaybackState = .stopped
    @Published private(set) var playbackTimeSeconds: TimeInterval = 0
    @Published private(set) var isNowPlayingLovedInAppleMusic: Bool? = nil
    @Published private(set) var isRunning = false

    private let logger = Logger(subsystem: "FastScrobbler", category: "MusicObserver")
    private var timer: Timer?
    private var currentPollingInterval: TimeInterval = 0
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var distributedObservers: [NSObjectProtocol] = []
    nonisolated private static let scriptingQueue = DispatchQueue(label: "FastScrobbler.MusicAppleScript", qos: .userInitiated)

    init() {
        authorizationStatus = Self.determineMusicAutomationAuthorizationStatus(askUserIfNeeded: false)
        Task { @MainActor in
            await refreshFromMusic()
        }
    }

    deinit {
        removeObservers()
    }

    func refreshOnceIfAuthorized() {
        Task { @MainActor in
            await refreshFromMusic()
        }
    }

    func refreshAuthorizationStatus() async -> MPMediaLibraryAuthorizationStatus {
        let status = await Self.determineMusicAutomationAuthorizationStatusAsync(askUserIfNeeded: false)
        applyAutomationAuthorization(status)
        return status
    }

    /// Attempts to trigger macOS's Automation permission prompt for controlling the Music app.
    func requestMusicControlPermission() async {
        let status = await Self.determineMusicAutomationAuthorizationStatusAsync(askUserIfNeeded: true)
        if status == .notDetermined {
            await requestMusicControlPermissionWithAppleScriptFallback()
        } else {
            applyAutomationAuthorization(status)
        }
        await refreshFromMusic()
    }

    func start() async throws {
        setupObservers()

        if isRunning {
            await refreshFromMusic()
            if authorizationStatus != .authorized { throw ObserverError.musicAutomationDenied }
            return
        }

        await refreshFromMusic()
        guard authorizationStatus == .authorized else { throw ObserverError.musicAutomationDenied }

        isRunning = true
        updatePollingTimerIfNeeded()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        timer?.invalidate()
        timer = nil
        currentPollingInterval = 0
    }

    func skipToNextItem() {
        Task { try? await Self.runAppleScriptAsync(#"tell application "Music" to next track"#) }
    }
    func skipToPreviousItem() {
        Task { try? await Self.runAppleScriptAsync(#"tell application "Music" to previous track"#) }
    }
    func togglePlayPause() {
        Task { try? await Self.runAppleScriptAsync(#"tell application "Music" to playpause"#) }
    }

    private func refreshFromMusic() async {
        guard Self.isMusicAppRunning() else {
            authorizationStatus = .authorized
            resetPlaybackSnapshot()
            updatePollingTimerIfNeeded()
            return
        }

        if authorizationStatus != .authorized {
            let status = await Self.determineMusicAutomationAuthorizationStatusAsync(askUserIfNeeded: false)
            applyAutomationAuthorization(status)
        }
        guard authorizationStatus == .authorized else {
            return
        }

        do {
            let snapshot = try await Self.readMusicSnapshotAsync()
            authorizationStatus = .authorized
            playbackState = snapshot.playbackState
            playbackTimeSeconds = snapshot.playbackTimeSeconds
            if let t = snapshot.track, t.usesFallbackDuration == true {
                logger.debug(
                    "Snapshot missing duration for \(t.artist, privacy: .public) - \(t.title, privacy: .public); using fallback duration of \(Self.fallbackTrackDurationSeconds, privacy: .public)s"
                )
            }
            track = snapshot.track
            isNowPlayingLovedInAppleMusic = snapshot.isTrackFavorited
        } catch let error as AppleScriptError {
            if error.number == Int(errAEEventNotPermitted) {
                // Not authorized to send Apple Events.
                applyAutomationAuthorization(.denied)
                return
            }
            if error.number == Int(procNotFound) {
                // Music isn't running (or still launching).
                authorizationStatus = .authorized
                resetPlaybackSnapshot()
                updatePollingTimerIfNeeded()
                return
            }
            logger.debug("AppleScript error: \(error.message, privacy: .public) (\(error.number, privacy: .public))")
            resetPlaybackSnapshot()
        } catch {
            logger.debug("Music snapshot error: \(error.localizedDescription, privacy: .public)")
            resetPlaybackSnapshot()
        }

        updatePollingTimerIfNeeded()
    }

    private func updatePollingTimerIfNeeded() {
        guard isRunning else { return }

        let desiredInterval: TimeInterval
        if !Self.isMusicAppRunning() {
            desiredInterval = 30.0
        } else if playbackState == .playing {
            desiredInterval = 1.0
        } else {
            desiredInterval = 10.0
        }

        if timer == nil || currentPollingInterval != desiredInterval {
            timer?.invalidate()
            currentPollingInterval = desiredInterval
            timer = Timer.scheduledTimer(withTimeInterval: desiredInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshFromMusic()
                }
            }
        }
    }

    private func setupObservers() {
        removeObservers()

        let wsNC = NSWorkspace.shared.notificationCenter
        let launchObs = wsNC.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Music" || app.bundleIdentifier == "com.apple.iTunes" else { return }
            Task { @MainActor [weak self] in
                await self?.refreshFromMusic()
            }
        }

        let termObs = wsNC.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Music" || app.bundleIdentifier == "com.apple.iTunes" else { return }
            Task { @MainActor [weak self] in
                await self?.refreshFromMusic()
            }
        }
        workspaceObservers = [launchObs, termObs]

        let distNC = DistributedNotificationCenter.default()
        let playerObs1 = distNC.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshFromMusic()
            }
        }
        let playerObs2 = distNC.addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshFromMusic()
            }
        }
        distributedObservers = [playerObs1, playerObs2]
    }

    nonisolated private func removeObservers() {
        let wsNC = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsNC.removeObserver(obs)
        }
        workspaceObservers.removeAll()

        let distNC = DistributedNotificationCenter.default()
        for obs in distributedObservers {
            distNC.removeObserver(obs)
        }
        distributedObservers.removeAll()
    }

    nonisolated private static func isMusicAppRunning() -> Bool {
        let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        if !musicApps.isEmpty { return true }
        let iTunesApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iTunes")
        return !iTunesApps.isEmpty
    }

    private func applyAutomationAuthorization(_ status: MPMediaLibraryAuthorizationStatus) {
        authorizationStatus = status
        guard status != .authorized else { return }
        resetPlaybackSnapshot()
    }

    private func resetPlaybackSnapshot() {
        track = nil
        playbackState = .stopped
        playbackTimeSeconds = 0
        isNowPlayingLovedInAppleMusic = nil
    }

    private func requestMusicControlPermissionWithAppleScriptFallback() async {
        do {
            _ = try await Self.runAppleScriptAsync(#"tell application id "com.apple.Music" to get running"#)
            applyAutomationAuthorization(.authorized)
        } catch let error as AppleScriptError {
            if error.number == Int(errAEEventNotPermitted) {
                applyAutomationAuthorization(.denied)
            } else {
                logger.debug("Music automation permission fallback failed: \(error.message, privacy: .public) (\(error.number, privacy: .public))")
                applyAutomationAuthorization(.notDetermined)
            }
        } catch {
            logger.debug("Music automation permission fallback failed: \(error.localizedDescription, privacy: .public)")
            applyAutomationAuthorization(.notDetermined)
        }
    }

    private struct MusicSnapshot: Sendable {
        var playbackState: MPMusicPlaybackState
        var playbackTimeSeconds: TimeInterval
        var track: Track?
        var isTrackFavorited: Bool?
    }

    private struct AppleScriptError: Error, Sendable {
        let number: Int
        let message: String
    }

    nonisolated private static func readMusicSnapshotSync() throws -> MusicSnapshot {
        let script = #"""
        tell application "Music"
            if not (it is running) then
                return "stopped"
            end if

            set sep to (ASCII character 31)
            set ps to (get player state) as string
            set pos to 0
            try
                set pos to (get player position)
            end try

            set a to ""
            set n to ""
            set al to ""
            set aa to ""
            set comp to ""
            set d to 0
            set streamTitle to ""
            set fav to ""
            set pid to ""

            try
                set t to current track
                try
                    set a to artist of t
                end try
                try
                    set n to name of t
                end try
                try
                    set al to album of t
                end try
                try
                    set aa to album artist of t
                end try
                try
                    set comp to (compilation of t) as string
                end try
                try
                    set d to duration of t
                end try
                try
                    set fav to (favorited of t) as string
                end try
                try
                    set pid to (persistent ID of t) as string
                end try
            end try

            try
                set streamTitle to (get current stream title)
            on error
                set streamTitle to ""
            end try

            return ps & sep & a & sep & n & sep & al & sep & d & sep & pos & sep & aa & sep & comp & sep & streamTitle & sep & fav & sep & pid
        end tell
        """#

        let result = try runAppleScriptSync(script)
        let parts = splitSnapshotFields(result)
        let stateString = parts.first ?? "stopped"

        let playbackState: MPMusicPlaybackState
        switch stateString.lowercased() {
        case "playing": playbackState = .playing
        case "paused": playbackState = .paused
        default: playbackState = .stopped
        }

        let artist = parts.count > 1 ? parts[1] : ""
        let title = parts.count > 2 ? parts[2] : ""
        let album = parts.count > 3 ? parts[3] : ""
        let duration = parts.count > 4 ? (parseTimeInterval(parts[4]) ?? 0) : 0
        let position = parts.count > 5 ? (parseTimeInterval(parts[5]) ?? 0) : 0
        let albumArtist = parts.count > 6 ? parts[6] : ""
        let isCompilation = parts.count > 7 ? parseAppleScriptBool(parts[7]) : nil
        let streamTitle = parts.count > 8 ? parts[8] : ""
        let isFavorited = parts.count > 9 ? parseAppleScriptBool(parts[9]) : nil
        let persistentID = parts.count > 10 ? parsePersistentID(parts[10]) : nil

        var resolvedArtist = artist
        var resolvedTitle = title
        var resolvedAlbum = album

        if resolvedArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let parsed = parseStreamTitle(streamTitle) {
                resolvedArtist = parsed.artist
                resolvedTitle = parsed.title
                if resolvedAlbum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedAlbum = parsed.album ?? resolvedAlbum
                }
            }
        }

        if resolvedArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let candidate = Track.usableAlbumArtistForArtistSubstitution(albumArtist, isCompilation: isCompilation) {
                resolvedArtist = candidate
            }
        }

        let resolvedDuration = duration > 0 ? duration : Self.fallbackTrackDurationSeconds
        let usesFallbackDuration = duration <= 0

        let track: Track?
        if resolvedArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            track = nil
        } else {
            track = Track(
                artist: resolvedArtist,
                title: resolvedTitle,
                album: resolvedAlbum.isEmpty ? nil : resolvedAlbum,
                albumArtist: albumArtist.isEmpty ? nil : albumArtist,
                durationSeconds: resolvedDuration,
                usesFallbackDuration: usesFallbackDuration,
                persistentID: persistentID,
                playbackStoreID: nil,
                isCompilation: isCompilation
            )
        }

        return MusicSnapshot(
            playbackState: playbackState,
            playbackTimeSeconds: max(0, position),
            track: track,
            isTrackFavorited: track == nil ? nil : isFavorited
        )
    }

    nonisolated private static func readMusicSnapshotAsync() async throws -> MusicSnapshot {
        try await withCheckedThrowingContinuation { cont in
            scriptingQueue.async {
                cont.resume(with: Result { try readMusicSnapshotSync() })
            }
        }
    }

    nonisolated private static func determineMusicAutomationAuthorizationStatusAsync(
        askUserIfNeeded: Bool
    ) async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { cont in
            scriptingQueue.async {
                cont.resume(returning: determineMusicAutomationAuthorizationStatus(askUserIfNeeded: askUserIfNeeded))
            }
        }
    }

    nonisolated private static func determineMusicAutomationAuthorizationStatus(
        askUserIfNeeded: Bool
    ) -> MPMediaLibraryAuthorizationStatus {
        let bundleID = "com.apple.Music"
        var target = AEAddressDesc()
        let createStatus = bundleID.withCString { buffer in
            AECreateDesc(DescType(typeApplicationBundleID), buffer, bundleID.utf8.count, &target)
        }

        guard createStatus == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(procNotFound):
            return .authorized
        default:
            return .notDetermined
        }
    }

    nonisolated private static func runAppleScriptAsync(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            scriptingQueue.async {
                cont.resume(with: Result { try runAppleScriptSync(source) })
            }
        }
    }

    nonisolated private static func runAppleScriptSync(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError(number: -1, message: "Failed to compile AppleScript.")
        }

        var errorDict: NSDictionary?
        let output = script.executeAndReturnError(&errorDict)
        if let errorDict,
           let number = errorDict[NSAppleScript.errorNumber] as? Int {
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "AppleScript error."
            throw AppleScriptError(number: number, message: message)
        }

        return output.stringValue ?? ""
    }

    nonisolated private static func splitSnapshotFields(_ output: String) -> [String] {
        let delimiter = "\u{1F}"
        if output.contains(delimiter) {
            return output.components(separatedBy: delimiter)
        }
        return output.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
    }

    nonisolated private static func parseStreamTitle(_ value: String) -> (artist: String, title: String, album: String?)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators = [" - ", " – ", " — ", " —", " -", " –"]
        for separator in separators {
            if let range = trimmed.range(of: separator) {
                let artist = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !artist.isEmpty, !title.isEmpty {
                    return (artist, title, nil)
                }
            }
        }

        return nil
    }

    nonisolated private static func parseAppleScriptBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    nonisolated private static func parsePersistentID(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UInt64(trimmed, radix: 16)
    }

    nonisolated private static func parseTimeInterval(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return TimeInterval(normalized)
    }
}
