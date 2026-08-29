import MediaPlayer
import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

#if os(iOS)
    private var pendingShortcutItem: UIApplicationShortcutItem?
#endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let model = AppModel.shared
        model.startIfNeeded()
        Task { @MainActor in
            await ProPurchaseManager.shared.startIfNeeded()
        }

        let contentView = ContentView()
            .environmentObject(model.auth)
            .environmentObject(model.listenBrainzAuth)
            .environmentObject(model.observer)
            .environmentObject(model.engine)
            .environmentObject(model.scrobbleLog)
            .environmentObject(ProPurchaseManager.shared)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()

#if os(iOS)
        if let shortcutItem = connectionOptions.shortcutItem {
            pendingShortcutItem = shortcutItem
        }
#endif

        Task { @MainActor in
            _ = await model.observer.requestMediaLibraryAuthorizationIfNeeded()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppModel.shared.prepareForBackground()
        BackgroundTaskManager.shared.scheduleAppRefresh()
        BackgroundTaskManager.shared.scheduleProcessingIfNeeded()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppModel.shared.handleWillEnterForeground()
        AppModel.shared.startIfNeeded()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
#if os(iOS)
        guard let windowScene = scene as? UIWindowScene else { return }
        Task { @MainActor in
            await AppModel.shared.handleSceneDidBecomeActive()
            AppReviewManager.shared.recordAppDidBecomeActive(in: windowScene)
            
            setupDynamicShortcutItems()
            if let shortcutItem = pendingShortcutItem {
                _ = handleShortcutItem(shortcutItem)
                pendingShortcutItem = nil
            }
        }
#endif
    }

#if os(iOS)
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = handleShortcutItem(shortcutItem)
        completionHandler(handled)
    }

    private func setupDynamicShortcutItems() {
        var items: [UIApplicationShortcutItem] = []
        
        let sessionKey = LastFMSessionStore.readSessionKey()
        let listenBrainzToken = ListenBrainzSessionStore.readUserToken()
        let hasAccount = sessionKey != nil || (listenBrainzToken != nil && !listenBrainzToken!.isEmpty)
        let hasSeenSetup = UserDefaults.standard.bool(forKey: "FastScrobbler.Setup.hasSeen")
        
        if hasSeenSetup && hasAccount {
            items.append(
                UIApplicationShortcutItem(
                    type: "com.fastscrobbler.scrobbleSong",
                    localizedTitle: NSLocalizedString("Scrobble Song", comment: ""),
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "arrow.triangle.2.circlepath"),
                    userInfo: nil
                )
            )
            items.append(
                UIApplicationShortcutItem(
                    type: "com.fastscrobbler.scanHistory",
                    localizedTitle: NSLocalizedString("Scan History", comment: ""),
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "clock.arrow.circlepath"),
                    userInfo: nil
                )
            )
        }
        
        items.append(
            UIApplicationShortcutItem(
                type: "com.fastscrobbler.help",
                localizedTitle: NSLocalizedString("Help", comment: ""),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "questionmark.circle"),
                userInfo: nil
            )
        )
        
        UIApplication.shared.shortcutItems = items
    }

    private func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        switch shortcutItem.type {
        case "com.fastscrobbler.help":
            AppSettings.requestPendingHelpLaunch()
            NotificationCenter.default.post(name: .openHelp, object: nil)
            return true
        case "com.fastscrobbler.scanHistory":
            let request: AppSettings.PendingListeningHistoryLaunchRequest =
                AppSettings.listeningHistoryRequireConfirmationEnabled() ? .scanAndOpenReview : .scanAndShowResult
            AppSettings.requestPendingListeningHistoryLaunch(request)
            NotificationCenter.default.post(name: .triggerPendingScan, object: nil)
            return true
        case "com.fastscrobbler.scrobbleSong":
            NotificationCenter.default.post(name: .triggerScrobbleSong, object: nil)
            return true
        default:
            return false
        }
    }
#endif
}
