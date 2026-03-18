import AppKit
import ObjectiveC.runtime
import SwiftUI

@main
struct FastScrobblerMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var appLanguage = AppLanguageStore.shared

    init() {
        _ = AppLanguageStore.shared
    }

    var body: some Scene {
        Settings {
            MacSettingsRootView()
                .environmentObject(AppModel.shared.auth)
                .environmentObject(AppModel.shared.engine)
                .environmentObject(ProPurchaseManager.shared)
                .environmentObject(appLanguage)
        }
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await model.startIfNeeded()
            await ProPurchaseManager.shared.startIfNeeded()
        }

        let rootView = MacPopoverRootView(content: ContentView())
            .environmentObject(model.auth)
            .environmentObject(model.observer)
            .environmentObject(model.engine)
            .environmentObject(model.scrobbleLog)
            .environmentObject(ProPurchaseManager.shared)
            .environmentObject(AppLanguageStore.shared)

        MenuBarController.shared.start(rootView: rootView)
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
            guard selection != oldValue else { return }
            persistSelection()
            Self.apply(selection)
        }
    }

    var locale: Locale {
        selection.locale
    }

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: Keys.selectedLanguage),
           let storedSelection = AppLanguage(rawValue: rawValue) {
            selection = storedSelection
        }

        Self.installBundleOverrideIfNeeded()
        Self.apply(selection)
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

    private static func installBundleOverrideIfNeeded() {
        guard object_getClass(Bundle.main) !== LocalizedBundle.self else { return }
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    private static func apply(_ language: AppLanguage) {
        objc_setAssociatedObject(
            Bundle.main,
            &localizedBundleOverrideKey,
            language.overrideBundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        objc_setAssociatedObject(
            Bundle.main,
            &forcedEnglishLocalizationKey,
            language == .english ? NSNumber(value: true) : nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
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

    fileprivate var overrideBundle: Bundle? {
        switch self {
        case .system, .english:
            return nil
        case .spanish:
            return localizedBundle(named: "es")
        case .french:
            return localizedBundle(named: "fr")
        case .japanese:
            return localizedBundle(named: "ja")
        case .simplifiedChinese:
            return localizedBundle(named: "zh-Hans")
        }
    }

    private func localizedBundle(named languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

private var localizedBundleOverrideKey: UInt8 = 0
private var forcedEnglishLocalizationKey: UInt8 = 0

private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let forcedEnglish = objc_getAssociatedObject(self, &forcedEnglishLocalizationKey) as? NSNumber,
           forcedEnglish.boolValue {
            guard let value, !value.isEmpty else {
                return key
            }
            return value
        }

        if let bundle = objc_getAssociatedObject(self, &localizedBundleOverrideKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }

        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
