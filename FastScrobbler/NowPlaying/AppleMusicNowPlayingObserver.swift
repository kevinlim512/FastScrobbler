import Foundation
import MediaPlayer

@MainActor
final class AppleMusicNowPlayingObserver: ObservableObject {
    enum ObserverError: Error, LocalizedError {
        case mediaLibraryDenied
        case noNowPlayingItem

        var errorDescription: String? {
            switch self {
            case .mediaLibraryDenied:
                return "Media Library access is required to read Apple Music now-playing metadata."
            case .noNowPlayingItem:
                return "No now-playing item found."
            }
        }
    }

    @Published private(set) var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published private(set) var track: Track?
    @Published private(set) var playbackState: MPMusicPlaybackState = .stopped
    @Published private(set) var playbackTimeSeconds: TimeInterval = 0

    @Published private(set) var isRunning = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var timer: Timer?

    init() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
    }

    func refreshOnceIfAuthorized() {
        let status = MPMediaLibrary.authorizationStatus()
        authorizationStatus = status
        guard status == .authorized else {
            track = nil
            playbackState = .stopped
            playbackTimeSeconds = 0
            return
        }
        refreshFromPlayer()
    }

    func start() async throws {
        let currentStatus = MPMediaLibrary.authorizationStatus()
        authorizationStatus = currentStatus

        if isRunning {
            guard currentStatus == .authorized else {
                stop()
                track = nil
                playbackState = .stopped
                playbackTimeSeconds = 0
                throw ObserverError.mediaLibraryDenied
            }
            refreshFromPlayer()
            return
        }

        let status: MPMediaLibraryAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await withCheckedContinuation { cont in
                MPMediaLibrary.requestAuthorization { s in
                    cont.resume(returning: s)
                }
            }
        } else {
            status = currentStatus
        }
        authorizationStatus = status
        guard status == .authorized else { throw ObserverError.mediaLibraryDenied }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )

        player.beginGeneratingPlaybackNotifications()
        refreshFromPlayer()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromPlayer()
            }
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        timer?.invalidate()
        timer = nil
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func nowPlayingItemChanged() {
        refreshFromPlayer()
    }

    @objc private func playbackStateChanged() {
        refreshFromPlayer()
    }

    private func refreshFromPlayer() {
        playbackState = player.playbackState
        playbackTimeSeconds = max(0, player.currentPlaybackTime)

        guard let item = player.nowPlayingItem else {
            track = nil
            return
        }

        let artist = item.artist ?? ""
        let title = item.title ?? ""
        let album = item.albumTitle
        let duration = item.playbackDuration
        let pid = item.persistentID

        if artist.isEmpty || title.isEmpty {
            track = nil
            return
        }

        track = Track(
            artist: artist,
            title: title,
            album: album,
            durationSeconds: duration > 0 ? duration : nil,
            persistentID: pid
        )
    }
}
