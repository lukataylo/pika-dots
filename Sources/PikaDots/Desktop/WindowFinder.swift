import AppKit

struct WindowFinder {
    static func windows() -> [WindowContext] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw), bounds.width > 80, bounds.height > 60,
                  let id = info[kCGWindowNumber as String] as? UInt32 else { return nil }
            return WindowContext(windowID: id,
                appName: info[kCGWindowOwnerName as String] as? String ?? "Application",
                title: info[kCGWindowName as String] as? String ?? "", bounds: bounds, ownerPID: pid)
        }
    }
    static func appRect(_ bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: CGDisplayBounds(CGMainDisplayID()).height - bounds.maxY, width: bounds.width, height: bounds.height)
    }
    static func window(at point: NSPoint) -> WindowContext? {
        windows().first { appRect($0.bounds).contains(point) }
    }

}

@MainActor
final class DotDragView: NSView {
    let color: NSColor
    var artwork: NSImage?
    var onDrop: ((NSPoint) -> Void)?
    var onClick: (() -> Void)?
    private var didDrag = false
    private var ghost: NSPanel?
    private var ghostDot: DotDragView?
    private var animation: Task<Void, Never>?
    private let birth = Date()
    private var lastPoint = NSPoint.zero
    private var stretch: CGFloat = 1
    private var angle: CGFloat = 0
    private var isGhost = false

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        setAccessibilityLabel("Draggable companion")
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        animation?.cancel()
        guard window != nil else { return }
        animation = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(24)) } catch { return }
                guard let self else { return }
                guard self.window?.occlusionState.contains(.visible) == true else { continue }
                self.stretch += (1 - self.stretch) * 0.12
                self.needsDisplay = true
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let time = Date().timeIntervalSince(birth)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let landing = reduced || isGhost ? 1 : 1 - exp(-time * 9) * cos(time * 19) * 0.24
        let breathe = reduced || isGhost ? 1 : 1 + sin(time * 2.4) * 0.025
        let blink = !isGhost && time.truncatingRemainder(dividingBy: 4.3) > 4.12
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byRadians: angle)
        let sizeScale: CGFloat = isGhost ? 40.0 / 48 : min(bounds.width, bounds.height) / 48
        transform.scaleX(by: sizeScale, yBy: sizeScale)
        transform.scaleX(by: stretch * landing * breathe, yBy: landing / sqrt(stretch) / breathe)
        transform.concat()
        if let artwork {
            artwork.draw(in: NSRect(x: -24, y: -24, width: 48, height: 48), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let body = NSBezierPath()
        body.move(to: NSPoint(x: -16, y: 7))
        body.curve(to: NSPoint(x: -14, y: 20), controlPoint1: NSPoint(x: -20, y: 26), controlPoint2: NSPoint(x: -16, y: 25))
        body.curve(to: NSPoint(x: 13, y: 20), controlPoint1: NSPoint(x: -5, y: 16), controlPoint2: NSPoint(x: 5, y: 16))
        body.curve(to: NSPoint(x: 17, y: 7), controlPoint1: NSPoint(x: 19, y: 27), controlPoint2: NSPoint(x: 19, y: 17))
        body.curve(to: NSPoint(x: 0, y: -19), controlPoint1: NSPoint(x: 25, y: -7), controlPoint2: NSPoint(x: 15, y: -19))
        body.curve(to: NSPoint(x: -16, y: 7), controlPoint1: NSPoint(x: -21, y: -19), controlPoint2: NSPoint(x: -24, y: -2))
        body.close()
        color.setFill(); body.fill()
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: NSRect(x: -12, y: 6, width: 12, height: 5)).fill()
        NSColor.white.setFill()
        for x in [-8.0, 4.0] {
            NSBezierPath(roundedRect: NSRect(x: x, y: blink ? -1 : -5, width: 4.5, height: blink ? 2 : 11), xRadius: 2.25, yRadius: 2.25).fill()
        }
        NSColor.systemPink.withAlphaComponent(0.35).setFill()
        for x in [-14.0, 10.0] { NSBezierPath(ovalIn: NSRect(x: x, y: -8, width: 5, height: 3)).fill() }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onClick?(); return onClick != nil }
    override func mouseDown(with event: NSEvent) {
        didDrag = false
        lastPoint = NSEvent.mouseLocation
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 110, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = .statusBar; panel.ignoresMouseEvents = true
        let dot = DotDragView(color: color); dot.isGhost = true; dot.artwork = artwork
        panel.contentView = dot
        ghost = panel; ghostDot = dot
    }
    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        let p = NSEvent.mouseLocation
        let dx = p.x - lastPoint.x, dy = p.y - lastPoint.y
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            ghostDot?.stretch = min(2.1, 1 + hypot(dx, dy) / 35)
            if hypot(dx, dy) > 1 { ghostDot?.angle = atan2(dy, dx) }
        }
        ghost?.setFrameOrigin(NSPoint(x: p.x - 55, y: p.y - 55))
        ghost?.orderFrontRegardless()
        lastPoint = p
    }
    override func mouseUp(with event: NSEvent) {
        ghost?.close(); ghost = nil; ghostDot = nil
        // Defer: a drop can close the panel that is still dispatching this event.
        let point = NSEvent.mouseLocation, drop = onDrop, click = onClick, dragged = didDrag
        DispatchQueue.main.async { if dragged { drop?(point) } else { click?() } }
    }
}
