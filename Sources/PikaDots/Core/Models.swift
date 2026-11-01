import AppKit

struct AgentDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let color: NSColor
    let summary: String
    let skillText: String
}

struct WindowContext {
    let windowID: CGWindowID
    let appName: String
    let title: String
    let bounds: CGRect
    var ownerPID: pid_t = 0
    var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

struct TaskRequest {
    let sessionID: UUID
    let agent: AgentDefinition
    let prompt: String
    let window: WindowContext?
    var imageData: Data? = nil
}

protocol AgentResponding {
    func respond(to request: TaskRequest) async throws -> String
}

struct SkillLoader {
    static func load() -> [AgentDefinition] {
        [("focus", "Focus", NSColor.systemOrange, "Stay with your intention"),
         ("chill", "Chill", NSColor.systemTeal, "Make space for a break"),
         ("explain", "Explain", NSColor.systemPurple, "A fresh pair of eyes")].map { id, name, color, summary in
            let url = Bundle.module.url(forResource: id, withExtension: "md", subdirectory: "Skills")
            let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            return AgentDefinition(id: id, name: name, color: color, summary: summary, skillText: text)
        }
    }
}
