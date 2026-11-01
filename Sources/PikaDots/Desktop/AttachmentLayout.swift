import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat) {
        let tabX = max(screen.minX + 48, min(window.midX - 191, screen.maxX - 430))
        // Share ONE window-relative anchor. Screen-clamping each panel separately
        // made the input and character drift apart on maximized windows.
        let hasRoomAbove = window.maxY + 72 <= screen.maxY
        let seamY = hasRoomAbove ? window.maxY - 1 : window.maxY - 72
        tab = CGRect(x: tabX, y: seamY - max(0, expandedHeight - 72), width: 430, height: expandedHeight)
        dot = CGRect(x: tabX - 46, y: seamY + 9, width: 48, height: 48)
    }
}
