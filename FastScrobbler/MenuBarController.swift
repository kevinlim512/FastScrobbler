	#if os(macOS)
	import AppKit
	import SwiftUI

	extension Notification.Name {
	    static let fastScrobblerPopoverWillShow = Notification.Name("FastScrobbler.popover.willShow")
	}

	@MainActor
	final class MenuBarController: NSObject, NSPopoverDelegate {
	    static let shared = MenuBarController()

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let quitMenu: NSMenu

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        quitMenu = NSMenu()
        super.init()

        popover.behavior = .transient
        popover.delegate = self

        let quitItem = NSMenuItem(title: "Quit FastScrobbler", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitMenu.addItem(quitItem)

        if let button = statusItem.button {
            let baseImage = NSImage(
                systemSymbolName: "music.note.arrow.trianglehead.clockwise",
                accessibilityDescription: "FastScrobbler"
            )
            let symbolConfig = NSImage.SymbolConfiguration(
                pointSize: NSStatusBar.system.thickness * 0.60,
                weight: .regular
            )
            let image = baseImage?.withSymbolConfiguration(symbolConfig)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func start<Root: View>(rootView: Root) {
        let sizedRoot = AnyView(
            rootView
                .frame(width: 390)
                .frame(minHeight: 620, idealHeight: 820, maxHeight: 880)
        )

        let hosting = NSHostingController(rootView: sizedRoot)
        popover.contentViewController = hosting
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            statusItem.menu = quitMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        togglePopover(sender)
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

	    private func showPopover() {
	        guard let button = statusItem.button else { return }
	        NSApp.activate(ignoringOtherApps: true)
	        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
	        // Post after presenting so any refresh work can't delay the popover from appearing.
	        DispatchQueue.main.async {
	            NotificationCenter.default.post(name: .fastScrobblerPopoverWillShow, object: nil)
	        }
	    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif
