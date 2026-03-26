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
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?
    private static let statusBarSymbolNames = [
        "music.note.arrow.trianglehead.clockwise",
        "music.note",
        "music.quarternote.3",
    ]

	    private override init() {
	        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	        popover = NSPopover()

        quitMenu = NSMenu()
        super.init()

        // `NSPopoverBehavior.transient` is brittle for UIElement/menu bar apps across macOS versions.
        // Handle outside-click dismissal ourselves so showing the primary UI stays reliable.
        popover.behavior = .applicationDefined
        popover.delegate = self

        let quitItem = NSMenuItem(title: "Quit FastScrobbler", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitMenu.addItem(quitItem)

	        if let button = statusItem.button {
	            let thickness = NSStatusBar.system.thickness
	            let pointSize = thickness * 0.60
	            let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)

	            let image = Self.makeStatusBarImage(
	                symbolNames: Self.statusBarSymbolNames,
	                symbolConfiguration: symbolConfig,
	                pointSize: pointSize,
	                targetSize: NSSize(width: thickness, height: thickness)
	            )

            if let image {
	                image.isTemplate = true
	                button.image = image
	                button.title = ""
	                button.imagePosition = .imageOnly
            } else {
                button.image = nil
                button.title = "♪"
                button.font = NSFont.systemFont(ofSize: max(13, thickness * 0.62), weight: .regular)
                button.imagePosition = .noImage
            }
	            button.imageScaling = .scaleNone
	            button.toolTip = "FastScrobbler"
	            button.target = self
	            button.action = #selector(statusItemClicked(_:))
	            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
	        }
	    }

    private static func makeStatusBarImage(
        symbolNames: [String],
        symbolConfiguration: NSImage.SymbolConfiguration,
        pointSize: CGFloat,
        targetSize: NSSize
    ) -> NSImage? {
        let resolvedSymbol = symbolNames.lazy.compactMap { symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: "FastScrobbler")?
                .withSymbolConfiguration(symbolConfiguration)
        }.first

        guard let symbol = resolvedSymbol else {
            return nil
        }

        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        func snapToPixel(_ value: CGFloat) -> CGFloat {
            (value * backingScale).rounded() / backingScale
        }

        let drawOrigin = NSPoint(
            x: snapToPixel((targetSize.width - symbol.size.width) / 2.0),
            y: snapToPixel((targetSize.height - symbol.size.height) / 2.0)
        )
        let drawRect = NSRect(origin: drawOrigin, size: symbol.size)

        return NSImage(size: targetSize, flipped: false) { _ in
            symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    func start<Root: View>(rootView: Root) {
        let sizedRoot = AnyView(
            rootView
                .frame(width: 390)
                .frame(height: 620)
        )

        let hosting = NSHostingController(rootView: sizedRoot)
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 390, height: 620)
    }

    var isShown: Bool {
        popover.isShown
    }

    func showPrimaryInterfaceIfNeeded() {
        guard !popover.isShown else { return }
        showPopover()
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
        installDismissMonitors()
	        // Post after presenting so any refresh work can't delay the popover from appearing.
	        DispatchQueue.main.async {
	            NotificationCenter.default.post(name: .fastScrobblerPopoverWillShow, object: nil)
	        }
	    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissMonitors()
    }

    private func installDismissMonitors() {
        if globalDismissMonitor == nil {
            globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closePopoverIfShown()
                }
            }
        }

        if localDismissMonitor == nil {
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self else { return event }
                guard self.popover.isShown else { return event }

                if event.type == .keyDown,
                   event.keyCode == 53 {
                    self.closePopoverIfShown()
                    return nil
                }

                let popoverWindow = self.popover.contentViewController?.view.window
                if event.window !== popoverWindow {
                    self.closePopoverIfShown()
                }
                return event
            }
        }
    }

    private func removeDismissMonitors() {
        if let globalDismissMonitor {
            NSEvent.removeMonitor(globalDismissMonitor)
            self.globalDismissMonitor = nil
        }

        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }
    }

    private func closePopoverIfShown() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
#endif
