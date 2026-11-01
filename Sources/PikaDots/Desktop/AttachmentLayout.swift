import AppKit

struct AttachmentLayout {
    let tab: CGRect
    let dot: CGRect
    /// Speech bubble just below the cat, kept on screen.
    let reply: CGRect
    /// True full screen only: the cat hangs upside down, peeking from the top edge. Windows that
    /// merely lack room above keep an upright cat just inside their top edge.
    let peeking: Bool
    /// `anchor` is the cat's position along the window's top edge, 0 = left, 1 = right.
    /// `fullScreen` is the whole display frame, including the menu bar area.
    /// `seat` is the gap between the cat panel's bottom and the drawn paws, so the paws rest on the edge.
    init(window: CGRect, screen: CGRect, expandedHeight: CGFloat, replyHeight: CGFloat = 0, anchor: CGFloat = 0.5, fullScreen: CGRect? = nil, seat: CGFloat = 6, tabWidth: CGFloat = 240) {
        let along = window.minX + window.width * min(1, max(0, anchor)) - 27
        let dotX = max(screen.minX, min(max(window.minX, min(along, window.maxX - 54)), screen.maxX - 54))
        // The purpose pill opens to the right of the cat, or to its left near the screen edge.
        let tabX = dotX + 52 + tabWidth <= screen.maxX ? dotX + 52 : max(screen.minX, dotX + 2 - tabWidth)
        peeking = fullScreen.map { window.minX <= $0.minX + 1 && window.maxX >= $0.maxX - 1 && window.maxY >= $0.maxY - 1 && window.minY <= $0.minY + 1 } ?? false
        // Peeking keeps 12pt of the (upside-down) cat beyond the top edge, as if hanging over it.
        let roomAbove = window.maxY + 46 <= screen.maxY
        // Paws overlap the window's top edge by 1pt, like sitting on it.
        let seamY = peeking ? window.maxY - 34 : roomAbove ? window.maxY + 1 - seat : window.maxY - 46
        let paws = peeking ? seamY : seamY + seat
        tab = CGRect(x: tabX, y: (peeking ? seamY + 1 : paws - 1) - max(0, expandedHeight - 32), width: tabWidth, height: expandedHeight)
        dot = CGRect(x: dotX, y: seamY, width: 54, height: 46)
        let replyX = max(screen.minX, min(dotX, screen.maxX - ReplyCard.width))
        reply = CGRect(x: replyX, y: max(screen.minY, paws - 3 - replyHeight), width: ReplyCard.width, height: replyHeight)
    }
}
