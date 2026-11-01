#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published private(set) var isFullscreenNowPlayingPresented = false

    private init() {}

    func setFullscreenNowPlayingPresented(_ isPresented: Bool) {
        guard isFullscreenNowPlayingPresented != isPresented else { return }
        isFullscreenNowPlayingPresented = isPresented
        notifyOrientationChanged()
        forcePortraitIfStandardPhone()
    }

    func supportedInterfaceOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        // iPad: all orientations
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }

        // iPhone Duo opened (inner screen): min dimension >= 500 pt
        if isPhoneDuoOpened(window: window) {
            return .allButUpsideDown
        }

        // Non-Duo iPhone / iPhone Duo closed: portrait only
        return .portrait
    }

    func isPhoneDuoOpened(window: UIWindow? = nil) -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if let window {
            let bounds = window.bounds
            if min(bounds.width, bounds.height) >= 500 {
                return true
            }
            if window.traitCollection.horizontalSizeClass == .regular && bounds.width <= bounds.height {
                return true
            }
        }
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let bounds = windowScene.screen.bounds
            if min(bounds.width, bounds.height) >= 500 {
                return true
            }
            if let firstWindow = windowScene.windows.first {
                let bounds = firstWindow.bounds
                if min(bounds.width, bounds.height) >= 500 {
                    return true
                }
                if firstWindow.traitCollection.horizontalSizeClass == .regular && bounds.width <= bounds.height {
                    return true
                }
            }
        }
        return false
    }

    private func notifyOrientationChanged() {
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            for window in windowScene.windows {
                var currentController = window.rootViewController
                while let controller = currentController {
                    controller.setNeedsUpdateOfSupportedInterfaceOrientations()
                    currentController = controller.presentedViewController
                }
            }
        }
    }

    private func forcePortraitIfStandardPhone() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        guard !isPhoneDuoOpened(window: windowScene.windows.first) else { return }

        if windowScene.interfaceOrientation.isLandscape {
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            windowScene.requestGeometryUpdate(preferences) { _ in }
        }
    }
}
#endif

