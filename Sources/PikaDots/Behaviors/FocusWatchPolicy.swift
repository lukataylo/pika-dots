import AppKit

enum FocusWatchPolicy {
    /// Lower-cased title without a trailing browser name or a leading unread count such as "(3) ".
    static func normalizedTitle(_ title: String) -> String {
        var title = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for browser in ["google chrome", "chrome", "safari", "dia", "arc", "firefox", "brave", "microsoft edge"] {
            for dash in [" - ", " – ", " — "] {
                if title.hasSuffix(dash + browser) { title = String(title.dropLast((dash + browser).count)) }
            }
        }
        if title.hasPrefix("("), let close = title.firstIndex(of: ")"), title[title.index(after: title.startIndex)..<close].allSatisfy(\.isNumber) {
            title = String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
    static func isYouTube(_ title: String) -> Bool {
        let title = normalizedTitle(title)
        return title == "youtube" || title.hasSuffix(" - youtube") || title.hasSuffix(" – youtube") || title.hasSuffix(" — youtube") || title.hasPrefix("https://www.youtube.com/") || title.hasPrefix("https://youtube.com/") || title.hasPrefix("youtube.com/")
    }
    static func canCheck(_ target: WindowContext, windows: [WindowContext], frontPID: pid_t?) -> Bool {
        guard frontPID == target.ownerPID, windows.contains(where: { $0.windowID == target.windowID && $0.ownerPID == target.ownerPID }) else { return false }
        // Autocomplete and transient browser popups are not content windows.
        let content = windows.first { $0.ownerPID == target.ownerPID && $0.bounds.width >= 300 && $0.bounds.height >= 180 && $0.bounds.width * $0.bounds.height >= target.bounds.width * target.bounds.height * 0.5 && !$0.title.isEmpty }
        return content == nil || content?.windowID == target.windowID
    }
}
