import Foundation

/// What Actions learned on earlier runs: the notes it saved and the pages it opened. A follow-up task
/// ("now write it up as a Google Doc") starts from these instead of from nothing.
struct OperatorMemory {
    struct Run: Codable, Equatable { var date: Date; var goal: String; var notes: [String]; var pages: [String] }
    var file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PikaDots/actions-memory.json")
    /// Older context is more likely to mislead than help.
    var maxAge: TimeInterval = 24 * 3600
    var keepRuns = 8
    var now: () -> Date = Date.init

    func runs() -> [Run] {
        guard let data = try? Data(contentsOf: file), let runs = try? JSONDecoder().decode([Run].self, from: data) else { return [] }
        return runs.filter { now().timeIntervalSince($0.date) <= maxAge }
    }

    func save(goal: String, notes: [String], pages: [String]) {
        guard !notes.isEmpty || !pages.isEmpty else { return }
        let all = (runs() + [Run(date: now(), goal: goal, notes: notes, pages: Array(Set(pages)).sorted())]).suffix(keepRuns)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(all)).write(to: file, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: file) }

    /// Lines for the start of the model's step list.
    func context() -> [String] {
        runs().flatMap { run in
            ["Earlier run (\(run.date.formatted(date: .omitted, time: .shortened))), goal: \(run.goal)"]
                + run.notes.map { "  Earlier note: \($0)" }
                + (run.pages.isEmpty ? [] : ["  Pages it used: " + run.pages.prefix(6).joined(separator: ", ")])
        }
    }
}
