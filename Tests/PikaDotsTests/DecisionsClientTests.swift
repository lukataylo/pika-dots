import XCTest
@testable import PikaDots

final class DecisionsClientTests: XCTestCase {
    func answers(off: Double, on: Double, related: Double, category: String = "entertainment") -> [DecisionsClient.Answer] {
        let json = """
        {"answers":[
          {"type":"choice","name":"category","choice":"\(category)","probabilities":[{"value":"\(category)","probability":0.9}],"confidence":0.9},
          {"type":"choice","name":"relevance","choice":"off_task","probabilities":[
            {"value":"on_task","probability":\(on)},{"value":"related","probability":\(related)},{"value":"off_task","probability":\(off)}],"confidence":0.8}
        ]}
        """
        struct R: Decodable { var answers: [DecisionsClient.Answer] }
        return try! JSONDecoder().decode(R.self, from: Data(json.utf8)).answers
    }

    func testOffTaskNeedsConfidence() {
        XCTAssertEqual(DecisionsClient.focusVerdict(answers(off: 0.82, on: 0.08, related: 0.10))?.relevance, .offTask)
        XCTAssertEqual(DecisionsClient.focusVerdict(answers(off: 0.55, on: 0.15, related: 0.30))?.relevance, .related, "an unsure off-task call is not a nudge")
        XCTAssertEqual(DecisionsClient.focusVerdict(answers(off: 0.05, on: 0.80, related: 0.15, category: "work"))?.relevance, .onTask)
        XCTAssertEqual(DecisionsClient.focusVerdict(answers(off: 0.82, on: 0.08, related: 0.10))?.category, .entertainment)
    }

    func testRefusalYieldsNoVerdict() {
        struct R: Decodable { var answers: [DecisionsClient.Answer] }
        let refused = try! JSONDecoder().decode(R.self, from: Data(#"{"answers":[{"type":"choice","name":"category","choice":"work"},{"type":"refusal","name":"relevance"}]}"#.utf8)).answers
        XCTAssertNil(DecisionsClient.focusVerdict(refused))
    }

    func testRequestShape() throws {
        let request = try DecisionsClient.request(text: "Window: Notes", imageJPEG: Data([1, 2, 3]), questions: DecisionsClient.focusQuestions(purpose: "Write the brief"), key: "k")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/decisions")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        let content = ((body["input"] as! [[String: Any]])[0]["content"] as! [[String: String]])
        XCTAssertEqual(content.map { $0["type"] }, ["input_text", "input_image"])
        XCTAssertTrue(content[1]["image_url"]!.hasPrefix("data:image/jpeg;base64,"))
        let questions = body["questions"] as! [[String: Any]]
        XCTAssertEqual(questions.map { $0["name"] as? String }, ["category", "relevance"])
        XCTAssertEqual((questions[1]["choices"] as! [[String: Any]]).count, 3)
        XCTAssertNil(questions[0]["levels"], "unused fields are omitted, not sent as null")
    }
}

final class CompanionAPITests: XCTestCase {
    func testOlderSavedCompanionsGetSensibleAPIDefaults() throws {
        let json = #"[{"id":"focus","name":"Focus","summary":"","hexColor":"FF9500","mode":"supervisor","defaultPurpose":"x"},{"id":"explain","name":"Explain","summary":"","hexColor":"AF52DE","mode":"promptable","defaultPurpose":"","api":"decisions"}]"#
        let records = try JSONDecoder().decode([CompanionRecord].self, from: Data(json.utf8))
        XCTAssertEqual(records[0].definition(skill: "s").api, .decisions)
        XCTAssertEqual(records[1].definition(skill: "s").api, .responses, "companions that reply always use Responses")
        XCTAssertEqual(SkillLoader.load().first { $0.id == "focus" }?.api, .decisions)
    }
}
