import AppKit

/// Activity only: never installs a key logger or reads characters or key codes.
enum TypingActivity {
    static func summary(for ownerPID: pid_t) -> String {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID else { return "App in background · checks paused" }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if idle < 3 { return "Typing now · checks every 45s" }
        if idle < 60 { return "Typed recently · checks every 45s" }
        return "Keyboard quiet · checks every 45s"
    }
}
