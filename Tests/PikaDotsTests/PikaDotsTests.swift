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

final class CompanionStoreTests: XCTestCase {
    func testRoundTripPersistsSkillAndSupervisorConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(directory: directory)
        let companion = AgentDefinition(id: UUID().uuidString, name: "Coach", color: .systemGreen, summary: "A little help", skillText: "# Coach\nBe kind.", mode: .supervisor, defaultPurpose: "Check my writing.")
        try store.save([companion])
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.name, "Coach")
        XCTAssertEqual(loaded.mode, .supervisor)
        XCTAssertEqual(loaded.defaultPurpose, "Check my writing.")
        XCTAssertEqual(loaded.skillText, "# Coach\nBe kind.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(companion.id + ".md").path))
    }
    func testEmptyRosterRemainsEmptyAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(directory: directory)
        try store.save([])
        XCTAssertTrue(try store.load().isEmpty)
    }
}

@MainActor
final class SupervisionTests: XCTestCase {
    func testFocusNudgesSwitchAwayAndRespectsCooldown() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), cooldown: 10, currentApp: { "Safari" })
        var messages: [String] = []
        monitor.start(agentID: "focus", targetApp: "Notes") { messages.append($0) }
        try await Task.sleep(for: .milliseconds(60))
        monitor.stop()
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first?.contains("Notes") == true)
    }
    func testFocusStaysQuietInTargetApp() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), currentApp: { "Chrome" })
        var count = 0
        monitor.start(agentID: "focus", targetApp: "Chrome") { _ in count += 1 }
        try await Task.sleep(for: .milliseconds(40)); monitor.stop()
        XCTAssertEqual(count, 0)
    }
    func testChillNudgesTypingAndCompletesExactlyOnce() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), breakLength: 0.05, cooldown: 10, keyboardIdle: { 0 })
        var messages: [String] = []
        monitor.start(agentID: "chill", targetApp: "Chrome") { messages.append($0) }
        try await Task.sleep(for: .milliseconds(120)); monitor.stop()
        XCTAssertEqual(messages.filter { $0.localizedCaseInsensitiveContains("keyboard") }.count, 1)
        XCTAssertEqual(messages.filter { $0.contains("Break complete") }.count, 1)
    }
    func testStopPreventsReminders() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(20), breakLength: 0.01, keyboardIdle: { 0 })
        var count = 0
        monitor.start(agentID: "chill", targetApp: "Chrome") { _ in count += 1 }
        monitor.stop()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(count, 0)
    }
    func testStartingChillReplacesFocus() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), breakLength: 0.02, currentApp: { "Safari" }, keyboardIdle: { 100 })
        var messages: [String] = []
        monitor.start(agentID: "focus", targetApp: "Chrome") { messages.append($0) }
        monitor.start(agentID: "chill", targetApp: "Chrome") { messages.append($0) }
        try await Task.sleep(for: .milliseconds(60)); monitor.stop()
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first?.contains("Break complete") == true)
    }
}

@MainActor
final class CharacterArtworkTests: XCTestCase {
    func testBundledCatPosesLoadWithAlpha() throws {
        for id in ["focus", "chill", "explain"] {
            let image = try XCTUnwrap(CharacterArtwork.image(for: id))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            XCTAssertTrue(bitmap.hasAlpha, "\(id) must preserve transparency")
        }
    }
}

final class NotificationCopyTests: XCTestCase {
    func testNotificationIsShortAndSingleLine() {
        let text = NotificationCopy.short(String(repeating: "longword ", count: 50) + "\nextra")
        XCTAssertLessThanOrEqual(text.count, 100)
        XCTAssertLessThanOrEqual(text.split(separator: " ").count, 14)
        XCTAssertFalse(text.contains("\n"))
    }
}
