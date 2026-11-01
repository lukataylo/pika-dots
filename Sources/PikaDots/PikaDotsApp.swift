import SwiftUI

@main
struct PikaDotsApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra {
            RosterView(app: controller)
        } label: {
            Image(nsImage: MenuBarArtwork.image).accessibilityLabel("Pika Dots")
        }.menuBarExtraStyle(.window)
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AttachedSession {
    let state: BubbleState
    let panel: CompanionPanel
    let dotPanel: CompanionPanel
    var watchTask: Task<Void, Never>?
    var task: Task<Void, Never>?
    init(state: BubbleState, panel: CompanionPanel, dotPanel: CompanionPanel) { self.state = state; self.panel = panel; self.dotPanel = dotPanel }
}

@MainActor
final class AppController: ObservableObject {
    let agents = SkillLoader.load()
    @Published var notice = ""
    private let responder: any AgentResponding = OpenAIResponder()
    private let monitor = SessionMonitor()
    @Published private var sessions: [String: AttachedSession] = [:]
    var attachedCount: Int { sessions.count }
    func attachedApp(_ id: String) -> String? { sessions[id]?.state.window?.appName }
    private var followTask: Task<Void, Never>?

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                self?.updateAttachments()
            }
        }
    }

    func attachToFrontmost(_ agent: AgentDefinition) {
        guard let window = WindowFinder.windows().first else { notice = "Open a window, then drag a dot onto it."; return }
        attach(agent, to: window)
    }

    func attach(_ agent: AgentDefinition, at point: NSPoint) {
        guard let window = WindowFinder.window(at: point) else { notice = "Drop onto an application window, such as Chrome or Notes."; return }
        attach(agent, to: window)
    }

    private func attach(_ agent: AgentDefinition, to window: WindowContext) {
        notice = ""
        close(agent.id)
        // One companion per target keeps the purpose field readable.
        let replaced = sessions.filter { $0.value.state.window?.windowID == window.windowID }.map(\.key)
        for id in replaced { close(id) }
        let state = BubbleState(agent: agent, window: window)
        state.prompt = UserDefaults.standard.string(forKey: purposeKey(agent, window)) ?? ""
        let panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 78), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let dotPanel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 48, height: 48), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        dotPanel.backgroundColor = .clear; dotPanel.isOpaque = false; dotPanel.hasShadow = false
        dotPanel.level = .floating; dotPanel.isReleasedWhenClosed = false
        dotPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        dotPanel.hidesOnDeactivate = false
        dotPanel.contentView = NSHostingView(rootView: PerchedDot(state: state,
            onDrop: { [weak self] in self?.attach(agent, at: $0) },
            toggle: { [weak self, weak state] in
                guard let self, let state else { return }
                state.expanded.toggle()
                self.updateAttachments()
                if state.expanded { self.sessions[agent.id]?.panel.makeKeyAndOrderFront(nil) }
            }))
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: TaskBubble(state: state,
            submit: { [weak self, weak state] in if let state { self?.submit(state) } },
            close: { [weak self] in self?.close(agent.id) },
            toggleWatch: { [weak self, weak state] in if let state { self?.toggleWatch(state) } }))
        sessions[agent.id] = AttachedSession(state: state, panel: panel, dotPanel: dotPanel)
        position(sessions[agent.id]!, window: window)
        dotPanel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        sampleAppearance(state)
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
        let height: CGFloat = session.state.response.isEmpty ? 72 : 210
        let layout = AttachmentLayout(window: rect, screen: visible, expandedHeight: height)
        if session.panel.frame != layout.tab { session.panel.setFrame(layout.tab, display: true) }
        if session.dotPanel.frame != layout.dot { session.dotPanel.setFrame(layout.dot, display: true) }

    }

    private func updateAttachments() {
        let windows = WindowFinder.windows()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for session in sessions.values {
            guard let old = session.state.window else { continue }
            guard let current = windows.first(where: { $0.windowID == old.windowID && $0.ownerPID == old.ownerPID }) else {
                session.panel.orderOut(nil); session.dotPanel.orderOut(nil); continue
            }
            session.state.window = current
            session.state.activity = TypingActivity.summary(for: current.ownerPID)
            position(session, window: current)
            // Only show on the frontmost window of that app, not another Chrome/Notes window.
            let frontWindow = windows.first { $0.ownerPID == current.ownerPID }
            let visible = (frontPID == current.ownerPID || frontPID == ownPID) && frontWindow?.windowID == current.windowID
            if visible {
                session.dotPanel.orderFrontRegardless()
                if session.state.expanded { session.panel.orderFrontRegardless() } else { session.panel.orderOut(nil) }
            } else { session.panel.orderOut(nil); session.dotPanel.orderOut(nil) }
        }
    }

    private func toggleWatch(_ state: BubbleState) {
        guard let session = sessions[state.agent.id] else { return }
        if state.watching {
            state.watching = false; session.watchTask?.cancel(); session.task?.cancel()
            if ["focus", "chill"].contains(state.agent.id) { monitor.stop() }
            return
        }
        guard !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.response = "Set a purpose first, then press Watch."; return
        }
        state.watching = true
        state.activity = "Starting · checks every 45s"
        submit(state)
        session.watchTask = Task { [weak self, weak state] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(45)); try Task.checkCancellation() } catch { return }
                guard let self, let state, state.watching, let target = state.window else { return }
                let windows = WindowFinder.windows()
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.ownerPID,
                      windows.first(where: { $0.ownerPID == target.ownerPID })?.windowID == target.windowID else { continue }
                self.submit(state, periodic: true)
            }
        }
    }

    private func submit(_ state: BubbleState, periodic: Bool = false) {
        let prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !state.busy, let window = state.window, let session = sessions[state.agent.id] else { return }
        state.busy = true; state.purpose = prompt; if !periodic { state.response = "" }
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
                if answer.trimmingCharacters(in: .whitespacesAndNewlines) != "NO_NUDGE" { state.response = answer; if periodic { state.expanded = true } }
                state.lastChecked = Date().formatted(date: .omitted, time: .shortened)
                if !periodic && ["focus", "chill"].contains(state.agent.id) {
                    monitor.start(agentID: state.agent.id, targetApp: window.appName) { [weak state] in state?.response = $0 }
                }
            } catch is CancellationError { } catch {
                state.response = error.localizedDescription
                state.watching = false; session?.watchTask?.cancel()
            }
            if let session { position(session, window: state.window ?? window) }
        }
    }
    private func close(_ id: String) {
        if id == "focus" || id == "chill" { monitor.stop() }
        sessions[id]?.task?.cancel(); sessions[id]?.watchTask?.cancel()
        sessions[id]?.panel.close(); sessions[id]?.dotPanel.close(); sessions[id] = nil
    }
    func stopSession() {
        monitor.stop()
        for session in sessions.values { session.task?.cancel(); session.watchTask?.cancel(); session.state.watching = false; session.state.response = "Session stopped." }
    }
}
