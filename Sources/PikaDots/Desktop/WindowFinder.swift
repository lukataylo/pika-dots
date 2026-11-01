import AppKit

struct WindowFinder {
    static func window(at point: NSPoint) -> WindowContext? {
        // CG windows use a top-left origin relative to the primary display.
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw), bounds.contains(cgPoint),
                  let id = info[kCGWindowNumber as String] as? UInt32 else { continue }
            return WindowContext(windowID: id,
                appName: info[kCGWindowOwnerName as String] as? String ?? "Application",
                title: info[kCGWindowName as String] as? String ?? "", bounds: bounds)
        }
        return nil
    }
}

final class DotDragView: NSView {
    let color: NSColor
    var onDrop: ((NSPoint) -> Void)?
    private var ghost: NSPanel?
    init(color: NSColor) { self.color = color; super.init(frame: NSRect(x: 0, y: 0, width: 48, height: 48)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 17, yRadius: 17).fill()
        NSColor.white.setFill()
        for x in [19.0, 29.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 21, width: 4, height: 10), xRadius: 2, yRadius: 2).fill() }
    }
    override func mouseDown(with event: NSEvent) {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.ignoresMouseEvents = true
        panel.contentView = DotDragView(color: color)
        ghost = panel
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        ghost?.setFrameOrigin(NSPoint(x: p.x - 24, y: p.y - 24)); ghost?.orderFrontRegardless()
    }
    override func mouseUp(with event: NSEvent) {
        ghost?.close(); ghost = nil
        onDrop?(NSEvent.mouseLocation)
    }
}
