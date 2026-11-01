import SwiftUI

@main
enum PikaDotsApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = StatusBarController()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onResignKey: (() -> Void)?
    override func resignKey() { super.resignKey(); onResignKey?() }
}

@MainActor
final class AttachedSession {
    let state: BubbleState
    let panel: CompanionPanel
    let dotPanel: CompanionPanel
    let replyPanel: CompanionPanel
    var replyHeight: CGFloat = 0
    var watchTask: Task<Void, Never>?
    var task: Task<Void, Never>?
    var missingFrames = 0
    var lastDistraction = Date.distantPast
    var snoozedUntil = Date.distantPast
    var retryAfter = Date.distantPast
    var lastErrorNotice = Date.distantPast
    // Focus: the running session, cached page verdicts, and the YouTube escalation ladder.
    var focus: FocusSession?
    var verdicts = TitleVerdicts()
    var pendingKey = ""
    var pendingSince = Date.distantPast
    var lastTip = Date.distantPast
    var youtubeSince: Date?
    var youtubeLevel = 0
    // Actions: the run waiting on the user's Approve/Stop.
    var approval: CheckedContinuation<Bool, Never>?
    /// Where the cat sits along the window's top edge (0 left … 1 right), remembered per app.
    var anchor: CGFloat = 0.5
    var speechTask: Task<Void, Never>?
    init(state: BubbleState, panel: CompanionPanel, dotPanel: CompanionPanel, replyPanel: CompanionPanel) {
        self.state = state; self.panel = panel; self.dotPanel = dotPanel; self.replyPanel = replyPanel
    }
}

@MainActor
final class AppController: ObservableObject {
    @Published var agents = SkillLoader.load()
    var onManage: (() -> Void)?
    var onSettings: (() -> Void)?
    private let store = CompanionStore()
    var onAttachment: (() -> Void)?
    @Published var notice = ""
    private let responder: any AgentResponding = OpenAIResponder()
    private let monitor = SessionMonitor()
    private var monitorOwner: String?
    private let nudges = NudgePresenter()
    private let intervention = InterventionPresenter()
    @Published private var sessions: [String: AttachedSession] = [:]
    var attachedCount: Int { sessions.count }
    func attachedApp(_ id: String) -> String? { sessions[id]?.state.window?.appName }
    private var followTask: Task<Void, Never>?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        do { agents = try store.load() } catch { notice = "Could not load saved companions: " + error.localizedDescription }
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                self?.updateAttachments()
            }
        }
    }

    func saveAttachments() {
        let snapshots = sessions.values.compactMap { session -> AttachmentSnapshot? in
            guard let target = session.state.window else { return nil }
            return AttachmentSnapshot(agentID: session.state.agent.id, windowID: target.windowID, ownerPID: target.ownerPID, prompt: session.state.prompt, running: session.state.watching || monitorOwner == session.state.agent.id, startedAt: session.state.startedAt, snoozedUntil: session.snoozedUntil)
        }
        if let data = try? JSONEncoder().encode(snapshots) { UserDefaults.standard.set(data, forKey: "attachments.v1") }
    }
    func restoreAttachments() {
        guard let data = UserDefaults.standard.data(forKey: "attachments.v1"), let snapshots = try? JSONDecoder().decode([AttachmentSnapshot].self, from: data) else { return }
        let windows = WindowFinder.windows()
        for snapshot in snapshots {
            guard let agent = agents.first(where: { $0.id == snapshot.agentID }), let window = windows.first(where: { $0.windowID == snapshot.windowID && $0.ownerPID == snapshot.ownerPID }) else { continue }
            attach(agent, to: window, restored: snapshot)
        }
    }
    func screenAccessRecovered() {
        for session in sessions.values where session.state.watching {
            session.retryAfter = .distantPast; session.state.supervisionError = false
            session.state.supervisionStatus = "Ready · checks resume in the attached app"
        }
    }

    func saveCompanion(_ agent: AgentDefinition) throws {
        var updated = agents
        if let i = updated.firstIndex(where: { $0.id == agent.id }) { updated[i] = agent }
        else { updated.append(agent) }
        try store.save(updated)
        close(agent.id)
        agents = updated
    }
    func deleteCompanion(_ id: String) throws {
        let updated = agents.filter { $0.id != id }
        try store.save(updated)
        close(id); agents = updated
    }
    func manageCompanions() { onManage?() }
    func showSettings() { onSettings?() }
    func testNotification() {
        if let agent = agents.first { nudges.show("You’re all set.", agent: agent) }
    }

    func attachToFrontmost(_ agent: AgentDefinition) {
        guard let window = WindowFinder.windows().first else { report("Open a window, then drag a dot onto it.", agent); return }
        attach(agent, to: window)
    }

    func attach(_ agent: AgentDefinition, at point: NSPoint) {
        guard let window = WindowFinder.window(at: point) else { report("Drop onto an application window, such as Chrome or Notes.", agent); return }
        attach(agent, to: window)
    }

    private func report(_ message: String, _ agent: AgentDefinition) {
        notice = message
        nudges.show(message, agent: agent)
    }

    private func attach(_ agent: AgentDefinition, to window: WindowContext, restored: AttachmentSnapshot? = nil) {
        notice = ""
        close(agent.id)
        // One companion per target keeps the purpose field readable.
        let replaced = sessions.filter { $0.value.state.window?.windowID == window.windowID }.map(\.key)
        for id in replaced { close(id) }
        let state = BubbleState(agent: agent, window: window)
        state.prompt = restored?.prompt ?? UserDefaults.standard.string(forKey: purposeKey(agent, window)) ?? ""
        state.startedAt = restored?.startedAt
        let panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .normal; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let dotPanel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 48, height: 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        dotPanel.backgroundColor = .clear; dotPanel.isOpaque = false; dotPanel.hasShadow = false
        dotPanel.level = .normal; dotPanel.isReleasedWhenClosed = false
        dotPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        dotPanel.hidesOnDeactivate = false
        dotPanel.becomesKeyOnlyIfNeeded = true
        dotPanel.contentView = NSHostingView(rootView: PerchedDot(state: state,
            onDrop: { [weak self] in self?.dropPerched(agent, at: $0) },
            toggle: { [weak self, weak state] in
                guard let self, let state else { return }
                state.expanded.toggle()
                self.updateAttachments()
                if state.expanded { self.sessions[agent.id]?.panel.makeKeyAndOrderFront(nil) }
            }, dismiss: { [weak self] in self?.dismissCompanion(agent.id) },
            settings: { [weak self] in self?.showSettings() },
            toggleWatch: { [weak self, weak state] in if let state { self?.toggleWatch(state) } },
            checkNow: { [weak self, weak state] in if let state { self?.checkNow(state) } },
            talk: { [weak self, weak state] in if let state { self?.talk(state) } },
            perch: { [weak self] in self?.setPerch(agent.id, anchor: $0) }))
        let replyPanel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: ReplyCard.width, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        replyPanel.backgroundColor = .clear; replyPanel.isOpaque = false; replyPanel.hasShadow = true
        replyPanel.level = .normal; replyPanel.isReleasedWhenClosed = false
        replyPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        replyPanel.hidesOnDeactivate = false
        replyPanel.contentView = NSHostingView(rootView: ReplyCard(state: state, close: { [weak self, weak state] in
            // Closing the card while an action waits counts as Stop.
            self?.resolveApproval(false, for: agent.id); state?.reply = nil
        }, decide: { [weak self] in self?.resolveApproval($0, for: agent.id) },
           dismissSpeech: { [weak self, weak state] in self?.sessions[agent.id]?.speechTask?.cancel(); state?.speech = nil }))
        panel.onResignKey = { [weak state] in state?.expanded = false }
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: TaskBubble(state: state,
            submit: { [weak self, weak state] in if let state { self?.submitFromPill(state) } },
            close: { [weak self] in self?.close(agent.id) },
            settings: { [weak self] in self?.showSettings() },
            toggleWatch: { [weak self, weak state] in if let state { self?.toggleWatch(state) } },
            talk: { [weak self, weak state] in if let state { self?.talk(state) } }))
        state.expanded = agent.mode == .promptable
        sessions[agent.id] = AttachedSession(state: state, panel: panel, dotPanel: dotPanel, replyPanel: replyPanel)
        sessions[agent.id]?.snoozedUntil = restored?.snoozedUntil ?? .distantPast
        sessions[agent.id]?.anchor = UserDefaults.standard.object(forKey: perchKey(agent, window)) as? CGFloat ?? 0.5
        position(sessions[agent.id]!, window: window)
        dotPanel.order(.above, relativeTo: Int(window.windowID))
        if state.expanded { panel.makeKeyAndOrderFront(nil) }
        sampleAppearance(state)
        if agent.mode == .supervisor && (restored?.running ?? true) {
            if state.prompt.isEmpty { state.prompt = agent.defaultPurpose }
            state.purpose = state.prompt
            state.expanded = false
            panel.orderOut(nil)
            // Focus and Chill replace each other inside beginFocus/startChill.
            toggleWatch(state)
        }
        saveAttachments()
        onAttachment?()
    }

    private func sampleAppearance(_ state: BubbleState) {
        guard CGPreflightScreenCaptureAccess(), let window = state.window else { return }
        Task { [weak state] in
            guard let data = try? await WindowCapture.capture(window),
                  let bitmap = NSBitmapImageRep(data: data) else { return }
            var samples: [(NSColor, CGFloat)] = []
            for x in stride(from: bitmap.pixelsWide / 5, to: bitmap.pixelsWide * 4 / 5, by: max(1, bitmap.pixelsWide / 30)) {
                guard let c = bitmap.colorAt(x: x, y: min(8, bitmap.pixelsHigh - 1))?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.9 else { continue }
                samples.append((c, c.redComponent * 0.2126 + c.greenComponent * 0.7152 + c.blueComponent * 0.0722))
            }
            samples.sort { $0.1 < $1.1 }
            guard !samples.isEmpty else { return }
            let sample = samples[samples.count / 2]
            state?.windowColor = sample.0
            state?.windowIsDark = sample.1 < 0.5
        }
    }

    private func purposeKey(_ agent: AgentDefinition, _ window: WindowContext) -> String {
        let bundle = NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier ?? window.appName
        return "purpose.\(agent.id).\(bundle)"
    }

    private func perchKey(_ agent: AgentDefinition, _ window: WindowContext) -> String {
        "perch." + purposeKey(agent, window).dropFirst("purpose.".count)
    }

    private func setPerch(_ id: String, anchor: CGFloat) {
        guard let session = sessions[id], let window = session.state.window else { return }
        session.anchor = min(1, max(0, anchor))
        UserDefaults.standard.set(Double(session.anchor), forKey: perchKey(session.state.agent, window))
        position(session, window: window)
    }

    /// Dragging a perched cat slides it along its own window's top edge; dropping it on a
    /// different window moves it there; dropping it on the desktop leaves it where it was.
    private func dropPerched(_ agent: AgentDefinition, at point: NSPoint) {
        guard let session = sessions[agent.id], let target = session.state.window else { attach(agent, at: point); return }
        let rect = WindowFinder.appRect(target.bounds)
        let edgeBand = CGRect(x: rect.minX - 40, y: rect.maxY - 80, width: rect.width + 80, height: 150)
        if edgeBand.contains(point) || rect.contains(point) {
            setPerch(agent.id, anchor: (point.x - rect.minX) / max(1, rect.width))
        } else if let other = WindowFinder.window(at: point), other.windowID != target.windowID {
            attach(agent, to: other)
        }
    }

    private func catVisible(_ session: AttachedSession) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return session.dotPanel.isVisible && (front == session.state.window?.ownerPID || front == ProcessInfo.processInfo.processIdentifier)
    }

    /// The cat says it in its speech bubble when it's on screen; otherwise it becomes a notification.
    private func say(_ text: String, _ state: BubbleState) {
        guard let session = sessions[state.agent.id], catVisible(session), state.reply == nil else {
            nudges.show(text, agent: state.agent); return
        }
        nudges.dismiss()
        let line = NotificationCopy.short(text)
        state.speech = line
        session.replyHeight = ReplyCard.speechHeight(line)
        if let window = state.window { position(session, window: window) }
        updateAttachments()
        session.speechTask?.cancel()
        session.speechTask = Task { [weak state] in
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            if state?.speech == line { state?.speech = nil }
        }
    }

    private func position(_ session: AttachedSession, window: WindowContext) {
        let rect = WindowFinder.appRect(window.bounds)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? rect
        let height: CGFloat = 32
        let layout = AttachmentLayout(window: rect, screen: visible, expandedHeight: height, replyHeight: session.replyHeight, anchor: session.anchor, fullScreen: screen?.frame,
                                      seat: 2 + 40 * CharacterArtwork.footInset(for: session.state.agent.id),
                                      tabWidth: SessionLength.pillWidth(for: session.state.agent.id))
        if session.state.peeking != layout.peeking { session.state.peeking = layout.peeking }
        let tailX = layout.dot.midX - layout.reply.minX
        if abs(session.state.tailX - tailX) > 0.5 { session.state.tailX = tailX }
        if session.panel.frame != layout.tab { session.panel.setFrame(layout.tab, display: true) }
        if session.dotPanel.frame != layout.dot { session.dotPanel.setFrame(layout.dot, display: true) }
        if session.replyHeight > 0, session.replyPanel.frame != layout.reply { session.replyPanel.setFrame(layout.reply, display: true) }
    }

    private func updateAttachments() {
        guard !sessions.isEmpty else { return }
        let windows = WindowFinder.windows()
        for session in sessions.values {
            guard let old = session.state.window else { continue }
            guard let current = windows.first(where: { $0.windowID == old.windowID && $0.ownerPID == old.ownerPID }) else {
                session.missingFrames += 1
                if session.missingFrames > 15 { session.panel.orderOut(nil); session.dotPanel.orderOut(nil); session.replyPanel.orderOut(nil) }
                continue
            }
            session.missingFrames = 0
            // Assign only on change: every write republishes both hosting views.
            if current != old { session.state.window = current }
            let activity = TypingActivity.summary(for: current.ownerPID)
            if activity != session.state.activity { session.state.activity = activity }
            position(session, window: current)
            // If another window covers the spot under the cat's paws, its own window is hidden there,
            // so hide the cat rather than let it float over unrelated windows.
            let paws = NSPoint(x: session.dotPanel.frame.midX, y: WindowFinder.appRect(current.bounds).maxY - 2)
            if windows.prefix(while: { $0.windowID != current.windowID }).contains(where: { WindowFinder.appRect($0.bounds).contains(paws) }) {
                session.panel.orderOut(nil); session.dotPanel.orderOut(nil); session.replyPanel.orderOut(nil)
                continue
            }
            // Normal-level panels follow the target's actual window-server order,
            // rather than vanishing whenever another application gains focus.
            session.dotPanel.order(.above, relativeTo: Int(current.windowID))
            if session.state.expanded {
                session.panel.order(.above, relativeTo: session.dotPanel.windowNumber)
            } else { session.panel.orderOut(nil) }
            if session.state.reply != nil || session.state.speech != nil {
                session.replyPanel.order(.above, relativeTo: session.dotPanel.windowNumber)
            } else if session.replyPanel.isVisible { session.replyPanel.orderOut(nil) }
        }
    }

    private func toggleWatch(_ state: BubbleState) {
        guard let session = sessions[state.agent.id] else { return }
        if state.agent.id == "chill" {
            if state.watching { endChill(state, message: "Break ended early") } else { startChill(state) }
            return
        }
        if state.watching {
            state.watching = false; state.supervisionStatus = "Paused by you"; session.watchTask?.cancel(); session.task?.cancel()
            intervention.dismiss(owner: state.agent.id)
            if monitorOwner == state.agent.id { monitor.stop(); monitorOwner = nil; nudges.dismiss() }
            if state.agent.id == "focus" { finishFocus(session, completed: false) }
            saveAttachments()
            return
        }
        guard !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            say("Set a purpose first.", state); return
        }
        state.watching = true
        saveAttachments()
        state.supervisionStatus = "Ready · waiting for attached app"
        if state.agent.id == "focus" { beginFocus(state, session: session); return }
        if let target = state.window, FocusWatchPolicy.canCheck(target, windows: WindowFinder.windows(), frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) {
            if state.agent.watchYouTube && FocusWatchPolicy.isYouTube(target.title) { detectedYouTube(state, session: session) }
            else { submit(state, kind: .nudge) }
        }
        session.watchTask = Task { [weak self, weak state, weak session] in
            var lastVision = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
                guard let self, let state, let session, state.watching, let target = state.window else { return }
                let windows = WindowFinder.windows()
                guard FocusWatchPolicy.canCheck(target, windows: windows, frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
                    state.supervisionStatus = "Paused · app in background"; continue
                }
                guard Date() >= session.snoozedUntil else { state.supervisionStatus = "Snoozed for 1 minute"; continue }
                if state.agent.watchYouTube && FocusWatchPolicy.isYouTube(target.title) {
                    self.detectedYouTube(state, session: session)
                    continue
                }
                session.youtubeSince = nil; session.youtubeLevel = 0
                guard ScreenAccess.available else {
                    state.supervisionError = true; state.supervisionStatus = "Screen access needed · open settings"; continue
                }
                if !state.busy && Date().timeIntervalSince(lastVision) >= 15 && Date() >= session.retryAfter {
                    lastVision = Date(); self.submit(state, kind: .nudge)
                }
            }
        }
    }

    private func detectedYouTube(_ state: BubbleState, session: AttachedSession) {
        if let window = state.window { youTubeLadder(state, session: session, now: Date(), window: window) }
    }

    /// Meow, then a louder warning, then (when enabled) close the tab. Leaving YouTube or snoozing resets it.
    private func youTubeLadder(_ state: BubbleState, session: AttachedSession, now: Date, window: WindowContext) {
        let since = session.youtubeSince ?? now
        session.youtubeSince = since
        let elapsed = now.timeIntervalSince(since)
        let task = session.focus?.label ?? "your task"
        state.supervisionStatus = "YouTube detected"
        state.supervisionError = false
        switch session.youtubeLevel {
        case 0:
            session.youtubeLevel = 1; session.lastDistraction = now
            CatVoice.play(.drift, for: state.agent)
            say("Meow. YouTube can wait. Back to \(task)?", state)
            if state.agent.pauseOnDistraction {
                intervention.show(agent: state.agent, target: window, resume: { [weak session] in
                    session?.snoozedUntil = Date().addingTimeInterval(60)
                    session?.youtubeSince = nil; session?.youtubeLevel = 0
                }, stop: { [weak self, weak state] in if let state { self?.toggleWatch(state) } })
            }
        case 1 where elapsed >= 45:
            session.youtubeLevel = 2; session.lastDistraction = now
            CatVoice.play(.warning, for: state.agent)
            say(state.agent.closeYouTube ? "MEOW! Still on YouTube. Closing it in 30 seconds." : "MEOW! Still on YouTube. Back to \(task)?", state)
        case 2 where elapsed >= 75:
            session.youtubeLevel = 3; session.lastDistraction = now
            guard state.agent.closeYouTube else { return }
            BrowserTabs.closeYouTube(pid: window.ownerPID) { [weak self, weak state] outcome in
                guard let self, let state else { return }
                switch outcome {
                case .closed: CatVoice.play(.done, for: state.agent); self.say("Closed YouTube. Back to \(task).", state)
                case .notAllowed: self.say("Allow Pika Dots to control your browser in Privacy & Security → Automation.", state)
                case .unsupported: self.say("I can’t close tabs in this browser. Back to \(task)?", state)
                case .notYouTube, .failed: break
                }
            }
        case 3 where now.timeIntervalSince(session.lastDistraction) >= 120:
            // Closing is off or did not work: keep reminding instead of going quiet.
            session.lastDistraction = now
            CatVoice.play(.drift, for: state.agent)
            say("Still on YouTube. Back to \(task)?", state)
        default: break
        }
    }

    // MARK: Focus sessions

    private func beginFocus(_ state: BubbleState, session: AttachedSession) {
        guard let window = state.window else { return }
        if let chill = sessions["chill"], chill.state.watching { endChill(chill.state, message: "Break ended for Focus") }
        if var focus = session.focus, !focus.isOver() {
            focus.resume(); session.focus = focus
            say(focus.resumeMessage, state)
        } else {
            let label = FocusSession.label(purpose: state.prompt, defaultPurpose: state.agent.defaultPurpose, appName: window.appName)
            let focus = FocusSession(label: label, length: state.lengthMinutes > 0 ? TimeInterval(state.lengthMinutes * 60) : nil)
            session.focus = focus; session.verdicts.reset()
            session.youtubeSince = nil; session.youtubeLevel = 0
            // Hold tips back so the start message is not immediately replaced.
            session.lastTip = focus.startedAt
            state.startedAt = focus.startedAt
            CatVoice.play(.start, for: state.agent)
            say(focus.startMessage, state)
        }
        session.pendingKey = ""
        session.watchTask = Task { [weak self, weak state, weak session] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
                guard let self, let state, let session, state.watching else { return }
                self.focusTick(state, session: session)
            }
        }
    }

    /// Every two seconds: decide on-task from the cached verdict for this page, asking the model
    /// only when a page is new (stable for 3s) or its verdict is older than five minutes.
    private func focusTick(_ state: BubbleState, session: AttachedSession) {
        guard var focus = session.focus, let target = state.window else { return }
        let now = Date()
        if focus.isOver() { finishFocus(session, completed: true); return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Using Pika itself (pill, card, settings) is neither work nor a wander.
        if front == ProcessInfo.processInfo.processIdentifier || now < session.snoozedUntil {
            if now < session.snoozedUntil { state.supervisionStatus = "Snoozed for 1 minute" }
            focus.resume(at: now); session.focus = focus; return
        }
        var onTask = true
        var drift = "Back to \(focus.label)?"
        let windows = WindowFinder.windows()
        // Supervise what the user is actually looking at: the attached window, or whatever is in
        // front in another app. Another app is judged on its content, not counted as "away".
        let subject = FocusWatchPolicy.canCheck(target, windows: windows, frontPID: front) ? target : windows.first { $0.ownerPID == front }
        let away = subject.map { $0.windowID == target.windowID ? "" : "In \($0.appName) · " } ?? ""
        if subject == nil {
            onTask = false
            session.youtubeSince = nil; session.youtubeLevel = 0
            state.supervisionStatus = "Away from \(target.appName)"
        } else if let subject, isDelegated(subject) {
            // Watching another cat (Actions) work for you is part of the task.
            session.youtubeSince = nil; session.youtubeLevel = 0
            state.supervisionStatus = "Actions is working for you · on task"
        } else if let subject {
            let key = TitleVerdicts.key(for: subject)
            if key != session.pendingKey { session.pendingKey = key; session.pendingSince = now }
            let verdict = session.verdicts.verdict(for: key, at: now)
            // YouTube counts as a distraction until its content is shown to serve the purpose:
            // a lecture on the topic passes, anything else (or a check that cannot run) starts the ladder.
            if state.agent.watchYouTube, FocusWatchPolicy.isYouTube(subject.title), verdict?.onTask != true {
                focus.record(onTask: false, at: now); session.focus = focus
                if verdict == nil, ScreenAccess.available, now >= session.retryAfter {
                    state.supervisionStatus = "Checking this video…"
                    if !state.busy { submit(state, kind: .focusCheck, cacheKey: key, subject: subject) }
                } else {
                    youTubeLadder(state, session: session, now: now, window: subject)
                }
                return
            }
            session.youtubeSince = nil; session.youtubeLevel = 0
            if let verdict {
                onTask = verdict.onTask
                if !verdict.onTask && !verdict.message.isEmpty { drift = verdict.message }
                state.supervisionStatus = away + verdict.label + (focus.remaining().map { " · \(FocusSession.minutes($0)) left" } ?? "")
            } else if !ScreenAccess.available {
                state.supervisionError = true; state.supervisionStatus = "Screen access needed · open settings"
            } else if now.timeIntervalSince(session.pendingSince) >= 3, !state.busy, now >= session.retryAfter {
                // Unknown pages get the benefit of the doubt until checked.
                state.supervisionStatus = away + "Looking…"
                submit(state, kind: .focusCheck, cacheKey: key, subject: subject)
            }
        }
        let newDrift = focus.record(onTask: onTask, at: now)
        session.focus = focus
        let repeatDrift = !onTask && focus.awayFor(at: now) >= FocusSession.driftThreshold && now.timeIntervalSince(session.lastDistraction) >= 120
        if (newDrift && now.timeIntervalSince(session.lastDistraction) >= 60) || repeatDrift {
            session.lastDistraction = now
            CatVoice.play(.drift, for: state.agent)
            say(drift, state)
        }
    }

    /// A window where an Actions run is in progress (or waiting for approval) on the user's behalf.
    private func isDelegated(_ window: WindowContext) -> Bool {
        sessions.values.contains { $0.state.agent.id == "outreach" && $0.state.busy && $0.state.window?.windowID == window.windowID }
    }

    private func finishFocus(_ session: AttachedSession, completed: Bool) {
        guard let focus = session.focus else { return }
        session.focus = nil
        let state = session.state
        if completed {
            state.watching = false; session.watchTask?.cancel(); session.task?.cancel()
            state.supervisionStatus = "Session complete"
            intervention.dismiss(owner: state.agent.id)
            saveAttachments()
        }
        guard focus.elapsed >= 60 else { return }
        showReply("Focus recap", focus.recapDetail, in: session)
        CatVoice.play(.done, for: state.agent)
        if !catVisible(session) { nudges.show(focus.recapShort, agent: state.agent) }
    }

    // MARK: Chill breaks

    private func startChill(_ state: BubbleState) {
        guard let window = state.window else { return }
        if let focus = sessions["focus"], focus.state.watching {
            // Pause, not end: the Focus session resumes when the break finishes.
            focus.watchTask?.cancel(); focus.task?.cancel(); focus.state.watching = false
            focus.state.supervisionStatus = "Paused for a break"
            intervention.dismiss(owner: "focus")
        }
        let minutes = max(1, state.lengthMinutes)
        state.startedAt = state.startedAt ?? Date()
        state.watching = true
        state.supervisionStatus = "Break · \(minutes) min"
        monitorOwner = "chill"
        monitor.start(agentID: "chill", targetApp: window.appName, targetPID: window.ownerPID, startedAt: state.startedAt,
                      breakLength: TimeInterval(minutes * 60), onMessage: { [weak self, weak state] message in
            guard let self, let state else { return }
            state.response = message
            if !message.hasPrefix("Break complete") { CatVoice.play(.drift, for: state.agent) }
            self.say(message, state)
        }, onFinish: { [weak self, weak state] in
            guard let self, let state else { return }
            CatVoice.play(.done, for: state.agent)
            self.endChill(state, message: "Break complete")
            if let focus = self.sessions["focus"], focus.focus != nil, !focus.state.watching { self.toggleWatch(focus.state) }
        })
        CatVoice.play(.start, for: state.agent)
        say("\(minutes)-minute break. Step away from the keys.", state)
        saveAttachments()
    }

    private func endChill(_ state: BubbleState, message: String) {
        if monitorOwner == "chill" { monitor.stop(); monitorOwner = nil }
        state.watching = false; state.startedAt = nil
        state.supervisionStatus = message
        saveAttachments()
    }

    // MARK: Pill, replies, requests

    private func submitFromPill(_ state: BubbleState) {
        guard let session = sessions[state.agent.id], let window = state.window else { return }
        if SessionLength.options(for: state.agent.id) != nil {
            UserDefaults.standard.set(state.lengthMinutes, forKey: SessionLength.key(state.agent.id))
        }
        if state.agent.id == "outreach" { runOperator(state, session: session); return }
        guard ["focus", "chill"].contains(state.agent.id) else { submit(state, kind: .ask); return }
        if state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.prompt = state.agent.defaultPurpose }
        state.purpose = state.prompt; state.expanded = false
        UserDefaults.standard.set(state.prompt, forKey: purposeKey(state.agent, window))
        if state.agent.id == "chill" {
            endChill(state, message: "Restarting break"); startChill(state)
        } else {
            // A new purpose or length starts a fresh session.
            session.watchTask?.cancel(); session.task?.cancel(); session.focus = nil; state.watching = false
            toggleWatch(state)
        }
    }

    /// Hover-mic or pill-mic: open the pill, dictate into it, and send when the user pauses.
    private func talk(_ state: BubbleState) {
        guard let session = sessions[state.agent.id] else { return }
        if !state.expanded {
            state.expanded = true; updateAttachments()
            session.panel.makeKeyAndOrderFront(nil)
        }
        VoiceInput.shared.start(partial: { [weak state] in state?.prompt = $0 },
            final: { [weak self, weak state] _ in if let state { self?.submitFromPill(state) } },
            listening: { [weak state] in state?.listening = $0 },
            failure: { [weak self, weak state] in if let state { self?.say($0, state) } })
    }

    private func checkNow(_ state: BubbleState) {
        if state.agent.id == "focus", let target = state.window {
            submit(state, kind: .focusCheck, cacheKey: TitleVerdicts.key(for: target))
        } else { submit(state, kind: .nudge) }
    }

    private func showReply(_ title: String, _ text: String, in session: AttachedSession) {
        session.speechTask?.cancel(); session.state.speech = nil
        session.state.replyTitle = title
        session.state.reply = text
        session.replyHeight = ReplyCard.height(text, actions: session.state.approval != nil)
        if let window = session.state.window { position(session, window: window) }
        updateAttachments()
    }

    // MARK: Actions

    /// Runs the Chrome operator. Every outward step (send, connect, post…) waits for Approve on the card.
    private func runOperator(_ state: BubbleState, session: AttachedSession) {
        let goal = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, let window = state.window else { return }
        guard NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier == "com.google.Chrome" else {
            say("Attach Actions to a Google Chrome window.", state); return
        }
        resolveApproval(false, for: state.agent.id)
        session.task?.cancel()
        UserDefaults.standard.set(goal, forKey: purposeKey(state.agent, window))
        state.busy = true; state.expanded = false; state.purpose = goal
        showReply("Actions · working", "Starting…", in: session)
        let token = UUID()
        state.requestToken = token
        session.task = Task { [weak self, weak session, state] in
            defer { if state.requestToken == token { state.busy = false; state.requestToken = nil } }
            let planner = OperatorPlanner(goal: goal, chrome: ChromeOperator(window: window.bounds), allowedSites: SkillSites.parse(state.agent.skillText))
            planner.autoApprove = UserDefaults.standard.bool(forKey: "actions.yolo"); planner.memory = OperatorMemory()
            let result: String
            do {
                result = try await planner.run(confirm: { [weak self, weak session] _, description in
                    guard let self, let session else { return false }
                    return await self.askApproval(description, session: session)
                }, progress: { [weak self, weak session] line in
                    if let self, let session { self.showReply("Actions · working", line, in: session) }
                })
            } catch is CancellationError { result = "Stopped. Nothing else was done."
            } catch { result = error.localizedDescription }
            guard let self, let session, state.requestToken == token else { return }
            CatVoice.play(.done, for: state.agent)
            self.showReply("Actions", result, in: session)
        }
    }

    private func askApproval(_ description: String, session: AttachedSession) async -> Bool {
        CatVoice.play(.warning, for: session.state.agent)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != session.state.window?.ownerPID {
            nudges.show("Needs your OK: " + description, agent: session.state.agent, pinned: true)
        }
        return await withCheckedContinuation { continuation in
            session.approval?.resume(returning: false)
            session.approval = continuation
            session.state.approval = description
            showReply("Actions · needs your OK", description, in: session)
        }
    }

    private func resolveApproval(_ approved: Bool, for id: String) {
        guard let session = sessions[id], let approval = session.approval else { return }
        session.approval = nil; session.state.approval = nil
        nudges.clearPinned(session.state.agent)
        approval.resume(returning: approved)
    }

    private func dismissCompanion(_ id: String) {
        let recap = sessions[id]?.focus.flatMap { $0.elapsed >= 60 ? $0.recapShort : nil }
        let agent = sessions[id]?.state.agent
        close(id)
        if let recap, let agent { nudges.show(recap, agent: agent) }
    }

    /// `subject` lets Focus check the window the user is on in another app; it defaults to the attached window.
    private func submit(_ state: BubbleState, kind: RequestKind = .ask, cacheKey: String? = nil, subject: WindowContext? = nil) {
        let prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let attached = state.window, let session = sessions[state.agent.id] else { return }
        let window = subject ?? attached
        if state.busy {
            // An explicit question outranks a background check that happens to be in flight.
            guard kind == .ask else { return }
            session.task?.cancel()
        }
        let token = UUID()
        state.requestToken = token
        if kind != .focusCheck { state.supervisionStatus = "Checking window…" }
        state.busy = true; state.expanded = false; state.permissionNeeded = false; state.purpose = prompt
        if kind == .ask { state.response = ""; state.reply = nil }
        UserDefaults.standard.set(prompt, forKey: purposeKey(state.agent, attached))
        session.task = Task { [weak self, weak session, state] in
            guard let self else { return }
            // A cancelled request must not clear the busy state of the one that replaced it.
            defer { if state.requestToken == token { state.busy = false; state.requestToken = nil } }
            do {
                let image = try await WindowCapture.capture(window)
                try Task.checkCancellation()
                let generic = prompt == state.agent.defaultPurpose
                let text = kind == .nudge ? prompt + "\nPeriodic check. Keyboard activity: " + state.activity + ". If no useful nudge is warranted, reply exactly NO_NUDGE. Otherwise give one short helpful observation toward the purpose."
                    : kind == .focusCheck && generic ? FocusVerdict.genericPurpose : prompt
                // Decisions gives calibrated on-task checks; any failure (it is in beta) falls back to Responses once.
                var decided: FocusVerdict?
                if kind == .focusCheck, state.agent.api == .decisions {
                    do { decided = try await DecisionsClient.focusCheck(purpose: text, window: window, imageJPEG: image) }
                    catch is CancellationError { throw CancellationError() } catch { decided = nil }
                }
                let answer = decided == nil ? try await responder.respond(to: TaskRequest(sessionID: UUID(), agent: state.agent, prompt: text, window: window, imageData: image, kind: kind)) : ""
                try Task.checkCancellation()
                guard let session else { return }
                state.lastChecked = Date().formatted(date: .omitted, time: .shortened)
                state.supervisionError = false
                switch kind {
                case .ask:
                    state.response = answer
                    showReply(state.agent.name, answer, in: session)
                    // The card is on the window; only notify if the user has moved elsewhere.
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.ownerPID { say(answer, state) }
                    state.supervisionStatus = state.watching ? "Active · checked " + state.lastChecked : "Answered at " + state.lastChecked
                case .nudge:
                    if !NudgeFilter.isQuiet(answer) { state.response = answer; say(answer, state) }
                    state.supervisionStatus = "Active · checked " + state.lastChecked
                case .focusCheck:
                    guard let cacheKey, let parsed = decided ?? FocusVerdict.parse(answer) else { session.retryAfter = Date().addingTimeInterval(30); return }
                    let verdict = parsed.adjusted(genericPurpose: generic)
                    session.verdicts.store(verdict, for: cacheKey)
                    if verdict.onTask, !verdict.message.isEmpty, !NudgeFilter.isQuiet(verdict.message), Date().timeIntervalSince(session.lastTip) >= 300 {
                        session.lastTip = Date()
                        say(verdict.message, state)
                    }
                }
            } catch is CancellationError { } catch {
                state.permissionNeeded = !ScreenAccess.available
                state.response = state.permissionNeeded ? "" : error.localizedDescription
                state.expanded = false
                state.supervisionError = true
                state.supervisionStatus = state.permissionNeeded ? "Screen access needed" : "Retrying after an error"
                session?.retryAfter = Date().addingTimeInterval(30)
                if let session, Date().timeIntervalSince(session.lastErrorNotice) >= 60 {
                    session.lastErrorNotice = Date()
                    say(state.permissionNeeded ? "Enable screen access in Pika settings." : error.localizedDescription, state)
                }

            }
            if let session { position(session, window: state.window ?? window) }
        }
    }
    private func close(_ id: String) {
        resolveApproval(false, for: id)
        sessions[id]?.speechTask?.cancel()
        intervention.dismiss(owner: id)
        if monitorOwner == id { monitor.stop(); monitorOwner = nil; nudges.dismiss() }
        sessions[id]?.task?.cancel(); sessions[id]?.watchTask?.cancel()
        sessions[id]?.panel.close(); sessions[id]?.dotPanel.close(); sessions[id]?.replyPanel.close(); sessions[id] = nil
        saveAttachments()
    }
    func stopSession() {
        intervention.dismiss()
        monitor.stop(); monitorOwner = nil; nudges.dismiss()
        for id in sessions.keys { resolveApproval(false, for: id) }
        for session in sessions.values {
            session.task?.cancel(); session.watchTask?.cancel(); session.state.watching = false
            session.state.supervisionStatus = "Stopped"; session.state.response = "Session stopped."
            finishFocus(session, completed: false)
        }
        saveAttachments()
    }
}
