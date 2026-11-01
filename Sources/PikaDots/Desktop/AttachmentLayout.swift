import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat) {
        let tabX = max(screen.minX + 34, min(window.midX - 124, screen.maxX - 280))
        // Share ONE window-relative anchor. Screen-clamping each panel separately
        // made the input and character drift apart on maximized windows.
        let hasRoomAbove = window.maxY + 40 <= screen.maxY
        let seamY = hasRoomAbove ? window.maxY - 5 : window.maxY - 40
        tab = CGRect(x: tabX, y: seamY - max(0, expandedHeight - 40), width: 280, height: expandedHeight)
        dot = CGRect(x: tabX - 32, y: seamY, width: 34, height: 26)
    }
}
