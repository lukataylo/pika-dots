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
    var watchTask: Task<Void, Never>?
    var task: Task<Void, Never>?
    var missingFrames = 0
    var lastDistraction = Date.distantPast
    var snoozedUntil = Date.distantPast
    var retryAfter = Date.distantPast
    var lastErrorNotice = Date.distantPast
    init(state: BubbleState, panel: CompanionPanel, dotPanel: CompanionPanel) { self.state = state; self.panel = panel; self.dotPanel = dotPanel }
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
            onDrop: { [weak self] in self?.attach(agent, at: $0) },
            toggle: { [weak self, weak state] in
                guard let self, let state else { return }
                state.expanded.toggle()
                self.updateAttachments()
                if state.expanded { self.sessions[agent.id]?.panel.makeKeyAndOrderFront(nil) }
            }, dismiss: { [weak self] in self?.close(agent.id) },
            settings: { [weak self] in self?.showSettings() },
            toggleWatch: { [weak self, weak state] in if let state { self?.toggleWatch(state) } },
            checkNow: { [weak self, weak state] in if let state { self?.submit(state, periodic: true) } }))
        panel.onResignKey = { [weak state] in state?.expanded = false }
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: TaskBubble(state: state,
            submit: { [weak self, weak state] in if let state { self?.submit(state) } },
            close: { [weak self] in self?.close(agent.id) },
            settings: { [weak self] in self?.showSettings() },
            toggleWatch: { [weak self, weak state] in if let state { self?.toggleWatch(state) } }))
        state.expanded = agent.mode == .promptable
        sessions[agent.id] = AttachedSession(state: state, panel: panel, dotPanel: dotPanel)
        sessions[agent.id]?.snoozedUntil = restored?.snoozedUntil ?? .distantPast
        position(sessions[agent.id]!, window: window)
        dotPanel.order(.above, relativeTo: Int(window.windowID))
        if state.expanded { panel.makeKeyAndOrderFront(nil) }
        sampleAppearance(state)
        if agent.mode == .supervisor && (restored?.running ?? true) {
            if ["focus", "chill"].contains(agent.id) {
                let opposite = agent.id == "focus" ? "chill" : "focus"
                if let previous = sessions[opposite] {
                    previous.watchTask?.cancel(); previous.task?.cancel(); previous.state.watching = false
                    previous.state.response = "Paused while the other companion takes over."
                }
            }
            if state.prompt.isEmpty { state.prompt = agent.defaultPurpose }
            state.purpose = state.prompt
            state.expanded = false
            panel.orderOut(nil)
            if ["focus", "chill"].contains(agent.id) {
                state.startedAt = state.startedAt ?? Date()
                monitorOwner = agent.id
                monitor.start(agentID: agent.id, targetApp: window.appName, targetPID: window.ownerPID, startedAt: state.startedAt) { [weak self, weak state] message in
                    state?.response = message
                    self?.nudges.show(message, agent: agent)
                }
                if agent.id == "focus" { toggleWatch(state) }
            } else {
                toggleWatch(state)
            }
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

    private func position(_ session: AttachedSession, window: WindowContext) {
        let rect = WindowFinder.appRect(window.bounds)
        let visible = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main)?.visibleFrame ?? rect
        let height: CGFloat = 32
        let layout = AttachmentLayout(window: rect, screen: visible, expandedHeight: height)
        if session.panel.frame != layout.tab { session.panel.setFrame(layout.tab, display: true) }
        if session.dotPanel.frame != layout.dot { session.dotPanel.setFrame(layout.dot, display: true) }

    }

    private func updateAttachments() {
        guard !sessions.isEmpty else { return }
        let windows = WindowFinder.windows()
        for session in sessions.values {
            guard let old = session.state.window else { continue }
            guard let current = windows.first(where: { $0.windowID == old.windowID && $0.ownerPID == old.ownerPID }) else {
                session.missingFrames += 1
                if session.missingFrames > 15 { session.panel.orderOut(nil); session.dotPanel.orderOut(nil) }
                continue
            }
            session.missingFrames = 0
            // Assign only on change: every write republishes both hosting views.
            if current != old { session.state.window = current }
            let activity = TypingActivity.summary(for: current.ownerPID)
            if activity != session.state.activity { session.state.activity = activity }
            position(session, window: current)
            // Normal-level panels follow the target's actual window-server order,
            // rather than vanishing whenever another application gains focus.
            session.dotPanel.order(.above, relativeTo: Int(current.windowID))
            if session.state.expanded {
                session.panel.order(.above, relativeTo: session.dotPanel.windowNumber)
            } else { session.panel.orderOut(nil) }

        }
    }

    private func toggleWatch(_ state: BubbleState) {
        guard let session = sessions[state.agent.id] else { return }
        if state.watching {
            state.watching = false; state.supervisionStatus = "Paused by you"; session.watchTask?.cancel(); session.task?.cancel()
            intervention.dismiss(owner: state.agent.id)
            if monitorOwner == state.agent.id { monitor.stop(); monitorOwner = nil; nudges.dismiss() }
            saveAttachments()
            return
        }
        guard !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            nudges.show("Set a purpose first.", agent: state.agent); return
        }
        state.watching = true
        saveAttachments()
        state.supervisionStatus = "Ready · waiting for attached app"
        if let target = state.window, FocusWatchPolicy.canCheck(target, windows: WindowFinder.windows(), frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) {
            if state.agent.watchYouTube && FocusWatchPolicy.isYouTube(target.title) { detectedYouTube(state, session: session) }
            else { submit(state) }
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
                guard ScreenAccess.available else {
                    state.supervisionError = true; state.supervisionStatus = "Screen access needed · open settings"; continue
                }
                if !state.busy && Date().timeIntervalSince(lastVision) >= 15 && Date() >= session.retryAfter {
                    lastVision = Date(); self.submit(state, periodic: true)
                }
            }
        }
    }

    private func detectedYouTube(_ state: BubbleState, session: AttachedSession) {
        state.supervisionStatus = "YouTube detected"
        state.supervisionError = false
        guard Date() >= session.snoozedUntil, Date().timeIntervalSince(session.lastDistraction) >= 60 else { return }
        session.lastDistraction = Date()
        nudges.show("YouTube can wait. Back to your task?", agent: state.agent)
        if state.agent.pauseOnDistraction, let target = state.window {
            intervention.show(agent: state.agent, target: target, resume: { [weak session] in
                session?.snoozedUntil = Date().addingTimeInterval(60)
            }, stop: { [weak self, weak state] in if let state { self?.toggleWatch(state) } })
        }
    }

    private func submit(_ state: BubbleState, periodic: Bool = false) {
        let prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !state.busy, let window = state.window, let session = sessions[state.agent.id] else { return }
        state.supervisionStatus = "Checking window…"
        state.busy = true; state.expanded = false; state.permissionNeeded = false; state.purpose = prompt; if !periodic { state.response = "" }
        UserDefaults.standard.set(prompt, forKey: purposeKey(state.agent, window))
        session.task = Task { [weak self, weak session, state] in
            guard let self else { return }
            defer { state.busy = false }
            do {
                let image = try await WindowCapture.capture(window)
                try Task.checkCancellation()
                let request = TaskRequest(sessionID: UUID(), agent: state.agent, prompt: periodic ? prompt + "\nPeriodic check. Keyboard activity: " + state.activity + ". If no useful nudge is warranted, reply exactly NO_NUDGE. Otherwise give one short helpful observation toward the purpose." : prompt, window: window, imageData: image)
                let answer = try await responder.respond(to: request)
                try Task.checkCancellation()
                guard session != nil else { return }
                let youtubeNow = state.agent.watchYouTube && FocusWatchPolicy.isYouTube(state.window?.title ?? "")
                if youtubeNow, let session { detectedYouTube(state, session: session) }
                if !youtubeNow && !NudgeFilter.isQuiet(answer) {
                    state.response = answer
                    nudges.show(answer, agent: state.agent)
                }
                state.lastChecked = Date().formatted(date: .omitted, time: .shortened)
                state.supervisionError = false
                if !youtubeNow { state.supervisionStatus = "Active · checked " + state.lastChecked }
                if !periodic && ["focus", "chill"].contains(state.agent.id) {
                    monitorOwner = state.agent.id
                    monitor.start(agentID: state.agent.id, targetApp: window.appName, targetPID: window.ownerPID) { [weak self, weak state] message in
                        state?.response = message
                        if let state { self?.nudges.show(message, agent: state.agent) }
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
                    nudges.show(state.permissionNeeded ? "Enable screen access in Pika settings." : error.localizedDescription, agent: state.agent)
                }

            }
            if let session { position(session, window: state.window ?? window) }
        }
    }
    private func close(_ id: String) {
        intervention.dismiss(owner: id)
        if monitorOwner == id { monitor.stop(); monitorOwner = nil; nudges.dismiss() }
        sessions[id]?.task?.cancel(); sessions[id]?.watchTask?.cancel()
        sessions[id]?.panel.close(); sessions[id]?.dotPanel.close(); sessions[id] = nil
        saveAttachments()
    }
    func stopSession() {
        intervention.dismiss()
        monitor.stop(); monitorOwner = nil; nudges.dismiss()
        for session in sessions.values { session.task?.cancel(); session.watchTask?.cancel(); session.state.watching = false; session.state.supervisionStatus = "Stopped"; session.state.response = "Session stopped." }
        saveAttachments()
    }
}
