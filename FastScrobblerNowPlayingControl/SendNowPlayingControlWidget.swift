import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
@main
struct SendNowPlayingControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kevin.FastScrobbler.control.sendNowPlaying") {
            ControlWidgetButton(action: SendNowPlayingIntent()) {
                Label("Send Now Playing", systemImage: "memories")
            }
            .tint(.red)
        }
        .displayName("Send Now Playing")
        .description("Send the current track to Last.fm as now playing.")
    }
}
