import ActivityKit
import SwiftUI
import WidgetKit

struct ScrobblingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScrobblingActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LockScreenView(
                        state: context.state,
                        contentInsets: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    )
                }
            } compactLeading: {
                Image(systemName: "music.note.arrow.trianglehead.clockwise")
                    .font(.caption2)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "music.note.arrow.trianglehead.clockwise")
                    .font(.caption2)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: ScrobblingActivityAttributes.ContentState
    let contentInsets: EdgeInsets

    init(
        state: ScrobblingActivityAttributes.ContentState,
        contentInsets: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    ) {
        self.state = state
        self.contentInsets = contentInsets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.arrow.trianglehead.clockwise")
                    Text("FastScrobbler")
                }
                .font(.headline)
                Spacer()
            }

            Text(state.status)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let artist = state.artist, let title = state.title {
                Text("\(artist) - \(title)")
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                Text("No track")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("If the track isn’t updating, tap to open the app")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(contentInsets)
    }
}
