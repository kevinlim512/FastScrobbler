import Foundation
import OSLog
import AppKit

@MainActor
final class AppleMusicNowPlayingObserver: ObservableObject {
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
    nonisolated private static let scriptingQueue = DispatchQueue(label: "FastScrobbler.MusicAppleScript", qos: .userInitiated)

    init() {
        Task { @MainActor in
            await refreshFromMusic()
        }
    }

    func refreshOnceIfAuthorized() {
        Task { @MainActor in
            await refreshFromMusic()
        }
    }

    /// Attempts to trigger macOS's Automation permission prompt for controlling the Music app.
    func requestMusicControlPermission() async {
        Self.launchMusicIfNeeded()
        try? await Task.sleep(nanoseconds: 150_000_000)
        do {
            _ = try await Self.runAppleScriptAsync(#"tell application "Music" to get player state as string"#)
        } catch let error as AppleScriptError where error.number == -600 {
            // Music can take a moment to launch on some systems.
            try? await Task.sleep(nanoseconds: 250_000_000)
            _ = try? await Self.runAppleScriptAsync(#"tell application "Music" to get player state as string"#)
        } catch {
            // Ignore: `refreshFromMusic()` will set the correct authorization state.
        }
        await refreshFromMusic()
    }

    func start() async throws {
        if isRunning {
            await refreshFromMusic()
            if authorizationStatus != .authorized { throw ObserverError.musicAutomationDenied }
            return
        }

        await refreshFromMusic()
        guard authorizationStatus == .authorized else { throw ObserverError.musicAutomationDenied }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshFromMusic()
            }
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func refreshFromMusic() async {
        do {
            let snapshot = try await Self.readMusicSnapshotAsync()
            authorizationStatus = .authorized
            playbackState = snapshot.playbackState
            playbackTimeSeconds = snapshot.playbackTimeSeconds
            track = snapshot.track
            isNowPlayingLovedInAppleMusic = snapshot.isTrackFavorited
        } catch let error as AppleScriptError {
            if error.number == -1743 {
                // Not authorized to send Apple Events.
                authorizationStatus = .denied
                track = nil
                playbackState = .stopped
                playbackTimeSeconds = 0
                isNowPlayingLovedInAppleMusic = nil
                return
            }
            if error.number == -600 {
                // Music isn't running (or still launching).
                authorizationStatus = .authorized
                track = nil
                playbackState = .stopped
                playbackTimeSeconds = 0
                isNowPlayingLovedInAppleMusic = nil
                return
            }
            logger.debug("AppleScript error: \(error.message, privacy: .public) (\(error.number, privacy: .public))")
            track = nil
            playbackState = .stopped
            playbackTimeSeconds = 0
            isNowPlayingLovedInAppleMusic = nil
        } catch {
            logger.debug("Music snapshot error: \(error.localizedDescription, privacy: .public)")
            track = nil
            playbackState = .stopped
            playbackTimeSeconds = 0
            isNowPlayingLovedInAppleMusic = nil
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
        let duration = parts.count > 4 ? TimeInterval(parts[4]) ?? 0 : 0
        let position = parts.count > 5 ? TimeInterval(parts[5]) ?? 0 : 0
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
                durationSeconds: duration > 0 ? duration : nil,
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

    nonisolated private static func launchMusicIfNeeded() {
        let bundleID = "com.apple.Music"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
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
}
