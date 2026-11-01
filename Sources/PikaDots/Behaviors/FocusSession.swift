import Foundation

/// Local bookkeeping for one Focus session; nothing here leaves the Mac.
struct FocusSession {
    static let driftThreshold: TimeInterval = 10
    let label: String
    let startedAt: Date
    let length: TimeInterval?
    private(set) var onTask: TimeInterval = 0
    private(set) var away: TimeInterval = 0
    private(set) var drifts = 0
    private var lastTick: Date
    private var awaySince: Date?
    private var countedStretch = false

    init(label: String, length: TimeInterval?, startedAt: Date = Date()) {
        self.label = label; self.length = length; self.startedAt = startedAt; lastTick = startedAt
    }

    /// Adds the time since the previous tick. Returns true when a wander has just become a counted drift.
    @discardableResult
    mutating func record(onTask isOnTask: Bool, at now: Date = Date()) -> Bool {
        // Cap each step so sleep, breaks, or a stalled loop never inflate the totals.
        let step = max(0, min(now.timeIntervalSince(lastTick), 10))
        lastTick = now
        if isOnTask { onTask += step; awaySince = nil; return false }
        away += step
        if awaySince == nil { awaySince = now; countedStretch = false }
        guard !countedStretch, let since = awaySince, now.timeIntervalSince(since) >= Self.driftThreshold else { return false }
        countedStretch = true; drifts += 1
        return true
    }
    /// Call when supervision resumes so the paused gap is not counted.
    mutating func resume(at now: Date = Date()) { lastTick = now; awaySince = nil }

    func awayFor(at now: Date = Date()) -> TimeInterval { awaySince.map { now.timeIntervalSince($0) } ?? 0 }
    var elapsed: TimeInterval { onTask + away }
    func remaining() -> TimeInterval? { length.map { max(0, $0 - elapsed) } }
    func isOver() -> Bool { remaining() == 0 }

    var startMessage: String {
        guard let length else { return "Focusing on \(label). I’ll keep you on track." }
        return "\(Self.minutes(length)) on \(label). I’ll keep you on track."
    }
    var resumeMessage: String {
        guard let left = remaining() else { return "Back to \(label)?" }
        return "Back to \(label)? \(Self.minutes(left)) left."
    }
    var recapShort: String {
        "Focus done · \(Self.minutes(onTask)) on task · \(drifts) \(drifts == 1 ? "drift" : "drifts")"
    }
    var recapDetail: String {
        let drift = drifts == 0 ? "No drifts. Nicely done." : "\(drifts) \(drifts == 1 ? "drift" : "drifts") back on track."
        return "\(label)\n\(Self.minutes(onTask)) on task · \(Self.minutes(away)) away\n\(drift)"
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "<1 min" : "\(Int((seconds / 60).rounded(.down))) min"
    }
    static func label(purpose: String, defaultPurpose: String, appName: String) -> String {
        let text = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != defaultPurpose else { return appName }
        return "“" + (text.count > 40 ? String(text.prefix(39)) + "…" : text) + "”"
    }
}

/// Cached on-task verdicts per window title, so the model is asked once per page rather than on a timer.
struct TitleVerdicts {
    static let ttl: TimeInterval = 300
    private var entries: [String: (verdict: FocusVerdict, at: Date)] = [:]

    static func key(for window: WindowContext) -> String {
        window.appName.lowercased() + "|" + FocusWatchPolicy.normalizedTitle(window.title)
    }
    func verdict(for key: String, at now: Date = Date()) -> FocusVerdict? {
        guard let entry = entries[key], now.timeIntervalSince(entry.at) < Self.ttl else { return nil }
        return entry.verdict
    }
    mutating func store(_ verdict: FocusVerdict, for key: String, at now: Date = Date()) {
        if entries.count > 200 { entries.removeAll() }
        entries[key] = (verdict, now)
    }
    mutating func reset() { entries.removeAll() }
}

/// What the page is and how it relates to the purpose. "related" covers things like an
/// educational video on the topic: not the task itself, but not a distraction either.
struct FocusVerdict: Decodable, Equatable {
    enum Category: String, Decodable, CaseIterable { case work, research, learning, communication, entertainment, social, news, shopping, other }
    enum Relevance: String, Decodable, CaseIterable { case onTask = "on_task", related, offTask = "off_task" }
    let category: Category
    let relevance: Relevance
    let message: String
    var onTask: Bool { relevance != .offTask }

    static let genericPurpose = "No specific task given: stay on productive work or study. Entertainment, social feeds, shopping, and leisure videos are distractions."
    /// The model can call a cat video "on task" for a vague purpose like "keep me focused on Chrome",
    /// so without a named task, leisure categories are off-task no matter what it says.
    func adjusted(genericPurpose: Bool) -> FocusVerdict {
        guard genericPurpose, [.entertainment, .social, .shopping].contains(category), relevance != .offTask else { return self }
        return FocusVerdict(category: category, relevance: .offTask, message: "")
    }
    var label: String {
        let kind = category.rawValue.prefix(1).uppercased() + category.rawValue.dropFirst()
        return kind + " · " + (relevance == .onTask ? "on task" : relevance == .related ? "related" : "off task")
    }

    static func parse(_ text: String) -> FocusVerdict? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}") { body = String(body[start...end]) }
        return try? JSONDecoder().decode(FocusVerdict.self, from: Data(body.utf8))
    }
}
