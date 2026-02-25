#if os(macOS)
import Foundation

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
    static func authorizationStatus() -> MPMediaLibraryAuthorizationStatus { .authorized }
}
#endif
