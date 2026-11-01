import SwiftUI

/// A clear panel avoids the opaque system popover behind the companion shelf.
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    private let app = AppController()
    private var item: NSStatusItem?
    private var shelf: CompanionPanel?
    private var clickMonitor: Any?
    private var editor: NSWindow?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 25)
        item.button?.image = MenuBarArtwork.image
        item.button?.toolTip = "Pika Dots"
        item.button?.target = self
        item.button?.action = #selector(toggleShelf)
        self.item = item
        let shelf = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 178, height: 98), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shelf.backgroundColor = .clear; shelf.isOpaque = false; shelf.hasShadow = true
        shelf.level = .popUpMenu; shelf.isReleasedWhenClosed = false
        shelf.contentView = NSHostingView(rootView: RosterView(app: app))
        self.shelf = shelf
        app.onSettings = { [weak self] in self?.showSettings() }
        app.onManage = { [weak self] in self?.showEditor() }
        if !UserDefaults.standard.bool(forKey: "hasSeenCompanionEditor") || LocalConfiguration.value("OPENAI_API_KEY") == nil {
            showEditor()
            UserDefaults.standard.set(true, forKey: "hasSeenCompanionEditor")
        }
        app.onAttachment = { [weak shelf] in shelf?.orderOut(nil) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak shelf] _ in
            Task { @MainActor in shelf?.orderOut(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return false
    }

    private func showSettings() {
        shelf?.orderOut(nil)
        if settings == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 488, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Pika Dots · Settings"; window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: PermissionsView(manage: { [weak self] in self?.showEditor() }, showShelf: { [weak self] in
                self?.settings?.orderOut(nil); self?.shelf?.orderOut(nil); self?.toggleShelf(); self?.shelf?.makeKeyAndOrderFront(nil)
            }, testNotification: { [weak self] in self?.app.testNotification() }))
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }

    private func showEditor() {
        shelf?.orderOut(nil)
        if editor == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 730, height: 630), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Pika Dots · Companions & Setup"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CompanionEditor(app: app))
            window.center(); editor = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleShelf() {
        guard let shelf, let button = item?.button, let window = button.window else { return }
        if shelf.isVisible { shelf.orderOut(nil); return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let width = min(screen.width, CGFloat(app.agents.count) * 62 + 110)
        shelf.setContentSize(NSSize(width: width, height: 98))
        shelf.setFrameOrigin(NSPoint(x: max(screen.minX, min(rect.midX - width / 2, screen.maxX - width)), y: rect.minY - 98))
        shelf.orderFrontRegardless()
    }
}
