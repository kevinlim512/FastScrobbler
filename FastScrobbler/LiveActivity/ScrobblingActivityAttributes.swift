import ActivityKit
import Foundation

// App-side attributes used for Live Activities.
// Note: to *display* a Live Activity on the Lock Screen/Dynamic Island, you'll also need a Widget extension
// that provides an `ActivityConfiguration` for these attributes.
struct ScrobblingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var artist: String?
        var title: String?
        var lastEventAt: Date
        var isActivelyScrobbling: Bool
    }

    var appName: String = "FastScrobbler"
}
