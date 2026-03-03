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
    private static let statusBarSymbolName = "music.note.arrow.trianglehead.clockwise"

	    private override init() {
	        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
	        popover = NSPopover()

        quitMenu = NSMenu()
        super.init()

        popover.behavior = .transient
        popover.delegate = self

        let quitItem = NSMenuItem(title: "Quit FastScrobbler", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitMenu.addItem(quitItem)

	        if let button = statusItem.button {
	            let thickness = NSStatusBar.system.thickness
	            let pointSize = thickness * 0.60
	            let symbolConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)

	            let image = Self.makeStatusBarImage(
	                symbolName: Self.statusBarSymbolName,
	                symbolConfiguration: symbolConfig,
	                targetSize: NSSize(width: thickness, height: thickness)
	            )

	            image?.isTemplate = true
	            button.image = image
	            button.imagePosition = .imageOnly
	            button.imageScaling = .scaleNone
	            button.toolTip = "FastScrobbler"
	            button.target = self
	            button.action = #selector(statusItemClicked(_:))
	            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
	        }
	    }

    private static func makeStatusBarImage(
        symbolName: String,
        symbolConfiguration: NSImage.SymbolConfiguration,
        targetSize: NSSize
    ) -> NSImage? {
        guard
            let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FastScrobbler")?
                .withSymbolConfiguration(symbolConfiguration)
        else {
            return nil
        }

        let verticalOffset = measuredVerticalOpticalCenterOffset(for: symbol)
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        func snapToPixel(_ value: CGFloat) -> CGFloat {
            (value * backingScale).rounded() / backingScale
        }

        let drawOrigin = NSPoint(
            x: snapToPixel((targetSize.width - symbol.size.width) / 2.0),
            y: snapToPixel((targetSize.height - symbol.size.height) / 2.0 + verticalOffset)
        )
        let drawRect = NSRect(origin: drawOrigin, size: symbol.size)

        // Use a drawing handler so the symbol remains resolution-independent when rendered (e.g., Retina).
        return NSImage(size: targetSize, flipped: false) { _ in
            symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private static func measuredVerticalOpticalCenterOffset(for image: NSImage) -> CGFloat {
        // SF Symbols can have asymmetric padding inside their bounding box, which can make them appear
        // visually "low" in the menu bar. NSSymbolImageRep exposes an alignment rect the app can use to nudge
        // the glyph so its alignment center sits at the image's vertical center.
        guard
            let rep = image.representations.first,
            let value = (rep as AnyObject).value(forKey: "alignmentRect") as? NSValue
        else {
            return 0
        }

        let alignmentRect = value.rectValue
        let imageCenterY = image.size.height / 2.0
        let alignmentCenterY = alignmentRect.midY
        let rawOffset = imageCenterY - alignmentCenterY

        // Round to half-point increments and clamp to a small, safe adjustment range.
        let rounded = (rawOffset * 2.0).rounded() / 2.0
        return min(2.0, max(-2.0, rounded))
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
