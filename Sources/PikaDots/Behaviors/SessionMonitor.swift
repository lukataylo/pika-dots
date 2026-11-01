import AppKit

@MainActor
final class SessionMonitor {
    private var task: Task<Void, Never>?
    private let interval: Duration
    private let breakLength: TimeInterval
    private let cooldown: TimeInterval
    private let currentApp: () -> pid_t?
    private let keyboardIdle: () -> TimeInterval
    init(interval: Duration = .seconds(10), breakLength: TimeInterval = 120, cooldown: TimeInterval = 60,
         currentApp: @escaping () -> pid_t? = {
             let active = NSWorkspace.shared.frontmostApplication?.processIdentifier
             return active == ProcessInfo.processInfo.processIdentifier ? nil : active
         }, keyboardIdle: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
         }) {
        self.interval = interval; self.breakLength = breakLength; self.cooldown = cooldown
        self.currentApp = currentApp; self.keyboardIdle = keyboardIdle
    }
    func stop() { task?.cancel(); task = nil }
    func start(agentID: String, targetApp: String?, targetPID: pid_t?, startedAt: Date? = nil, onMessage: @escaping @MainActor (String) -> Void) {
        stop()
        // Any key press since the previous poll counts as still typing.
        let typingWindow = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let interval = interval, breakLength = breakLength, cooldown = cooldown
        let currentApp = currentApp, keyboardIdle = keyboardIdle
        task = Task {
            let start = startedAt ?? Date()
            var lastNudge = Date.distantPast
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval); try Task.checkCancellation() } catch { return }
                if agentID == "chill" {
                    if Date().timeIntervalSince(start) >= breakLength {
                        onMessage("Break complete. Ready when you are."); return
                    }
                    if keyboardIdle() < typingWindow, Date().timeIntervalSince(lastNudge) >= cooldown {
                        lastNudge = Date()
                        onMessage("Rest your keyboard. Enjoy your break.")
                    }
                } else if agentID == "focus", let targetApp, let targetPID, let active = currentApp(), active != targetPID,
                          Date().timeIntervalSince(lastNudge) >= cooldown {
                    lastNudge = Date()
                    onMessage("Back to \(targetApp)?")
                }
            }
        }
    }
}
