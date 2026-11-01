import XCTest
@testable import PikaDots

final class PikaDotsTests: XCTestCase {
    func testBundledRosterHasDistinctNonemptySkills() {
        let agents = SkillLoader.load()
        XCTAssertEqual(Set(agents.map(\.id)), Set(["focus", "chill", "explain"]))
        XCTAssertTrue(agents.allSatisfy { !$0.skillText.isEmpty })
    }

    func testDemoDoesNotPretendToReadWindowContent() async throws {
        let agent = try XCTUnwrap(SkillLoader.load().first { $0.id == "explain" })
        let response = try await DemoResponder().respond(to: TaskRequest(sessionID: UUID(), agent: agent, prompt: "Summarize", window: nil))
        XCTAssertTrue(response.contains("Demo mode"))
        XCTAssertTrue(response.contains("Connect an AgentResponding provider"))
    }
}

final class OpenAIResponseTests: XCTestCase {
    func testResponseParserSkipsReasoningAndCombinesText() throws {
        let fixture = Data(#"{"output":[{"type":"reasoning","summary":[]},{"content":[{"type":"output_text","text":"Hello"},{"type":"output_text","text":"Pika"}]}]}"#.utf8)
        XCTAssertEqual(try OpenAIResponder().responseText(fixture), "Hello\nPika")
    }
    func testResponseParserReportsEmptyOutput() {
        XCTAssertThrowsError(try OpenAIResponder().responseText(Data(#"{"output":[]}"#.utf8)))
    }
    func testWindowCoordinateConversionRoundTrips() {
        let rect = CGRect(x: -400, y: 50, width: 300, height: 200)
        XCTAssertEqual(WindowFinder.appRect(WindowFinder.appRect(rect)), rect)
    }
}

final class AttachmentLayoutTests: XCTestCase {
    func testResponseKeepsPurposeTopAndPerchedDotFixed() {
        let window = CGRect(x: 100, y: 100, width: 900, height: 500)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let collapsed = AttachmentLayout(window: window, screen: screen, expandedHeight: 40)
        let expanded = AttachmentLayout(window: window, screen: screen, expandedHeight: 178)
        XCTAssertEqual(collapsed.dot, expanded.dot)
        XCTAssertEqual(collapsed.tab.minY, window.maxY - 5)
        XCTAssertEqual(expanded.tab.maxY, collapsed.tab.maxY)
        XCTAssertEqual(expanded.dot.maxX, expanded.tab.minX + 2)
    }
    func testMaximizedWindowKeepsTabOnScreen() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let layout = AttachmentLayout(window: screen, screen: screen, expandedHeight: 178)
        XCTAssertTrue(screen.contains(layout.tab))
        XCTAssertTrue(screen.contains(layout.dot))
    }
}
