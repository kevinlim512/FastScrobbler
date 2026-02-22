import Foundation

struct Track: Codable, Equatable, Hashable {
    var artist: String
    var title: String
    var album: String?
    var durationSeconds: TimeInterval?
    var persistentID: UInt64?
}
