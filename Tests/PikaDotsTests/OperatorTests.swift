import XCTest
@testable import PikaDots

private final class FakePage: PageDriving, @unchecked Sendable {
    var page: PageSnapshot
    var performed: [OperatorAction] = []
    init(_ page: PageSnapshot) { self.page = page }
    func snapshot() async throws -> PageSnapshot { page }
    func perform(_ action: OperatorAction) async throws { performed.append(action) }
}

final class OperatorTests: XCTestCase {
    let profile = PageSnapshot(url: "https://www.linkedin.com/in/someone", title: "Someone | LinkedIn", text: "Climate tech investor", elements: [
        PageElement(id: "e1", role: "button", label: "Send now", visible: true),
        PageElement(id: "e2", role: "textbox", label: "Add a note", visible: true),
        PageElement(id: "e3", role: "button", label: "More actions", visible: true),
        PageElement(id: "e4", role: "submit", label: "Save", visible: true)
    ])

    func freshBudget(limit: Int = 10, now: @escaping () -> Date = Date.init) -> OutwardBudget {
        OutwardBudget(defaults: UserDefaults(suiteName: "OperatorTests.\(UUID())")!, limit: limit, now: now)
    }

    func testRiskClassification() {
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "e1"), snapshot: profile), .outward)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .type, elementID: "e2", text: "Hi"), snapshot: profile), .safe)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "e3"), snapshot: profile), .safe)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "e4"), snapshot: profile), .outward, "form submit buttons are outward whatever their label")
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "e99"), snapshot: profile), .outward, "unknown elements fail closed")
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .navigate, url: "https://www.linkedin.com/feed"), snapshot: profile), .safe)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .navigate, url: "https://evil.example/?q=data"), snapshot: profile), .outward)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .navigate, url: "https://docs.example.com/guide"), snapshot: profile), .safe, "plain links are browsing")
        let nav = PageSnapshot(url: profile.url, title: "", text: "", elements: [
            PageElement(id: "n1", role: "link", label: "Messaging", visible: true), PageElement(id: "n2", role: "link", label: "Send", visible: true)])
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "n1"), snapshot: nav), .safe)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .click, elementID: "n2"), snapshot: nav), .outward)
    }

    func testActionDecodingToleratesFencesAndNulls() throws {
        let action = try OperatorAction.decode("```json\n{\"kind\":\"ask_user\",\"element_id\":null,\"text\":\"Which interest?\",\"url\":null,\"reason\":\"unclear\"}\n```")
        XCTAssertEqual(action, OperatorAction(kind: .askUser, text: "Which interest?", reason: "unclear"))
        XCTAssertEqual(try OperatorAction.decode(#"{"kind":"click","element_id":"e1"}"#).elementID, "e1")
        XCTAssertThrowsError(try OperatorAction.decode(#"{"kind":"hack"}"#))
    }

    func testDailyCapResetsNextDay() {
        var day = Date(timeIntervalSince1970: 1_800_000_000)
        let budget = freshBudget(limit: 2, now: { day })
        budget.record(); budget.record()
        XCTAssertEqual(budget.remaining, 0)
        day += 86_400
        XCTAssertEqual(budget.remaining, 2)
    }

    @MainActor
    func testDeclinedOutwardActionIsNotPerformed() async throws {
        let page = FakePage(profile)
        var script = [OperatorAction(kind: .type, elementID: "e2", text: "Hi, I saw your climate tech work."), OperatorAction(kind: .click, elementID: "e1")]
        let planner = OperatorPlanner(goal: "Send a note", chrome: page, budget: freshBudget(), settle: .zero) { _, _, _ in script.removeFirst() }
        var asked: [String] = []
        let summary = try await planner.run(confirm: { _, description in asked.append(description); return false }, progress: { _ in })
        XCTAssertEqual(page.performed.map(\.kind), [.type])
        XCTAssertEqual(asked.count, 1)
        XCTAssertTrue(asked[0].contains("Send now") && asked[0].contains("climate tech"))
        XCTAssertTrue(summary.contains("Nothing was sent"))
    }

    @MainActor
    func testApprovedOutwardActionIsPerformedAndCounted() async throws {
        let page = FakePage(profile), budget = freshBudget()
        var script = [OperatorAction(kind: .click, elementID: "e1"), OperatorAction(kind: .done, text: "Sent.")]
        let planner = OperatorPlanner(goal: "Send", chrome: page, budget: budget, settle: .zero) { _, _, _ in script.removeFirst() }
        let summary = try await planner.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertEqual(page.performed.map(\.elementID), ["e1"])
        XCTAssertEqual(summary, "Sent.")
        XCTAssertEqual(budget.used, 1)
    }

    @MainActor
    func testExhaustedBudgetStopsWithoutAsking() async throws {
        let page = FakePage(profile), budget = freshBudget(limit: 1)
        budget.record()
        let planner = OperatorPlanner(goal: "Send", chrome: page, budget: budget, settle: .zero) { _, _, _ in OperatorAction(kind: .click, elementID: "e1") }
        let summary = try await planner.run(confirm: { _, _ in XCTFail("should not ask"); return true }, progress: { _ in })
        XCTAssertTrue(page.performed.isEmpty)
        XCTAssertTrue(summary.contains("daily limit"))
    }

    @MainActor
    func testStepCap() async throws {
        let page = FakePage(profile)
        let planner = OperatorPlanner(goal: "Browse", chrome: page, budget: freshBudget(), settle: .zero) { _, _, _ in OperatorAction(kind: .scroll, text: "down") }
        _ = try await planner.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertEqual(page.performed.count, planner.maxSteps)
    }

    @MainActor
    func testVanishedElementRereadsInsteadOfStopping() async throws {
        final class ChangingPage: PageDriving, @unchecked Sendable {
            let page: PageSnapshot; var reads = 0, misses = 1
            init(_ page: PageSnapshot) { self.page = page }
            func snapshot() async throws -> PageSnapshot { reads += 1; return page }
            func perform(_ action: OperatorAction) async throws { if misses > 0 { misses -= 1; throw PageChanged() } }
        }
        let page = ChangingPage(profile)
        var script = [OperatorAction(kind: .click, elementID: "e3"), OperatorAction(kind: .click, elementID: "e3"), OperatorAction(kind: .done, text: "Opened.")]
        let planner = OperatorPlanner(goal: "Open more actions", chrome: page, budget: freshBudget(), settle: .zero) { _, _, _ in script.removeFirst() }
        let summary = try await planner.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertEqual(summary, "Opened.")
        XCTAssertEqual(page.reads, 3, "the page is read again after the element vanished")
    }

    @MainActor
    func testNotesAreKeptForLaterSteps() async throws {
        let page = FakePage(profile)
        var seen: [[String]] = []
        var script = [OperatorAction(kind: .note, text: "German Shepherds: herding dogs, Germany, 1899 (Wikipedia)"),
                      OperatorAction(kind: .newTab, url: "https://docs.new"), OperatorAction(kind: .done, text: "Written.")]
        let planner = OperatorPlanner(goal: "Research dogs and write a doc", chrome: page, budget: freshBudget(), settle: .zero) { _, _, history in seen.append(history); return script.removeFirst() }
        _ = try await planner.run(confirm: { _, _ in XCTFail("research steps need no approval"); return true }, progress: { _ in })
        XCTAssertTrue(seen[1].contains { $0.contains("Noted: German Shepherds") })
        XCTAssertEqual(page.performed.map(\.kind), [.newTab], "a note is not a browser action")
    }

    func testTabActionsAndParsing() {
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .newTab, url: "https://docs.new"), snapshot: profile), .safe)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .newTab, url: "https://evil.example/?q=data"), snapshot: profile), .outward)
        XCTAssertEqual(ActionRisk.classify(OperatorAction(kind: .switchTab, text: "2"), snapshot: profile), .safe)
        let tabs = ChromeOperator.parseTabs("1\tNew tab\tchrome://newtab/\tfalse\n2\tGerman Shepherd - Wikipedia\thttps://en.wikipedia.org/wiki/German_Shepherd\ttrue\n")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[1], BrowserTab(index: 2, title: "German Shepherd - Wikipedia", url: "https://en.wikipedia.org/wiki/German_Shepherd", active: true))
        XCTAssertEqual(try OperatorAction.decode(#"{"kind":"switch_tab","text":"2"}"#).kind, .switchTab)
    }

    @MainActor
    func testYoloSkipsApprovalButNotPayments() async throws {
        let shop = PageSnapshot(url: "https://shop.example/cart", title: "", text: "", elements: [
            PageElement(id: "s1", role: "button", label: "Send message", visible: true), PageElement(id: "p1", role: "button", label: "Pay now", visible: true)])
        let page = FakePage(shop)
        var script = [OperatorAction(kind: .click, elementID: "s1"), OperatorAction(kind: .click, elementID: "p1")]
        let planner = OperatorPlanner(goal: "Message and pay", chrome: page, budget: freshBudget(), settle: .zero) { _, _, _ in script.removeFirst() }
        planner.autoApprove = true
        var asked: [String] = []
        let summary = try await planner.run(confirm: { _, d in asked.append(d); return false }, progress: { _ in })
        XCTAssertEqual(page.performed.map(\.elementID), ["s1"], "the send ran without asking")
        XCTAssertEqual(asked.count, 1, "the payment still asked")
        XCTAssertTrue(asked[0].contains("Pay now") && summary.contains("Nothing was sent"))
    }

    @MainActor
    func testNextRunStartsFromEarlierNotes() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let memory = OperatorMemory(file: file)
        var first = [OperatorAction(kind: .note, text: "German Shepherds were bred in 1899 by Max von Stephanitz (Wikipedia)"), OperatorAction(kind: .done, text: "Researched.")]
        let research = OperatorPlanner(goal: "Research German Shepherds", chrome: FakePage(profile), budget: freshBudget(), settle: .zero) { _, _, _ in first.removeFirst() }
        research.memory = memory
        _ = try await research.run(confirm: { _, _ in true }, progress: { _ in })
        var seen: [String] = []
        let write = OperatorPlanner(goal: "Write it up as a Google Doc", chrome: FakePage(profile), budget: freshBudget(), settle: .zero) { _, _, h in seen = h; return OperatorAction(kind: .done, text: "ok") }
        write.memory = memory
        _ = try await write.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertTrue(seen.contains { $0.contains("Earlier note: German Shepherds were bred in 1899") })
        XCTAssertTrue(seen.contains { $0.contains("linkedin.com") }, "pages from the earlier run are remembered")
    }

    @MainActor
    func testEmptyQuestionDoesNotStopTheRun() async throws {
        var script = [OperatorAction(kind: .askUser, text: nil, reason: ""), OperatorAction(kind: .done, text: "Finished.")]
        var seen: [String] = []
        let planner = OperatorPlanner(goal: "Research", chrome: FakePage(profile), budget: freshBudget(), settle: .zero) { _, _, h in seen = h; return script.removeFirst() }
        let summary = try await planner.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertEqual(summary, "Finished.")
        XCTAssertTrue(seen.contains { $0.contains("without a question") })
    }

    @MainActor
    func testYoloOnlyStopsForThingsThePersonMustDo() async throws {
        var script = [OperatorAction(kind: .askUser, text: "Which breed should I focus on?"), OperatorAction(kind: .askUser, text: "Please log in to Google to continue.")]
        let planner = OperatorPlanner(goal: "Research dogs", chrome: FakePage(profile), budget: freshBudget(), settle: .zero) { _, _, _ in script.removeFirst() }
        planner.autoApprove = true
        let summary = try await planner.run(confirm: { _, _ in true }, progress: { _ in })
        XCTAssertEqual(summary, "Please log in to Google to continue.")
    }

    func testAppleScriptErrorsMapToGuidance() {
        XCTAssertTrue(ChromeOperator.describe(error: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)").contains("Automation"))
        XCTAssertTrue(ChromeOperator.describe(error: "Executing JavaScript through AppleScript is turned off. (12)").contains("Allow JavaScript from Apple Events"))
    }
}

@MainActor
final class AllowedSitesTests: XCTestCase {
    func testSitesComeFromTheSkillMarkdown() {
        let skill = "# Actions\nHelp.\n\n## Allowed websites\nNotes.\n- https://www.LinkedIn.com/feed\n- notion.so\n- not a site\n\n## Sounds\n- done: mrrp"
        XCTAssertEqual(SkillSites.parse(skill), ["linkedin.com", "notion.so"])
        XCTAssertTrue(SkillSites.parse("# Explain").isEmpty)
        XCTAssertTrue(OperatorPlanner.isAllowed("https://www.linkedin.com/in/x", sites: ["linkedin.com"]))
        XCTAssertFalse(OperatorPlanner.isAllowed("https://notlinkedin.com", sites: ["linkedin.com"]))
    }
    func testAllowedSiteSendsWithoutAskingButOthersStillAsk() async throws {
        let snapshot = PageSnapshot(url: "https://www.linkedin.com/in/sam", title: "", text: "", elements: [PageElement(id: "e1", role: "button", label: "Send", visible: true)])
        let page = FakePage(snapshot)
        var asked = 0
        let budget = OutwardBudget(defaults: UserDefaults(suiteName: "AllowedSitesTests.\(UUID())")!)
        var script = [OperatorAction(kind: .click, elementID: "e1"), OperatorAction(kind: .done, text: "Sent.")]
        let planner = OperatorPlanner(goal: "Send", chrome: page, budget: budget, settle: .zero, allowedSites: ["linkedin.com"]) { _, _, _ in script.removeFirst() }
        _ = try await planner.run(confirm: { _, _ in asked += 1; return false }, progress: { _ in })
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(page.performed.count, 1)
        XCTAssertEqual(budget.used, 1, "allowed sends still count toward the daily cap")
    }
}
