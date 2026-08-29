import BackgroundTasks
import FirebaseCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var didConfigureFirebase = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureFirebaseIfPossible()

        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0

        AppSettings.migrateLegacyAppGroupSettingsIfNeeded()
        AppSettings.seedScrobbleAppleMusicAPIEnabledIfNeeded()
        AppSettings.seedScrobbleOnlyNonLibraryAppleMusicAPITracksIfNeeded()
        AppSettings.removeLegacyListeningHistoryScrobblingToggleIfNeeded()
        ProSettings.migrateLegacyAppGroupSettingsIfNeeded()

        // Ensure shared objects exist for background task launches (no UI scene).
        _ = AppModel.shared
        Task { @MainActor in
            await ICloudSyncCoordinator.shared.startIfNeeded()
            await ProPurchaseManager.shared.startIfNeeded()
        }
        BackgroundTaskManager.shared.registerIfNeeded()
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                await LiveActivityManager.shared.stop()
            }
        }
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

    private func configureFirebaseIfPossible() {
        guard !didConfigureFirebase else { return }
        guard let configPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath),
              let googleAppID = config["GOOGLE_APP_ID"] as? String,
              !googleAppID.hasPrefix("REPLACE_") else {
            assertionFailure("Missing valid GoogleService-Info.plist for Firebase.")
            return
        }

        FirebaseApp.configure()
        didConfigureFirebase = true
    }
}
