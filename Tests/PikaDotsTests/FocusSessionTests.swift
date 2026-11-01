import XCTest
@testable import PikaDots

final class FocusSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testDriftCountsOncePerStretchAfterThreshold() {
        var focus = FocusSession(label: "“proposal”", length: 25 * 60, startedAt: t0)
        XCTAssertFalse(focus.record(onTask: true, at: t0.addingTimeInterval(2)))
        XCTAssertFalse(focus.record(onTask: false, at: t0.addingTimeInterval(4)))
        XCTAssertFalse(focus.record(onTask: false, at: t0.addingTimeInterval(10)))
        XCTAssertTrue(focus.record(onTask: false, at: t0.addingTimeInterval(14)))
        XCTAssertFalse(focus.record(onTask: false, at: t0.addingTimeInterval(20)), "same stretch counts once")
        focus.record(onTask: true, at: t0.addingTimeInterval(22))
        focus.record(onTask: false, at: t0.addingTimeInterval(24))
        XCTAssertTrue(focus.record(onTask: false, at: t0.addingTimeInterval(34)))
        XCTAssertEqual(focus.drifts, 2)
    }

    func testStepsAreCappedAndPausesDoNotCount() {
        var focus = FocusSession(label: "x", length: nil, startedAt: t0)
        focus.record(onTask: true, at: t0.addingTimeInterval(600)) // laptop slept
        XCTAssertEqual(focus.onTask, 10)
        focus.resume(at: t0.addingTimeInterval(900))
        focus.record(onTask: true, at: t0.addingTimeInterval(902))
        XCTAssertEqual(focus.onTask, 12)
        XCTAssertNil(focus.remaining())
        XCTAssertFalse(focus.isOver())
    }

    func testSessionEndsAtLengthAndRecapReadsWell() {
        var focus = FocusSession(label: "“proposal”", length: 60, startedAt: t0)
        for step in 1...8 { focus.record(onTask: step != 5, at: t0.addingTimeInterval(Double(step) * 10)) }
        XCTAssertTrue(focus.isOver())
        XCTAssertEqual(focus.recapShort, "Focus done · 1 min on task · 0 drifts")
        XCTAssertTrue(focus.recapDetail.hasPrefix("“proposal”\n"))
        XCTAssertLessThanOrEqual(NotificationCopy.short(focus.recapShort).count, 100)
    }

    func testLabelPrefersPurposeOverDefault() {
        XCTAssertEqual(FocusSession.label(purpose: "Keep me focused.", defaultPurpose: "Keep me focused.", appName: "Notes"), "Notes")
        XCTAssertEqual(FocusSession.label(purpose: " finish the proposal ", defaultPurpose: "d", appName: "Notes"), "“finish the proposal”")
        XCTAssertTrue(FocusSession.label(purpose: String(repeating: "a", count: 80), defaultPurpose: "", appName: "").hasSuffix("…”"))
    }
}

final class FocusVerdictTests: XCTestCase {
    func testParsesCategoryAndRelevance() throws {
        let verdict = try XCTUnwrap(FocusVerdict.parse(#"```json {"category":"learning","relevance":"related","message":""} ```"#))
        XCTAssertEqual(verdict.category, .learning)
        XCTAssertTrue(verdict.onTask, "related content is not a distraction")
        XCTAssertEqual(verdict.label, "Learning · related")
        let off = try XCTUnwrap(FocusVerdict.parse(#"{"category":"entertainment","relevance":"off_task","message":"Back to the proposal?"}"#))
        XCTAssertFalse(off.onTask)
        XCTAssertNil(FocusVerdict.parse("NO_NUDGE"))
        XCTAssertNil(FocusVerdict.parse(#"{"category":"vibes","relevance":"on_task","message":""}"#))
    }

    func testGenericPurposeNeverExcusesEntertainment() throws {
        let lenient = try XCTUnwrap(FocusVerdict.parse(#"{"category":"entertainment","relevance":"on_task","message":"Enjoy the video"}"#))
        let fixed = lenient.adjusted(genericPurpose: true)
        XCTAssertFalse(fixed.onTask)
        XCTAssertEqual(fixed.message, "", "an off-task cat should not say enjoy the video")
        XCTAssertTrue(lenient.adjusted(genericPurpose: false).onTask, "a named purpose may legitimately involve entertainment")
        let lecture = try XCTUnwrap(FocusVerdict.parse(#"{"category":"learning","relevance":"related","message":""}"#))
        XCTAssertEqual(lecture.adjusted(genericPurpose: true), lecture)
    }

    func testVerdictCacheExpires() throws {
        var cache = TitleVerdicts()
        let now = Date()
        cache.store(try XCTUnwrap(FocusVerdict.parse(#"{"category":"work","relevance":"on_task","message":""}"#)), for: "k", at: now)
        XCTAssertNotNil(cache.verdict(for: "k", at: now.addingTimeInterval(60)))
        XCTAssertNil(cache.verdict(for: "k", at: now.addingTimeInterval(TitleVerdicts.ttl + 1)))
    }

    func testTitleKeyIgnoresBrowserSuffixAndUnreadCounts() {
        let a = WindowContext(windowID: 1, appName: "Google Chrome", title: "(3) Inbox - Gmail - Google Chrome", bounds: .zero)
        let b = WindowContext(windowID: 2, appName: "Google Chrome", title: "(12) Inbox - Gmail - Google Chrome", bounds: .zero)
        XCTAssertEqual(TitleVerdicts.key(for: a), TitleVerdicts.key(for: b))
        XCTAssertTrue(FocusWatchPolicy.isYouTube("(2) Lo-fi beats - YouTube - Google Chrome"))
    }

    func testFocusCheckSchemaListsEveryCategory() {
        let style = OpenAIResponder.style(for: .focusCheck)
        for category in FocusVerdict.Category.allCases where category != .other { XCTAssertTrue(style.contains(category.rawValue), category.rawValue) }
        XCTAssertTrue(OpenAIResponder.style(for: .ask).contains("70 words"))
    }
}

final class RuntimeHelperTests: XCTestCase {
    func testImageTypeAndTransientStatuses() {
        XCTAssertEqual(OpenAIResponder.imageMIME(Data([0x89, 0x50, 0x4E, 0x47, 1])), "image/png")
        XCTAssertEqual(OpenAIResponder.imageMIME(Data([0xFF, 0xD8, 0xFF])), "image/jpeg")
        XCTAssertTrue(OpenAIResponder.isTransient(status: 503))
        XCTAssertFalse(OpenAIResponder.isTransient(status: 429), "quota errors are not retried")
        XCTAssertFalse(OpenAIResponder.isTransient(status: 401))
    }

    func testTabScriptOnlyClosesYouTubeInSupportedBrowsers() throws {
        let chrome = try XCTUnwrap(BrowserTabs.script(bundleID: "com.google.Chrome"))
        XCTAssertTrue(chrome.contains("contains \"youtube.com\""))
        XCTAssertTrue(chrome.contains("active tab"))
        XCTAssertTrue(try XCTUnwrap(BrowserTabs.script(bundleID: "com.apple.Safari")).contains("current tab"))
        XCTAssertNil(BrowserTabs.script(bundleID: "org.mozilla.firefox"))
    }

    func testSessionLengthsAndReplyCardSizing() {
        XCTAssertEqual(SessionLength.options(for: "chill"), [1, 2, 5, 10])
        XCTAssertNil(SessionLength.options(for: "explain"))
        XCTAssertEqual(SessionLength.label(0), "∞")
        XCTAssertEqual(SessionLength.defaultMinutes(for: "chill"), 2)
        let short = ReplyCard.height("One line."), long = ReplyCard.height(String(repeating: "A longer answer that wraps. ", count: 60))
        XCTAssertLessThan(short, long)
        XCTAssertLessThanOrEqual(long, 220 + 56 + ReplyCard.tail, "long answers scroll inside a capped card")
        XCTAssertLessThanOrEqual(ReplyCard.speechWidth(String(repeating: "word ", count: 30)), 280)
    }

    func testLayoutKeepsReplyCardOnScreenBelowCat() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = AttachmentLayout(window: CGRect(x: 1300, y: 100, width: 140, height: 500), screen: screen, expandedHeight: 32, replyHeight: 120)
        XCTAssertTrue(screen.contains(layout.reply))
        XCTAssertLessThanOrEqual(layout.reply.maxY, 600, "bubble hangs just below the window edge")
    }
}

@MainActor
final class CatVoiceTests: XCTestCase {
    func testEachSoundIsAudibleBoundedAndAValidWav() {
        for sound in CatVoice.Sound.allCases {
            let samples = CatVoice.samples(sound)
            XCTAssertGreaterThan(samples.count, 10_000)
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.5); XCTAssertLessThanOrEqual(peak, 1)
            XCTAssertLessThan(abs(samples.last ?? 1), 0.05, "fades out instead of clicking")
            let wav = CatVoice.wav(samples)
            XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertEqual(wav.count, 44 + samples.count * 2)
        }
    }
}

@MainActor
final class ChillLengthTests: XCTestCase {
    func testBreakLengthOverrideAndFinishCallback() async throws {
        let monitor = SessionMonitor(interval: .milliseconds(5), breakLength: 999, keyboardIdle: { 100 })
        var messages: [String] = [], finished = 0
        monitor.start(agentID: "chill", targetApp: "Notes", targetPID: 1, breakLength: 0.03,
                      onMessage: { messages.append($0) }, onFinish: { finished += 1 })
        try await Task.sleep(for: .milliseconds(120)); monitor.stop()
        XCTAssertEqual(messages, ["Break complete. Ready when you are."])
        XCTAssertEqual(finished, 1)
    }
}

final class SkillSoundsTests: XCTestCase {
    private let skill = "# Cat\nBe kind.\n\n## Sounds\nNotes for the user.\n- start: mrrp\n* Drift: MEOW\n- warning: purr\n- done:yowl\n\n## Style\nShort."
    func testSoundsComeOnlyFromTheMarkdownSection() {
        XCTAssertEqual(SkillSounds.parse(skill), [.start: .mrrp, .drift: .meow, .done: .yowl], "unknown sounds are ignored")
        XCTAssertTrue(SkillSounds.parse("# Explain\n- drift: meow").isEmpty, "no Sounds section means silent")
    }
    func testSoundsSectionIsNotSentToTheModel() {
        let stripped = SkillSounds.stripped(skill)
        XCTAssertFalse(stripped.contains("mrrp"))
        XCTAssertTrue(stripped.contains("Be kind.") && stripped.contains("## Style\nShort."))
        XCTAssertEqual(SkillSounds.stripped("# Plain"), "# Plain")
    }
    func testBundledSkillsDeclareTheirVoices() {
        let agents = SkillLoader.load()
        XCTAssertEqual(SkillSounds.parse(agents.first { $0.id == "focus" }!.skillText)[.warning], .yowl)
        XCTAssertEqual(SkillSounds.parse(agents.first { $0.id == "chill" }!.skillText)[.done], .mrrp)
        XCTAssertTrue(SkillSounds.parse(agents.first { $0.id == "explain" }!.skillText).isEmpty)
    }
}
