import AppKit
import SwiftUI

@main
struct FastScrobblerMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        // No windows; status bar popover only.
        Settings {
            EmptyView()
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

        let rootView = ContentView()
            .environmentObject(model.auth)
            .environmentObject(model.observer)
            .environmentObject(model.engine)
            .environmentObject(model.scrobbleLog)
            .environmentObject(ProPurchaseManager.shared)

        MenuBarController.shared.start(rootView: rootView)
    }
}
