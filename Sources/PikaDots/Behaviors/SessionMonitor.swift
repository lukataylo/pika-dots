import AppKit

@MainActor
final class SessionMonitor {
    private var task: Task<Void, Never>?
    private let interval: Duration
    private let breakLength: TimeInterval
    private let cooldown: TimeInterval
    private let currentApp: () -> String?
    private let keyboardIdle: () -> TimeInterval
    init(interval: Duration = .seconds(10), breakLength: TimeInterval = 120, cooldown: TimeInterval = 60,
         currentApp: @escaping () -> String? = {
             let active = NSWorkspace.shared.frontmostApplication
             return active?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : active?.localizedName
         }, keyboardIdle: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
         }) {
        self.interval = interval; self.breakLength = breakLength; self.cooldown = cooldown
        self.currentApp = currentApp; self.keyboardIdle = keyboardIdle
    }
    func stop() { task?.cancel(); task = nil }
    func start(agentID: String, targetApp: String?, onMessage: @escaping @MainActor (String) -> Void) {
        stop()
        let interval = interval, breakLength = breakLength, cooldown = cooldown
        let currentApp = currentApp, keyboardIdle = keyboardIdle
        task = Task {
            let start = Date()
            var lastNudge = Date.distantPast
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval); try Task.checkCancellation() } catch { return }
                if agentID == "chill" {
                    if Date().timeIntervalSince(start) >= breakLength {
                        onMessage("Break complete. Ready when you are."); return
                    }
                    if keyboardIdle() < 3, Date().timeIntervalSince(lastNudge) >= cooldown {
                        lastNudge = Date()
                        onMessage("Rest your keyboard. Enjoy your break.")
                    }
                } else if agentID == "focus", let targetApp, let active = currentApp(), active != targetApp,
                          Date().timeIntervalSince(lastNudge) >= cooldown {
                    lastNudge = Date()
                    onMessage("Back to \(targetApp)?")
                }
            }
        }
    }
}
