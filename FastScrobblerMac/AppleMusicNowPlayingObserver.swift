import Foundation
import OSLog

@MainActor
final class AppleMusicNowPlayingObserver: ObservableObject {
    enum ObserverError: Error, LocalizedError {
        case musicAutomationDenied
        case noNowPlayingItem

        var errorDescription: String? {
            switch self {
            case .musicAutomationDenied:
                return "Permission is required to control the Music app and read now-playing metadata."
            case .noNowPlayingItem:
                return "No now-playing item found."
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

    init() {
        refreshFromMusic()
    }

    func refreshOnceIfAuthorized() {
        refreshFromMusic()
    }

    func start() async throws {
        if isRunning {
            refreshFromMusic()
            if authorizationStatus != .authorized { throw ObserverError.musicAutomationDenied }
            return
        }

        refreshFromMusic()
        guard authorizationStatus == .authorized else { throw ObserverError.musicAutomationDenied }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromMusic()
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

    private func refreshFromMusic() {
        do {
            let snapshot = try readMusicSnapshot()
            authorizationStatus = .authorized
            playbackState = snapshot.playbackState
            playbackTimeSeconds = snapshot.playbackTimeSeconds
            track = snapshot.track
        } catch let error as AppleScriptError {
            if error.number == -1743 {
                // Not authorized to send Apple Events.
                authorizationStatus = .denied
                track = nil
                playbackState = .stopped
                playbackTimeSeconds = 0
                return
            }
            logger.debug("AppleScript error: \(error.message, privacy: .public) (\(error.number, privacy: .public))")
            track = nil
            playbackState = .stopped
            playbackTimeSeconds = 0
        } catch {
            logger.debug("Music snapshot error: \(error.localizedDescription, privacy: .public)")
            track = nil
            playbackState = .stopped
            playbackTimeSeconds = 0
        }
    }

    private struct MusicSnapshot {
        var playbackState: MPMusicPlaybackState
        var playbackTimeSeconds: TimeInterval
        var track: Track?
    }

    private struct AppleScriptError: Error {
        let number: Int
        let message: String
    }

    private func readMusicSnapshot() throws -> MusicSnapshot {
        let script = #"""
        tell application "Music"
            if not (it is running) then
                return "stopped"
            end if

            set ps to (get player state) as string
            set pos to (get player position)

            try
                set t to current track
                set a to artist of t
                set n to name of t
                set al to album of t
                set d to duration of t
            on error
                set a to ""
                set n to ""
                set al to ""
                set d to 0
            end try

            return ps & "\n" & a & "\n" & n & "\n" & al & "\n" & d & "\n" & pos
        end tell
        """#

        let result = try runAppleScript(script)
        let parts = result.components(separatedBy: "\n")
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

        let track: Track?
        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            track = nil
        } else {
            track = Track(
                artist: artist,
                title: title,
                album: album.isEmpty ? nil : album,
                durationSeconds: duration > 0 ? duration : nil,
                persistentID: 0
            )
        }

        return MusicSnapshot(playbackState: playbackState, playbackTimeSeconds: max(0, position), track: track)
    }

    private func runAppleScript(_ source: String) throws -> String {
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
}
