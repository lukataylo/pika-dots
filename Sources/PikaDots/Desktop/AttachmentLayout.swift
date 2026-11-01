import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat) {
        let x = max(screen.minX, min(window.midX - 215, screen.maxX - 430))
        tab = CGRect(x: x, y: max(screen.minY, min(window.maxY - 1, screen.maxY - expandedHeight)), width: 430, height: expandedHeight)
        dot = CGRect(x: min(screen.maxX - 48, max(screen.minX, window.midX - 24)), y: min(window.maxY - 12, screen.maxY - 48), width: 48, height: 48)
    }
}
