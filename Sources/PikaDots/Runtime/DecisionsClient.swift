import Foundation

/// Which OpenAI API a companion uses for its checks. Responses writes prose and JSON; Decisions returns
/// calibrated probabilities for fixed questions, which is faster and cheaper for yes/no supervision.
enum ModelAPI: String, Codable, CaseIterable, Identifiable, Sendable {
    case responses, decisions
    var id: String { rawValue }
    var title: String { self == .responses ? "Responses" : "Decisions" }
    var summary: String {
        self == .responses ? "Writes replies and tips. Use for companions that talk."
            : "Fast yes/no checks with confidence. Use for supervision."
    }
}

/// OpenAI's /v1/decisions endpoint (public beta, Oct 2026; only model gpt-6-luna).
/// Each question is answered independently against the same input, with probabilities.
enum DecisionsClient {
    struct Option: Encodable, Equatable { var value: String; var description: String? = nil }
    struct Level: Encodable, Equatable { var label: String; var description: String? = nil }
    struct Question: Encodable, Equatable {
        enum Kind: String, Encodable { case predicate, choice, score }
        var type: Kind
        var name: String
        var instructions: String
        var choices: [Option]? = nil
        var levels: [Level]? = nil
    }
    struct Answer: Decodable, Equatable {
        struct Weight: Decodable, Equatable { var value: String?; var label: String?; var probability: Double }
        var type: String
        var name: String?
        var probability: Double?
        var choice: String?
        var score: Double?
        var confidence: Double?
        var probabilities: [Weight]?
        func probability(of value: String) -> Double { probabilities?.first { $0.value == value }?.probability ?? (choice == value ? 1 : 0) }
    }
    private struct Reply: Decodable { var answers: [Answer] }

    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static func request(text: String, imageJPEG: Data?, questions: [Question], key: String, model: String = "gpt-6-luna") throws -> URLRequest {
        var content: [[String: String]] = [["type": "input_text", "text": text]]
        if let imageJPEG { content.append(["type": "input_image", "image_url": "data:image/jpeg;base64," + imageJPEG.base64EncodedString()]) }
        let body: [String: Any] = [
            "model": model,
            "input": [["role": "user", "content": content]],
            "questions": try JSONSerialization.jsonObject(with: JSONEncoder().encode(questions))
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/decisions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decide(text: String, imageJPEG: Data?, questions: [Question], send: Send = { try await URLSession.shared.data(for: $0) }) async throws -> [Answer] {
        guard let key = LocalConfiguration.value("OPENAI_API_KEY") else { throw PikaError.message("Add your API key in Pika settings.") }
        let model = LocalConfiguration.value("OPENAI_DECISIONS_MODEL") ?? "gpt-6-luna"
        let data: Data, response: URLResponse
        do { (data, response) = try await send(try request(text: text, imageJPEG: imageJPEG, questions: questions, key: key, model: model)) }
        catch let error as URLError where error.code != .cancelled { throw PikaError.message("Couldn’t reach OpenAI. Try again.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PikaError.message(status == 401 ? "API key rejected. Update it in Pika settings."
                : status == 429 ? "API limit reached. Check your OpenAI quota."
                : status == 404 ? "The Decisions API isn’t available on this key. Switch the companion to Responses."
                : "OpenAI request failed (\(status)).")
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw PikaError.message("Pika couldn’t read the decision.") }
        return reply.answers
    }

    // MARK: Focus

    /// Off-task only when the model is at least this sure; anything less counts as related.
    /// A wrong nudge costs more trust than a missed one.
    static let offTaskThreshold = 0.7

    static func focusQuestions(purpose: String) -> [Question] {
        let categories: [(FocusVerdict.Category, String)] = [
            (.work, "Doing the task itself: writing, coding, designing, editing."), (.research, "Looking things up for a task."),
            (.learning, "Courses, lectures, documentation, tutorials."), (.communication, "Email, chat, calls, messages."),
            (.entertainment, "Videos, games, streaming for leisure."), (.social, "Social feeds."), (.news, "News and current affairs."),
            (.shopping, "Shops and product browsing."), (.other, "Anything else.")]
        return [
            Question(type: .choice, name: "category", instructions: "What is the person doing in this window?",
                     choices: categories.map { Option(value: $0.0.rawValue, description: $0.1) }),
            Question(type: .choice, name: "relevance", instructions: "How does what is on screen relate to the person's stated purpose: \(purpose)",
                     choices: [Option(value: "on_task", description: "Directly serves the purpose."),
                               Option(value: "related", description: "Plausibly supports it, or is a short necessary detour."),
                               Option(value: "off_task", description: "Unrelated to the purpose.")])
        ]
    }

    static func focusVerdict(_ answers: [Answer]) -> FocusVerdict? {
        guard let relevance = answers.first(where: { $0.name == "relevance" }), relevance.type == "choice",
              let category = answers.first(where: { $0.name == "category" })?.choice.flatMap(FocusVerdict.Category.init(rawValue:)) else { return nil }
        let off = relevance.probability(of: "off_task")
        let level: FocusVerdict.Relevance = off >= offTaskThreshold ? .offTask
            : relevance.probability(of: "on_task") >= relevance.probability(of: "related") ? .onTask : .related
        return FocusVerdict(category: category, relevance: level, message: "")
    }

    /// One Focus check through the Decisions API, in the same shape the Responses path parses.
    static func focusCheck(purpose: String, window: WindowContext, imageJPEG: Data?, send: Send = { try await URLSession.shared.data(for: $0) }) async throws -> FocusVerdict {
        let text = "Window: \(window.label)\nPurpose: \(purpose)"
        guard let verdict = focusVerdict(try await decide(text: text, imageJPEG: imageJPEG, questions: focusQuestions(purpose: purpose), send: send)) else {
            throw PikaError.message("Pika couldn’t read the decision.")
        }
        return verdict
    }
}
