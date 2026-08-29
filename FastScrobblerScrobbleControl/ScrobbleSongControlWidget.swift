import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
@main
struct ScrobbleSongControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlWidgetStatusKind.scrobbleSong.rawValue) {
            ControlWidgetButton(action: ScrobbleSongIntent()) {
                Label("Scrobble Song", systemImage: "memories.badge.plus")
            }
            .tint(.purple)
        }
        .displayName("Scrobble Song")
        .description("Scrobble the current track.")
    }
}
