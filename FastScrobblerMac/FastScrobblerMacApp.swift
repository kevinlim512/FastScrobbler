import AppKit
import FirebaseCore
import SwiftUI

@main
struct FastScrobblerMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var appLanguage = AppLanguageStore.shared

    init() {
        Self.configureFirebaseIfPossible()
        _ = AppLanguageStore.shared
    }

    var body: some Scene {
        Settings {
            MacSettingsRootView()
                .environmentObject(AppModel.shared.auth)
                .environmentObject(AppModel.shared.listenBrainzAuth)
                .environmentObject(AppModel.shared.engine)
                .environmentObject(ProPurchaseManager.shared)
                .environmentObject(appLanguage)
        }

    }
}

private extension FastScrobblerMacApp {
    static var didConfigureFirebase = false

    static func configureFirebaseIfPossible() {
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

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = MacPopoverRootView(content: ContentView())
            .environmentObject(model.auth)
            .environmentObject(model.listenBrainzAuth)
            .environmentObject(model.observer)
            .environmentObject(model.engine)
            .environmentObject(model.scrobbleLog)
            .environmentObject(model.permissions)
            .environmentObject(ProPurchaseManager.shared)
            .environmentObject(AppLanguageStore.shared)

        MenuBarController.shared.start(rootView: rootView)

        Task { @MainActor in
            model.permissions.startMonitoring(observer: model.observer)
            model.startIfNeeded()
            await ProPurchaseManager.shared.startIfNeeded()
            await ICloudSyncCoordinator.shared.startIfNeeded()
        }

        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in
                await AppModel.shared.periodicFlush()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async {
            MenuBarController.shared.showPrimaryInterfaceIfNeeded()
        }
    }

}

private struct MacPopoverRootView<Content: View>: View {
    let content: Content

    @EnvironmentObject private var appLanguage: AppLanguageStore

    var body: some View {
        content
            .environment(\.locale, appLanguage.locale)
    }
}

private struct MacSettingsRootView: View {
    @EnvironmentObject private var appLanguage: AppLanguageStore

    var body: some View {
        SettingsView()
            .environment(\.locale, appLanguage.locale)
            .frame(minWidth: 640, minHeight: 620)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    private enum Keys {
        static let selectedLanguage = "FastScrobbler.AppLanguage.selected"
    }

    static let shared = AppLanguageStore()

    @Published var selection: AppLanguage = .system {
        didSet {
            guard selection != oldValue, !isInitializing else { return }
            persistSelection()
            Self.relaunchApp()
        }
    }

    var locale: Locale {
        selection.locale
    }

    private var isInitializing = true

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: Keys.selectedLanguage),
           let storedSelection = AppLanguage(rawValue: rawValue) {
            selection = storedSelection
        }

        isInitializing = false
    }

    private func persistSelection() {
        if selection == .system {
            UserDefaults.standard.removeObject(forKey: Keys.selectedLanguage)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set(selection.rawValue, forKey: Keys.selectedLanguage)
            UserDefaults.standard.set([selection.locale.identifier], forKey: "AppleLanguages")
        }
    }

    private static func relaunchApp() {
        let bundleURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
        NSApp.terminate(nil)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish
    case french
    case japanese
    case simplifiedChinese

    var id: String {
        rawValue
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .spanish:
            return Locale(identifier: "es")
        case .french:
            return Locale(identifier: "fr")
        case .japanese:
            return Locale(identifier: "ja")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var title: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "")
        case .english:
            return "English"
        case .spanish:
            return "Espanol"
        case .french:
            return "Francais"
        case .japanese:
            return "日本語"
        case .simplifiedChinese:
            return "简体中文"
        }
    }
}
