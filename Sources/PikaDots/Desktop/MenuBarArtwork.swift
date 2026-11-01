import AppKit

/// A template face that follows macOS menu-bar tint and accessibility contrast.
enum MenuBarArtwork {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 4, y: 10))
            body.curve(to: NSPoint(x: 5, y: 16), controlPoint1: NSPoint(x: 2, y: 17), controlPoint2: NSPoint(x: 3, y: 18))
            body.curve(to: NSPoint(x: 16, y: 16), controlPoint1: NSPoint(x: 9, y: 14), controlPoint2: NSPoint(x: 12, y: 14))
            body.curve(to: NSPoint(x: 18, y: 10), controlPoint1: NSPoint(x: 19, y: 18), controlPoint2: NSPoint(x: 19, y: 15))
            body.curve(to: NSPoint(x: 11, y: 1), controlPoint1: NSPoint(x: 23, y: 2), controlPoint2: NSPoint(x: 15, y: 1))
            body.curve(to: NSPoint(x: 4, y: 10), controlPoint1: NSPoint(x: 2, y: 1), controlPoint2: NSPoint(x: 1, y: 6))
            body.close(); body.fill()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            for x in [7.0, 13.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 6, width: 2.5, height: 5.5), xRadius: 1.25, yRadius: 1.25).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
