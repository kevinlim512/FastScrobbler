import MediaPlayer
import SwiftUI

struct ContentView: View {
    private enum Keys {
        static let hasSeenSetup = "FastScrobbler.Setup.hasSeen"
    }

    @EnvironmentObject private var auth: LastFMAuthManager
    @EnvironmentObject private var observer: AppleMusicNowPlayingObserver
    @EnvironmentObject private var engine: ScrobbleEngine
    @EnvironmentObject private var scrobbleLog: ScrobbleLogStore

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Keys.hasSeenSetup) private var hasSeenSetup = false

    @State private var errorText: String?
    @State private var isShowingSetup = false
    @State private var isShowingHelp = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    trackCard
                    controls
                        .padding(.top, 12)
                    scrobbleLogCard
                    if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("FastScrobbler")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        isShowingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
        }
        .onAppear {
            presentSetupIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            presentSetupIfNeeded()
        }
        .onChange(of: observer.authorizationStatus) { _ in
            presentSetupIfNeeded()
        }
        .fullScreenCover(isPresented: $isShowingSetup) {
            SetupHelpView(mode: .onboarding) {
                guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
                hasSeenSetup = true
                isShowingSetup = false
                Task { @MainActor in
                    await AppModel.shared.startIfNeeded()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingHelp) {
            SetupHelpView(mode: .help) {
                isShowingHelp = false
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationView {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingSettings = false
                            } label: {
                                IOSCloseButtonLabel(style: .plain)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                        }
                    }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last.fm")
                .font(.title2.weight(.semibold))
            if auth.sessionKey != nil {
                Text("Connected").foregroundColor(.green)
            } else {
                Text("Not connected").foregroundColor(.secondary)
            }
            engineStatusText(engine.statusText)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var trackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now Playing")
                .font(.title2.weight(.semibold))
            if let t = observer.track {
                Text("\(t.artist) - \(t.title)")
                if let album = t.album, !album.isEmpty {
                    Text(album).foregroundColor(.secondary)
                }
                if let d = t.durationSeconds {
                    Text("Duration: \(Int(d))s | Playback: \(Int(observer.playbackTimeSeconds))s")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Text("State: \(playbackStateText(observer.playbackState))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("No track detected.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private var controls: some View {
        let actionButtonHeight: CGFloat = 48
        let actionButtonSpacing: CGFloat = 12

        return VStack(spacing: 12) {
            Button {
                if let url = URL(string: "music://") {
                    openURL(url)
                }
            } label: {
                Label("Open Music App", systemImage: "music.note")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)

            HStack(spacing: actionButtonSpacing) {
                Button {
                    engine.setUserPaused(!engine.isUserPaused)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engine.isUserPaused ? "play.fill" : "pause.fill")
                        Text(engine.isUserPaused ? "Resume" : "Pause")
                    }
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(engine.isUserPaused ? .green : .orange)
                .disabled(auth.sessionKey == nil)

                if auth.sessionKey == nil {
                    Button {
                        Task { await connectTapped() }
                    } label: {
                        Label("Log In", systemImage: "person.crop.circle")
                            .font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.blue)
                } else {
                    Button {
                        Task { await engine.scrobbleNow(force: true) }
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "memories.badge.plus")
                            Text("Scrobble Now")
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.purple)
                    .disabled(engine.isUserPaused)
                }
            }

            if auth.sessionKey != nil {
                Button {
                    if let url = auth.profileURL {
                        openURL(url)
                    }
                } label: {
                    Label("View Profile in Last.fm", systemImage: "person.circle")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .disabled(auth.profileURL == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func presentSetupIfNeeded() {
        let mediaAuthorized = (MPMediaLibrary.authorizationStatus() == .authorized)
        let shouldShow = (!hasSeenSetup || !mediaAuthorized)
        guard shouldShow else { return }

        isShowingHelp = false
        isShowingSettings = false
        if !isShowingSetup {
            isShowingSetup = true
        }
    }

    private var scrobbleLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scrobbles")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            if scrobbleLog.entries.isEmpty {
                Text("No scrobbles yet.")
                    .foregroundColor(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let entries = Array(scrobbleLog.entries.prefix(30))
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.track.artist) — \(entry.track.title)")
                                    .font(.subheadline.weight(.semibold))
                                if let album = entry.track.album, !album.isEmpty {
                                    Text(album)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Text(relativeHoursMinutes(from: entry.scrobbledAt, to: context.date))
                                    if entry.source == .backlog {
                                        Text("Backlog")
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private func connectTapped() async {
        errorText = nil
        do {
            try await auth.connect()
            engine.start()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func playbackStateText(_ s: MPMusicPlaybackState) -> String {
        switch s {
        case .stopped: return "stopped"
        case .playing: return "playing"
        case .paused: return "paused"
        case .interrupted: return "interrupted"
        case .seekingForward: return "seeking forward"
        case .seekingBackward: return "seeking backward"
        @unknown default: return "unknown"
        }
    }

    private func relativeHoursMinutes(from date: Date, to now: Date) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        let totalMinutes = Int(delta / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m ago"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours)h ago" }
        return "\(hours)h \(minutes)m ago"
    }

    private func engineStatusText(_ status: String) -> Text {
        let parts = status
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var text = Text("Engine: ")
        for (idx, part) in parts.enumerated() {
            if idx > 0 { text = text + Text(" | ") }
            let segment = Text(part)
            if part == "now playing sent" || part == "scrobbled" {
                text = text + segment.fontWeight(.bold)
            } else {
                text = text + segment
            }
        }
        return text
    }
}

struct IOSCloseButtonLabel: View {
    enum Style {
        case plain
        case floating
    }

    let style: Style

    init(style: Style = .floating) {
        self.style = style
    }

    var body: some View {
        let icon = Image(systemName: "xmark")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)

        switch style {
        case .plain:
            icon
        case .floating:
            icon
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .contentShape(Circle())
        }
    }
}
