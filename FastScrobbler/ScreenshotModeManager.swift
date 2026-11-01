#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class ScreenshotModeManager: ObservableObject {
    static let shared = ScreenshotModeManager()

    @Published var isEnabled: Bool = false

    static let songTitle = "TYRANT"
    static let artistName = "Beyoncé & Dolly Parton"
    static let albumTitle = "COWBOY CARTER"
    static let durationSeconds: TimeInterval = 288 // 4:48
    static let playbackSeconds: TimeInterval = 168 // 2:48

    let mockTrack = Track(
        artist: artistName,
        title: songTitle,
        album: albumTitle,
        durationSeconds: durationSeconds
    )

    var statusPills: [String] {
        [
            NSLocalizedString("now playing sent", comment: ""),
            NSLocalizedString("scrobbled", comment: "")
        ]
    }

    var serviceStatusPills: [ScrobbleEngine.ServiceStatusPill] {
        [
            ScrobbleEngine.ServiceStatusPill(
                text: NSLocalizedString("now playing sent", comment: ""),
                style: .neutral
            ),
            ScrobbleEngine.ServiceStatusPill(
                text: NSLocalizedString("scrobbled", comment: ""),
                style: .success
            )
        ]
    }

    var artworkImage: UIImage? {
        // Compile-time source tree resolution so Simulator can read host files
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectsDir = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        let candidateURLs: [URL] = [
            projectsDir.appendingPathComponent("FastScrobbler/Resources/album_cover.jpg"),
            projectsDir.appendingPathComponent("FastScrobbler/FastScrobbler/Resources/album_cover.jpg"),
            URL(fileURLWithPath: "../FastScrobbler/Resources/album_cover.jpg"),
            URL(fileURLWithPath: "../FastScrobbler/FastScrobbler/Resources/album_cover.jpg"),
            URL(fileURLWithPath: "/Users/kevin/Projects/FastScrobbler/FastScrobbler/Resources/album_cover.jpg"),
            URL(fileURLWithPath: "/Users/kevin/Projects/FastScrobbler/Resources/album_cover.jpg")
        ]

        for url in candidateURLs {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }

        if let bundleURL = Bundle.main.url(forResource: "album_cover", withExtension: "jpg"),
           let data = try? Data(contentsOf: bundleURL),
           let image = UIImage(data: data) {
            return image
        }

        return nil
    }

    private init() {}
}
#endif

