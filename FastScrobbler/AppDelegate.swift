import BackgroundTasks
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Ensure shared objects exist for background task launches (no UI scene).
        _ = AppModel.shared
        Task { @MainActor in
            await ProPurchaseManager.shared.startIfNeeded()
        }
        BackgroundTaskManager.shared.registerIfNeeded()
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            AppModel.shared.prepareForBackground()
        }
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
