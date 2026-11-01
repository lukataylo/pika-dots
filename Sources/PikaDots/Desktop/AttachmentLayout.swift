import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat) {
        let dotX = max(screen.minX, min(window.midX - 27, screen.maxX - 54))
        let tabX = max(screen.minX, min(dotX + 52, screen.maxX - 240))
        let seamY = window.maxY + 46 <= screen.maxY ? window.maxY - 5 : window.maxY - 46
        tab = CGRect(x: tabX, y: seamY - max(0, expandedHeight - 32), width: 240, height: expandedHeight)
        dot = CGRect(x: dotX, y: seamY, width: 54, height: 46)
    }
}
