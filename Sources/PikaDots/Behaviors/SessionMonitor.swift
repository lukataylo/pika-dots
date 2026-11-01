import AppKit

@MainActor
final class SessionMonitor {
    private var task: Task<Void, Never>?
    func stop() { task?.cancel(); task = nil }
    func start(agentID: String, targetApp: String?, onMessage: @escaping @MainActor (String) -> Void) {
        stop()
        task = Task {
            if agentID == "chill" {
                do { try await Task.sleep(for: .seconds(120)); try Task.checkCancellation() }
                catch { return }
                onMessage("Break complete. Come back gently when you’re ready.")
            } else if agentID == "focus", let targetApp {
                var lastNudge = Date.distantPast
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)); try Task.checkCancellation() }
                    catch { return }
                    guard Date().timeIntervalSince(lastNudge) > 60,
                          let active = NSWorkspace.shared.frontmostApplication,
                          active.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                          active.localizedName != targetApp else { continue }
                    lastNudge = Date()
                    onMessage("You’ve switched to \(active.localizedName ?? "another app"). Ready to return to \(targetApp)?")
                }
            }
        }
    }
}
