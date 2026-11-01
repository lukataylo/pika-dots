import Foundation

struct DemoResponder: AgentResponding {
    func respond(to request: TaskRequest) async throws -> String {
        try await Task.sleep(for: .milliseconds(450))
        try Task.checkCancellation()
        switch request.agent.id {
        case "focus": return "Focus session started. I’ll remind you if you leave \(request.window?.appName ?? "your current app"). Your intention: \(request.prompt)"
        case "chill": return "Your two-minute break starts now. Relax your shoulders, look away from the screen, and take a breath."
        default: return "Demo mode · Attached to \(request.window?.label ?? "your desktop").\n\nYour request: “\(request.prompt)”\n\nThe desktop interaction is ready. Connect an AgentResponding provider and window capture to generate an answer from this window’s contents."
        }
    }
}
