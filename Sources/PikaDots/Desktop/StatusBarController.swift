import SwiftUI

/// A clear panel avoids the opaque system popover behind the companion shelf.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    private let app = AppController()
    private var item: NSStatusItem?
    private var shelf: CompanionPanel?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 25)
        item.button?.image = MenuBarArtwork.image
        item.button?.toolTip = "Pika Dots"
        item.button?.target = self
        item.button?.action = #selector(toggleShelf)
        self.item = item
        let shelf = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 178, height: 68), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shelf.backgroundColor = .clear; shelf.isOpaque = false; shelf.hasShadow = false
        shelf.level = .popUpMenu; shelf.isReleasedWhenClosed = false
        shelf.contentView = NSHostingView(rootView: RosterView(app: app))
        self.shelf = shelf
        app.onAttachment = { [weak shelf] in shelf?.orderOut(nil) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak shelf] _ in
            Task { @MainActor in shelf?.orderOut(nil) }
        }
    }

    @objc private func toggleShelf() {
        guard let shelf, let button = item?.button, let window = button.window else { return }
        if shelf.isVisible { shelf.orderOut(nil); return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        shelf.setFrameOrigin(NSPoint(x: max(screen.minX, min(rect.midX - 89, screen.maxX - 178)), y: rect.minY - 68))
        shelf.orderFrontRegardless()
    }
}
