#if os(macOS)
import Foundation
import MusicKit

enum MPMediaLibraryAuthorizationStatus: Int {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum MPMusicPlaybackState: Int {
    case stopped
    case playing
    case paused
    case interrupted
    case seekingForward
    case seekingBackward
}

enum MPMediaLibrary {
    private static func map(_ status: MusicAuthorization.Status) -> MPMediaLibraryAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    static func authorizationStatus() -> MPMediaLibraryAuthorizationStatus {
        map(MusicAuthorization.currentStatus)
    }

    static func requestAuthorization(_ handler: @escaping (MPMediaLibraryAuthorizationStatus) -> Void) {
        Task { @MainActor in
            let status = await MusicAuthorization.request()
            handler(map(status))
        }
    }
}
#endif
