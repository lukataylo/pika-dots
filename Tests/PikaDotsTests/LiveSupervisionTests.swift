import XCTest
import AppKit
@testable import PikaDots

@MainActor
final class LiveSupervisionTests: XCTestCase {
    private func fixture(_ text: String) throws -> Data {
        let image = NSImage(size: NSSize(width: 1000, height: 600))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
        (text as NSString).draw(in: NSRect(x: 40, y: 60, width: 920, height: 480), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    }
    func testLiveVisionDistinguishesWorkFromDistractionAndSupportsBreaks() async throws {
        guard ProcessInfo.processInfo.environment["PIKA_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live API test using synthetic windows only.") }
        let focus = try XCTUnwrap(SkillLoader.load().first { $0.id == "focus" })
        let chill = try XCTUnwrap(SkillLoader.load().first { $0.id == "chill" })
        let prompt = "I am writing a database migration plan. Assess this browser screenshot. Reply exactly NO_NUDGE if it is relevant work. Otherwise reply with one short reminder to return to my migration plan."
        let work = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: focus, prompt: prompt, window: nil, imageData: fixture("Browser tab: Database migration plan\n\n1. Back up production database\n2. Validate schema changes\n3. Run SQL migration in staging\n4. Test rollback strategy\n5. Schedule migration window")))
        XCTAssertEqual(work.trimmingCharacters(in: .whitespacesAndNewlines), "NO_NUDGE")
        let distraction = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: focus, prompt: prompt, window: nil, imageData: fixture("Browser tab: Endless entertainment feed\n\nFUNNY CAT VIDEOS\nCelebrity gossip\nWatch next: hilarious memes\nAutoplay enabled\nKeep scrolling for more viral videos")))
        XCTAssertFalse(distraction.trimmingCharacters(in: .whitespacesAndNewlines) == "NO_NUDGE")
        XCTAssertTrue(distraction.lowercased().contains("migration"))
        let relaxation = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: chill, prompt: "I am on a two-minute break but returned to coding. Give one brief reminder to stop working and relax.", window: nil, imageData: fixture("Code editor: App.swift\n\nfunc deployProduction() {\n    runDatabaseMigration()\n}\n\nTODO: finish feature implementation\nBuild running...")))
        XCTAssertFalse(relaxation.isEmpty)
        XCTAssertTrue(["break", "relax", "rest", "breath", "pause"].contains { relaxation.lowercased().contains($0) }, relaxation)
    }

    /// Full Go path against a real on-screen window: ScreenCaptureKit capture -> OpenAI -> notification-sized reply.
    /// Run with PIKA_LIVE_TESTS=1 and a TextEdit window open; uses the test runner's screen-recording permission.
    func testLiveCaptureOfRealWindowAnswersEachCompanion() async throws {
        guard ProcessInfo.processInfo.environment["PIKA_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live API test.") }
        let window = try XCTUnwrap(WindowFinder.windows().first { $0.appName == "TextEdit" }, "Open a TextEdit window first.")
        let image = try await WindowCapture.capture(window)
        XCTAssertGreaterThan(image.count, 1000)
        let agents = SkillLoader.load()
        for (id, prompt) in [("explain", "explain this error"), ("focus", "help me finish this proposal"), ("chill", "Help me take a two-minute break.")] {
            let agent = try XCTUnwrap(agents.first { $0.id == id })
            let reply = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: agent, prompt: prompt, window: window, imageData: image))
            let short = NotificationCopy.short(reply)
            print("LIVE \(id): \(reply)  ->  \(short)")
            XCTAssertFalse(reply.isEmpty)
            XCTAssertLessThanOrEqual(short.count, 100)
        }
    }

    /// Non-binary classification: an on-topic lecture on YouTube is learning/related, a vlog is entertainment/off-task.
    func testLiveFocusCheckClassifiesContentNotSite() async throws {
        guard ProcessInfo.processInfo.environment["PIKA_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live API test.") }
        let focus = try XCTUnwrap(SkillLoader.load().first { $0.id == "focus" })
        func check(_ title: String, _ page: String) async throws -> FocusVerdict {
            let window = WindowContext(windowID: 1, appName: "Google Chrome", title: title, bounds: .zero)
            let answer = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: focus, prompt: "Write my database migration plan", window: window, imageData: fixture(page), kind: .focusCheck))
            print("LIVE focusCheck \(title): \(answer)")
            return try XCTUnwrap(FocusVerdict.parse(answer), answer)
        }
        let lecture = try await check("Postgres zero-downtime migrations explained - YouTube", "YouTube\n\nPostgres zero-downtime schema migrations explained\nConference talk · 48:12\nChapters: expand/contract, backfills, rollback")
        XCTAssertEqual(lecture.category, .learning); XCTAssertTrue(lecture.onTask)
        let vlog = try await check("My week in Tokyo vlog - YouTube", "YouTube\n\nMy week in Tokyo! Street food, karaoke and shopping haul\nVlog · 22:40\nUp next: funniest fails compilation")
        XCTAssertEqual(vlog.category, .entertainment); XCTAssertFalse(vlog.onTask)
        XCTAssertFalse(vlog.message.isEmpty)
        let doc = try await check("Migration plan - Google Docs", "Google Docs\n\nMigration plan\n1. Back up production\n2. Expand schema\n3. Backfill\n4. Contract")
        XCTAssertEqual(doc.relevance, .onTask)
        let explain = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: try XCTUnwrap(SkillLoader.load().first { $0.id == "explain" }), prompt: "explain this error", window: nil, imageData: fixture("main.js\n\nTypeError: undefined is not a function\n    at render (main.js:12)\n    at App (app.js:40)"), kind: .ask))
        print("LIVE ask: \(explain)")
        XCTAssertGreaterThan(explain.split(separator: " ").count, 14, "card answers may be longer than a notification")
        XCTAssertLessThan(explain.split(separator: " ").count, 110)
    }

    func testLiveGenericPurposeStillFlagsLeisureYouTube() async throws {
        guard ProcessInfo.processInfo.environment["PIKA_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live API test.") }
        let focus = try XCTUnwrap(SkillLoader.load().first { $0.id == "focus" })
        let window = WindowContext(windowID: 1, appName: "Google Chrome", title: "20 Minutes of Cute Cats - YouTube", bounds: .zero)
        let answer = try await OpenAIResponder().respond(to: TaskRequest(sessionID: UUID(), agent: focus, prompt: FocusVerdict.genericPurpose, window: window, imageData: fixture("YouTube\n\n20 Minutes of Cute Cats\nThe Pet Collective · 2.1M views\nUp next: funny kittens compilation"), kind: .focusCheck))
        print("LIVE generic: \(answer)")
        XCTAssertEqual(try XCTUnwrap(FocusVerdict.parse(answer)).relevance, .offTask)
    }

    /// Live smoke test of the Decisions path Focus uses by default.
    func testLiveDecisionsFocusCheck() async throws {
        guard ProcessInfo.processInfo.environment["PIKA_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live API test.") }
        let window = WindowContext(windowID: 1, appName: "Google Chrome", title: "20 Minutes of Cute Cats - YouTube", bounds: .zero)
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: fixture("YouTube\n\n20 Minutes of Cute Cats\nThe Pet Collective · 2.1M views\nUp next: funny kittens"))?.representation(using: .jpeg, properties: [:]))
        let off = try await DecisionsClient.focusCheck(purpose: "Write my database migration plan", window: window, imageJPEG: jpeg)
        print("LIVE decisions cats: \(off)")
        XCTAssertEqual(off.category, .entertainment); XCTAssertEqual(off.relevance, .offTask)
        let doc = WindowContext(windowID: 2, appName: "Google Chrome", title: "Migration plan - Google Docs", bounds: .zero)
        let docJPEG = try XCTUnwrap(NSBitmapImageRep(data: fixture("Google Docs\n\nMigration plan\n1. Back up production\n2. Expand schema\n3. Backfill"))?.representation(using: .jpeg, properties: [:]))
        let on = try await DecisionsClient.focusCheck(purpose: "Write my database migration plan", window: doc, imageJPEG: docJPEG)
        print("LIVE decisions doc: \(on)")
        XCTAssertTrue(on.onTask)
    }
}
