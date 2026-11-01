import AppKit

enum AgentMode: String, Codable, CaseIterable {
    case promptable, supervisor
}

struct AgentDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let color: NSColor
    let summary: String
    let skillText: String
    var mode: AgentMode = .promptable
    var defaultPurpose: String = ""
    var watchYouTube: Bool = false
    var pauseOnDistraction: Bool = false
    /// Last rung of the YouTube ladder: close the YouTube tab after repeated warnings.
    var closeYouTube: Bool = false
    /// Which OpenAI API runs this companion's on-task checks; replies always use Responses.
    var api: ModelAPI = .responses
}

struct WindowContext: Equatable {
    let windowID: CGWindowID
    let appName: String
    let title: String
    let bounds: CGRect
    var ownerPID: pid_t = 0
    var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

/// ask: an explicit question shown in the reply card. nudge: a notification-sized
/// periodic observation. focusCheck: a structured on-task verdict for one window title.
enum RequestKind { case ask, nudge, focusCheck }

struct TaskRequest {
    let sessionID: UUID
    let agent: AgentDefinition
    let prompt: String
    let window: WindowContext?
    var imageData: Data? = nil
    var kind: RequestKind = .nudge
}

protocol AgentResponding {
    func respond(to request: TaskRequest) async throws -> String
}

struct SkillLoader {
    static func load() -> [AgentDefinition] {
        [("focus", "Focus", NSColor.systemOrange, "Stay with your intention"),
         ("chill", "Chill", NSColor.systemTeal, "Make space for a break"),
         ("explain", "Explain", NSColor.systemPurple, "A fresh pair of eyes"),
         ("outreach", "Actions", NSColor.systemBlue, "Gets things done in Chrome, with your OK")].map { id, name, color, summary in
            let url = Bundle.module.url(forResource: id, withExtension: "md", subdirectory: "Skills")
            let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            return AgentDefinition(id: id, name: name, color: color, summary: summary, skillText: text, mode: ["explain", "outreach"].contains(id) ? .promptable : .supervisor, defaultPurpose: id == "focus" ? "Keep me focused on this application." : id == "chill" ? "Help me take a two-minute break." : "", watchYouTube: id == "focus", closeYouTube: id == "focus", api: id == "focus" ? .decisions : .responses)
        }
    }
}

enum NudgeFilter {
    /// Models sometimes decorate the sentinel ("NO_NUDGE.", `NO_NUDGE`), so match loosely.
    static func isQuiet(_ answer: String) -> Bool {
        answer.uppercased().contains("NO_NUDGE")
    }
}
