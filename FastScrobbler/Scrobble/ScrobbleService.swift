import Foundation

enum ScrobbleService: String, Codable, Hashable, CaseIterable, Sendable {
    case lastfm
    case listenbrainz

    var displayName: String {
        switch self {
        case .lastfm:
            return "Last.fm"
        case .listenbrainz:
            return "ListenBrainz"
        }
    }
}
