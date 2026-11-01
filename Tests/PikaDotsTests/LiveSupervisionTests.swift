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
        XCTAssertTrue(relaxation.lowercased().contains("break") || relaxation.lowercased().contains("relax"))
    }
}
