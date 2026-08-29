#if os(iOS)
import MediaPlayer
import SwiftUI

struct FullscreenNowPlayingView: View {
    @ObservedObject var auth: LastFMAuthManager
    @ObservedObject var observer: AppleMusicNowPlayingObserver
    @ObservedObject var engine: ScrobbleEngine
    let openURL: OpenURLAction

    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var shuffleMode: MPMusicShuffleMode = MPMusicPlayerController.systemMusicPlayer.shuffleMode
    @State private var repeatMode: MPMusicRepeatMode = MPMusicPlayerController.systemMusicPlayer.repeatMode
    @State private var isScrubbingProgress = false
    @State private var scrubPreviewSeconds: TimeInterval?
    @State private var heldScrubSeconds: TimeInterval?
    @State private var heldScrubClearTask: Task<Void, Never>?
    @State private var idleSleepToken: IdleSleepController.Token?

    private let backgroundColor = Color(uiColor: UIColor(white: 0, alpha: 1.0)).opacity(1)
    private let panelColor = Color(uiColor: UIColor(white: 0.14, alpha: 1.0))
    private let panelBorderColor = Color.white.opacity(0.08)
    private let horizontalPadding: CGFloat = 24

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = fullscreenLayout(in: proxy.size)
                let track = observer.track
                let contentWidth = max(0, proxy.size.width - (horizontalPadding * 2))

                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()

                    backgroundColor
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer(minLength: layout.topContentInset)
                        if layout.showsArtwork {
                            artworkView(side: layout.artworkSide)
                        }
                        Spacer(minLength: 0)

                        VStack(spacing: layout.verticalSpacing) {
                            VStack(spacing: 6) {
                                if let track {
                                    Text(track.title)
                                        .font(.system(size: layout.titleFontSize, weight: .bold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.68)

                                    Text(track.artist)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.78)

                                    if let album = track.album, !album.isEmpty {
                                        Text(album)
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.58))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.78)
                                    }
                                } else {
                                    Text(NSLocalizedString("No track detected.", comment: ""))
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, layout.titleTopPadding)

                            progressSection(for: track)
                            transportControls(width: contentWidth)
                            statusSection

                            Button {
                                if let url = URL(string: "music://") {
                                    openURL(url)
                                }
                            } label: {
                                Label(NSLocalizedString("Open Music App", comment: ""), systemImage: "music.note")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(Color.white.opacity(0.12))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, layout.bottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .tint(.white)
                    .accessibilityLabel(Text(NSLocalizedString("Close Now Playing", comment: "")))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            syncPlaybackModes()
            updateIdleSleepPrevention()
        }
        .onChange(of: observer.track) {
            syncPlaybackModes()
            resetProgressScrubbing()
        }
        .onValueChange(of: scenePhase) { _ in
            updateIdleSleepPrevention()
        }
        .onDisappear {
            resetProgressScrubbing()
            releaseIdleSleepPrevention()
        }
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                backgroundColor
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func artworkView(side: CGFloat) -> some View {
        if let image = nowPlayingArtworkImage(size: CGSize(width: side * 2, height: side * 2)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.32), radius: 30, y: 18)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(panelColor)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(panelBorderColor, lineWidth: 1)

                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(NSLocalizedString("No Artwork", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(width: side, height: side)
        }
    }

    @ViewBuilder
    private func progressSection(for track: Track?) -> some View {
        if let track, let duration = track.durationSeconds, duration > 0 {
            let isInteractive = track.usesFallbackDuration != true
            let playedSeconds = displayedPlayedSeconds(for: track, duration: duration)

            FullscreenPlaybackScrubber(
                duration: duration,
                playedSeconds: playedSeconds,
                thresholdFraction: ProSettings.scrobbleThresholdFraction(),
                isInteractive: isInteractive,
                formatTime: formatTime,
                accessibilityHint: scrubberAccessibilityHint(isInteractive: isInteractive),
                onPreviewChange: { preview in
                    updateScrubPreview(to: preview, duration: duration)
                },
                onScrubEnd: { target in
                    commitScrub(to: target, duration: duration)
                }
            )
        } else {
            EmptyView()
        }
    }

    private func transportControls(width: CGFloat) -> some View {
        let spacing: CGFloat = 14
        let sideButtonSide = min(max((width - (spacing * 4)) / 5, 48), 68)
        let modeButtonSide = min(sideButtonSide * 0.82, 44)
        let primaryWidth = min(max(sideButtonSide * 1.3, 70), 92)
        let iconScale = sideButtonSide / 64

        return HStack(spacing: spacing) {
            modeButton(
                systemImage: "shuffle",
                isActive: shuffleMode != .off,
                side: modeButtonSide,
                action: {
                    let player = MPMusicPlayerController.systemMusicPlayer
                    player.shuffleMode = player.shuffleMode == .off ? .songs : .off
                    syncPlaybackModes()
                }
            )

            transportButton(systemImage: "backward.fill", symbolSize: 28 * iconScale, frameWidth: sideButtonSide, frameHeight: 54) {
                observer.skipToPreviousItem()
            }

            primaryTransportButton(
                systemImage: observer.playbackState == .playing ? "pause.fill" : "play.fill",
                symbolSize: (observer.playbackState == .playing ? 44 : 46) * min(iconScale, 1),
                frameWidth: primaryWidth
            ) {
                observer.togglePlayPause()
            }

            transportButton(systemImage: "forward.fill", symbolSize: 28 * iconScale, frameWidth: sideButtonSide, frameHeight: 54) {
                observer.skipToNextItem()
            }

            modeButton(
                systemImage: repeatSymbolName,
                isActive: repeatMode != .none,
                side: modeButtonSide,
                action: {
                    cycleRepeatMode()
                }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(systemImage: String, symbolSize: CGFloat, frameWidth: CGFloat, frameHeight: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .frame(width: frameWidth, height: frameHeight)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func primaryTransportButton(systemImage: String, symbolSize: CGFloat, frameWidth: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .frame(width: frameWidth, height: 76)
                .contentTransition(.symbolEffect(.replace.downUp))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func modeButton(systemImage: String, isActive: Bool, side: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: min(18, side * 0.36), weight: .semibold))
                .foregroundStyle(isActive ? .black : .white.opacity(0.78))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Color.white : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(isActive ? 0.0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusSection: some View {
        let pills = statusPills
        let fallback = statusFallbackText

        VStack(spacing: 0) {
            if !pills.isEmpty {
                HStack(spacing: 10) {
                    ForEach(pills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(statusPillColor(for: pill).opacity(0.22))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(statusPillColor(for: pill).opacity(0.55), lineWidth: 1)
                            )
                    }
                }
            } else if let fallback {
                Text(fallback)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        .offset(y: -8)
    }

    private var statusPills: [String] {
        statusParts.filter {
            $0 == NSLocalizedString("now playing sent", comment: "") ||
            $0 == NSLocalizedString("scrobbled", comment: "")
        }
    }

    private var statusFallbackText: String? {
        if auth.sessionKey == nil && !listenBrainzAuth.isConnected {
            return NSLocalizedString("Connect Last.fm or ListenBrainz to scrobble.", comment: "")
        }

        if observer.track == nil {
            return engine.statusText
        }

        if statusParts.contains(NSLocalizedString("error scrobbling", comment: "")) {
            return engine.statusText
        }

        return nil
    }

    private var statusParts: [String] {
        engine.statusText
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func nowPlayingArtworkImage(size: CGSize) -> UIImage? {
        MPMusicPlayerController.systemMusicPlayer.nowPlayingItem?.artwork?.image(at: size)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func displayedPlayedSeconds(for track: Track, duration: TimeInterval) -> TimeInterval {
        if isScrubbingProgress, let scrubPreviewSeconds {
            return clampedProgressSeconds(scrubPreviewSeconds, duration: duration)
        }
        if let heldScrubSeconds {
            return clampedProgressSeconds(heldScrubSeconds, duration: duration)
        }
        return livePlayedSeconds(for: track, duration: duration)
    }

    private func livePlayedSeconds(for track: Track, duration: TimeInterval) -> TimeInterval {
        clampedProgressSeconds(engine.liveDisplayedPlayedSeconds(for: track), duration: duration)
    }

    private func clampedProgressSeconds(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, seconds), duration)
    }

    private func updateScrubPreview(to seconds: TimeInterval, duration: TimeInterval) {
        cancelHeldScrubClearTask()
        heldScrubSeconds = nil
        isScrubbingProgress = true
        scrubPreviewSeconds = clampedProgressSeconds(seconds, duration: duration)
    }

    private func commitScrub(to seconds: TimeInterval, duration: TimeInterval) {
        let target = clampedProgressSeconds(seconds, duration: duration)
        observer.seek(toSeconds: target)
        isScrubbingProgress = false
        scrubPreviewSeconds = nil
        heldScrubSeconds = target
        cancelHeldScrubClearTask()
        heldScrubClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            heldScrubSeconds = nil
            heldScrubClearTask = nil
        }
    }

    private func resetProgressScrubbing() {
        isScrubbingProgress = false
        scrubPreviewSeconds = nil
        cancelHeldScrubClearTask()
        heldScrubSeconds = nil
    }

    private func cancelHeldScrubClearTask() {
        heldScrubClearTask?.cancel()
        heldScrubClearTask = nil
    }

    private func scrubberAccessibilityHint(isInteractive: Bool) -> String {
        if isInteractive {
            return NSLocalizedString("Drag to preview and release to seek. Swipe up or down with VoiceOver to adjust by 15 seconds.", comment: "")
        }
        return NSLocalizedString("Seeking is unavailable because Music did not provide an exact track duration.", comment: "")
    }

    private var repeatSymbolName: String {
        switch repeatMode {
        case .one:
            return "repeat.1"
        case .all:
            return "repeat"
        default:
            return "repeat"
        }
    }

    private func cycleRepeatMode() {
        let player = MPMusicPlayerController.systemMusicPlayer
        switch player.repeatMode {
        case .none:
            player.repeatMode = .all
        case .all:
            player.repeatMode = .one
        case .one:
            player.repeatMode = .none
        default:
            player.repeatMode = .none
        }
        syncPlaybackModes()
    }

    private func syncPlaybackModes() {
        let player = MPMusicPlayerController.systemMusicPlayer
        shuffleMode = player.shuffleMode
        repeatMode = player.repeatMode
    }

    private func updateIdleSleepPrevention() {
        guard scenePhase == .active else {
            releaseIdleSleepPrevention()
            return
        }

        if idleSleepToken == nil {
            idleSleepToken = IdleSleepController.shared.acquireIdleTimerDisableToken()
        }
    }

    private func releaseIdleSleepPrevention() {
        idleSleepToken?.release()
        idleSleepToken = nil
    }

    private func statusPillColor(for pill: String) -> Color {
        if pill == NSLocalizedString("scrobbled", comment: "") {
            return Color.green
        }
        return Color.white.opacity(0.5)
    }

    private func fullscreenLayout(in size: CGSize) -> (artworkSide: CGFloat, verticalSpacing: CGFloat, topContentInset: CGFloat, titleTopPadding: CGFloat, titleFontSize: CGFloat, bottomPadding: CGFloat, showsArtwork: Bool) {
        let showsArtwork = !isFourPointSevenInchPhone(size)
        let availableWidth = size.width - (horizontalPadding * 2)
        let bottomPadding: CGFloat = 40
        let bottomControlsHeight: CGFloat = 374
        let availableHeight = size.height - 14 - bottomPadding - bottomControlsHeight
        let artworkSide = min(max(0, availableWidth), max(180, availableHeight))
        let spacing: CGFloat = 22
        let topContentInset: CGFloat = showsArtwork ? 22 : 76
        let titleTopPadding: CGFloat = showsArtwork ? 28 : 0
        let titleFontSize: CGFloat = 31
        return (artworkSide, spacing, topContentInset, titleTopPadding, titleFontSize, bottomPadding, showsArtwork)
    }

    private func isFourPointSevenInchPhone(_ size: CGSize) -> Bool {
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        return shortSide <= 375 && longSide <= 667
    }
}

@MainActor
final class IdleSleepController {
    static let shared = IdleSleepController()

    @MainActor
    final class Token {
        private let identifier: UUID
        private weak var controller: IdleSleepController?
        private var isReleased = false

        fileprivate init(identifier: UUID, controller: IdleSleepController) {
            self.identifier = identifier
            self.controller = controller
        }

        func release() {
            guard !isReleased else { return }
            isReleased = true
            controller?.releaseToken(withID: identifier)
        }
    }

    private var activeTokenIDs: Set<UUID> = []

    private init() {}

    func acquireIdleTimerDisableToken() -> Token {
        let identifier = UUID()
        activeTokenIDs.insert(identifier)
        applyIdleTimerState()
        return Token(identifier: identifier, controller: self)
    }

    fileprivate func releaseToken(withID identifier: UUID) {
        activeTokenIDs.remove(identifier)
        applyIdleTimerState()
    }

    private func applyIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = !activeTokenIDs.isEmpty
    }
}

private struct FullscreenPlaybackScrubber: View {
    private static let accessibilityStepSeconds: TimeInterval = 15

    let duration: TimeInterval
    let playedSeconds: TimeInterval
    let thresholdFraction: Double
    let isInteractive: Bool
    let formatTime: (TimeInterval) -> String
    let accessibilityHint: String
    let onPreviewChange: (TimeInterval) -> Void
    let onScrubEnd: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                if isInteractive {
                    progressBar(width: geo.size.width)
                        .gesture(dragGesture(trackWidth: geo.size.width))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(NSLocalizedString("Playback Position", comment: "")))
                        .accessibilityValue(Text("\(formatTime(playedSeconds)) of \(formatTime(duration))"))
                        .accessibilityHint(Text(accessibilityHint))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                onScrubEnd(min(duration, playedSeconds + Self.accessibilityStepSeconds))
                            case .decrement:
                                onScrubEnd(max(0, playedSeconds - Self.accessibilityStepSeconds))
                            @unknown default:
                                break
                            }
                        }
                } else {
                    progressBar(width: geo.size.width)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(NSLocalizedString("Playback Position", comment: "")))
                        .accessibilityValue(Text("\(formatTime(playedSeconds)) of \(formatTime(duration))"))
                        .accessibilityHint(Text(accessibilityHint))
                }
            }
            .frame(height: 28)

            HStack {
                Text(formatTime(playedSeconds))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    private func progressBar(width: CGFloat) -> some View {
        let progress = duration > 0 ? min(max(playedSeconds / duration, 0), 1) : 0
        let thresholdX = width * CGFloat(thresholdFraction)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(height: 6)

            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: width * CGFloat(progress), height: 6)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 3, height: 12)
                .offset(x: thresholdX - 1.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                onPreviewChange(seconds(for: value.location.x, trackWidth: trackWidth))
            }
            .onEnded { value in
                onScrubEnd(seconds(for: value.location.x, trackWidth: trackWidth))
            }
    }

    private func seconds(for positionX: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        guard duration > 0, trackWidth > 0 else { return 0 }
        let clampedX = min(max(0, positionX), trackWidth)
        return duration * Double(clampedX / trackWidth)
    }
}
#endif
