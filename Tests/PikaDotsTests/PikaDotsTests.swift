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
        let collapsed = AttachmentLayout(window: window, screen: screen, expandedHeight: 32)
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
        let monitor = SessionMonitor(interval: .milliseconds(5), cooldown: 10, currentApp: { 2 })
        var messages: [String] = []
        monitor.start(agentID: "focus", targetApp: "Notes", targetPID: 1) { messages.append($0) }
        try await Task.sleep(for: .milliseconds(60))
        monitor.stop()
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages.first?.contains("Notes") == true)
    }
    func testFocusStaysQuietInTargetApp() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), currentApp: { 1 })
        var count = 0
        monitor.start(agentID: "focus", targetApp: "Chrome", targetPID: 1) { _ in count += 1 }
        try await Task.sleep(for: .milliseconds(40)); monitor.stop()
        XCTAssertEqual(count, 0)
    }
    func testFocusStaysQuietWhilePikaItselfIsFrontmost() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), currentApp: { nil })
        var count = 0
        monitor.start(agentID: "focus", targetApp: "Notes", targetPID: 1) { _ in count += 1 }
        try await Task.sleep(for: .milliseconds(40)); monitor.stop()
        XCTAssertEqual(count, 0)
    }
    func testChillNudgesTypingAndCompletesExactlyOnce() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), breakLength: 0.05, cooldown: 10, keyboardIdle: { 0 })
        var messages: [String] = []
        monitor.start(agentID: "chill", targetApp: "Chrome", targetPID: 1) { messages.append($0) }
        try await Task.sleep(for: .milliseconds(120)); monitor.stop()
        XCTAssertEqual(messages.filter { $0.localizedCaseInsensitiveContains("keyboard") }.count, 1)
        XCTAssertEqual(messages.filter { $0.contains("Break complete") }.count, 1)
    }
    func testStopPreventsReminders() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(20), breakLength: 0.01, keyboardIdle: { 0 })
        var count = 0
        monitor.start(agentID: "chill", targetApp: "Chrome", targetPID: 1) { _ in count += 1 }
        monitor.stop()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(count, 0)
    }
    func testStartingChillReplacesFocus() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), breakLength: 0.02, currentApp: { 2 }, keyboardIdle: { 100 })
        var messages: [String] = []
        monitor.start(agentID: "focus", targetApp: "Chrome", targetPID: 1) { messages.append($0) }
        monitor.start(agentID: "chill", targetApp: "Chrome", targetPID: 1) { messages.append($0) }
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

final class NudgeFilterTests: XCTestCase {
    func testQuietSentinelToleratesDecoration() {
        for reply in ["NO_NUDGE", "NO_NUDGE.", "`NO_NUDGE`", " no_nudge\n"] { XCTAssertTrue(NudgeFilter.isQuiet(reply), reply) }
        XCTAssertFalse(NudgeFilter.isQuiet("Finish the migration plan's rollback section."))
    }
}

final class CompanionColorTests: XCTestCase {
    func testColourSurvivesSaveAndExtendedRangeIsClamped() {
        let agent = AgentDefinition(id: "focus", name: "F", color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1), summary: "", skillText: "x")
        XCTAssertEqual(CompanionRecord.record(agent).hexColor, "336699")
        let wide = AgentDefinition(id: "focus", name: "F", color: NSColor(srgbRed: 1.3, green: -0.2, blue: 0.5, alpha: 1), summary: "", skillText: "x")
        XCTAssertEqual(CompanionRecord.record(wide).hexColor, "FF0080")
    }
}

final class NotificationCopyTests: XCTestCase {
    func testNotificationIsShortAndSingleLine() {
        let text = NotificationCopy.short(String(repeating: "longword ", count: 50) + "\nextra")
        XCTAssertLessThanOrEqual(text.count, 100)
        XCTAssertLessThanOrEqual(text.split(separator: " ").count, 14)
        XCTAssertFalse(text.contains("\n"))
    }
    func testWordCapMarksTruncation() {
        XCTAssertEqual(NotificationCopy.short("one two three"), "one two three")
        XCTAssertTrue(NotificationCopy.short(String(repeating: "w ", count: 20)).hasSuffix("…"))
    }
}

final class FocusWatchPolicyTests: XCTestCase {
    func testDetectsYouTubeAcrossBrowserTitles() {
        for title in ["YouTube", "Funny cats - YouTube", "Funny cats — YouTube — Dia", "Music - YouTube - Google Chrome", "https://www.youtube.com/watch?v=test"] {
            XCTAssertTrue(FocusWatchPolicy.isYouTube(title), title)
        }
        XCTAssertFalse(FocusWatchPolicy.isYouTube("YouTube API documentation - Google Search"))
        XCTAssertFalse(FocusWatchPolicy.isYouTube("Database migration plan"))
    }
    func testTypingPopupDoesNotPauseTargetWindow() {
        let target = WindowContext(windowID: 10, appName: "Chrome", title: "Video - YouTube", bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), ownerPID: 22)
        let popup = WindowContext(windowID: 11, appName: "Chrome", title: "Autocomplete", bounds: CGRect(x: 20, y: 20, width: 400, height: 250), ownerPID: 22)
        XCTAssertTrue(FocusWatchPolicy.canCheck(target, windows: [popup, target], frontPID: 22))
        XCTAssertFalse(FocusWatchPolicy.canCheck(target, windows: [popup, target], frontPID: 33))
        XCTAssertFalse(FocusWatchPolicy.canCheck(target, windows: [], frontPID: 22))
    }
    func testDifferentMainWindowPausesScreenshotCapture() {
        let target = WindowContext(windowID: 10, appName: "Chrome", title: "Work", bounds: CGRect(x: 0, y: 0, width: 1000, height: 700), ownerPID: 22)
        let front = WindowContext(windowID: 12, appName: "Chrome", title: "Other window", bounds: target.bounds, ownerPID: 22)
        XCTAssertFalse(FocusWatchPolicy.canCheck(target, windows: [front, target], frontPID: 22))
    }
    func testLegacyFocusSettingsEnableYouTubeWithoutForcingPause() throws {
        let record = try JSONDecoder().decode(CompanionRecord.self, from: Data(#"{"id":"focus","name":"Focus","summary":"Focus","hexColor":"FF9500","mode":"supervisor","defaultPurpose":"Work"}"#.utf8))
        let definition = record.definition(skill: "Focus")
        XCTAssertTrue(definition.watchYouTube)
        XCTAssertFalse(definition.pauseOnDistraction)
    }
    func testInterventionConfigurationPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(directory: directory)
        let agent = AgentDefinition(id: UUID().uuidString, name: "Coach", color: .orange, summary: "", skillText: "Focus", mode: .supervisor, defaultPurpose: "Work", watchYouTube: true, pauseOnDistraction: true)
        try store.save([agent])
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertTrue(loaded.watchYouTube)
        XCTAssertTrue(loaded.pauseOnDistraction)
    }
    func testRestartSnapshotRetainsWindowAndPausedState() throws {
        let snapshot = AttachmentSnapshot(agentID: "focus", windowID: 12, ownerPID: 23, prompt: "Write a proposal", running: false, startedAt: Date(timeIntervalSince1970: 10), snoozedUntil: Date(timeIntervalSince1970: 60))
        let restored = try JSONDecoder().decode(AttachmentSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.windowID, 12)
        XCTAssertEqual(restored.prompt, "Write a proposal")
        XCTAssertFalse(restored.running)
        XCTAssertEqual(restored.startedAt, snapshot.startedAt)
    }
}
