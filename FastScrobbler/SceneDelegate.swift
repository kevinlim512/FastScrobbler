import MediaPlayer
import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let model = AppModel.shared
        Task { @MainActor in
            await model.startIfNeeded()
            await ProPurchaseManager.shared.startIfNeeded()
        }

        let contentView = ContentView()
            .environmentObject(model.auth)
            .environmentObject(model.observer)
            .environmentObject(model.engine)
            .environmentObject(model.scrobbleLog)
            .environmentObject(ProPurchaseManager.shared)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()

        Task { @MainActor in
            _ = await model.observer.requestMediaLibraryAuthorizationIfNeeded()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Task { @MainActor in
            AppModel.shared.prepareForBackground()
        }
        BackgroundTaskManager.shared.scheduleAppRefresh()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Task { @MainActor in
            await AppModel.shared.startIfNeeded()
        }
    }
}
