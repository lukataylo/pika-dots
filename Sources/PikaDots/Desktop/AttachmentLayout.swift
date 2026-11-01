import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat) {
        let tabX = max(screen.minX + 52, min(window.midX - 124, screen.maxX - 280))
        // Share ONE window-relative anchor. Screen-clamping each panel separately
        // made the input and character drift apart on maximized windows.
        let hasRoomAbove = window.maxY + 46 <= screen.maxY
        let seamY = hasRoomAbove ? window.maxY - 5 : window.maxY - 46
        tab = CGRect(x: tabX, y: seamY - max(0, expandedHeight - 40), width: 280, height: expandedHeight)
        dot = CGRect(x: tabX - 52, y: seamY, width: 54, height: 46)
    }
}
