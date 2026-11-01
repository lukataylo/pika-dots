import AppKit

struct CompanionRecord: Codable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var hexColor: String
    var mode: AgentMode
    var defaultPurpose: String
    var watchYouTube: Bool? = nil
    var pauseOnDistraction: Bool? = nil
    static func record(_ agent: AgentDefinition) -> Self {
        // sRGB matches how definition(skill:) decodes; clamp extended-range picker colours.
        let c = agent.color.usingColorSpace(.sRGB) ?? .systemOrange
        let byte = { (v: CGFloat) in Int((min(1, max(0, v)) * 255).rounded()) }
        return Self(id: agent.id, name: agent.name, summary: agent.summary,
                    hexColor: String(format: "%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent)), mode: agent.mode, defaultPurpose: agent.defaultPurpose, watchYouTube: agent.watchYouTube, pauseOnDistraction: agent.pauseOnDistraction)
    }
    func definition(skill: String) -> AgentDefinition {
        let value = UInt32(hexColor, radix: 16) ?? 0xFF9500
        return AgentDefinition(id: id, name: name,
            color: NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1), summary: summary,
            skillText: skill, mode: mode, defaultPurpose: defaultPurpose, watchYouTube: watchYouTube ?? (id == "focus"), pauseOnDistraction: pauseOnDistraction ?? false)
    }
}

struct CompanionStore {
    let directory: URL
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PikaDots/Companions")) { self.directory = directory }
    func load() throws -> [AgentDefinition] {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("roster.json").path) else { return SkillLoader.load() }
        let records = try JSONDecoder().decode([CompanionRecord].self, from: Data(contentsOf: directory.appendingPathComponent("roster.json")))
        return try records.map { record in
            guard UUID(uuidString: record.id) != nil || ["focus", "chill", "explain"].contains(record.id) else { throw PikaError.message("Invalid companion identifier.") }
            return record.definition(skill: try String(contentsOf: directory.appendingPathComponent(record.id + ".md"), encoding: .utf8))
        }
    }
    func save(_ agents: [AgentDefinition]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for agent in agents {
            try agent.skillText.write(to: directory.appendingPathComponent(agent.id + ".md"), atomically: true, encoding: .utf8)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(agents.map(CompanionRecord.record)).write(to: directory.appendingPathComponent("roster.json"), options: .atomic)
    }
}
