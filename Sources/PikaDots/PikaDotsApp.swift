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
    var task: Task<Void, Never>?
    init(state: BubbleState, panel: CompanionPanel) { self.state = state; self.panel = panel }
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
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
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
        panel.contentView = NSHostingView(rootView: TaskBubble(state: state,
            submit: { [weak self, weak state] in if let state { self?.submit(state) } },
            close: { [weak self] in self?.close(agent.id) },
            onDrop: { [weak self] in self?.attach(agent, at: $0) }))
        sessions[agent.id] = AttachedSession(state: state, panel: panel)
        position(sessions[agent.id]!, window: window)
        panel.makeKeyAndOrderFront(nil)
    }

    private func purposeKey(_ agent: AgentDefinition, _ window: WindowContext) -> String {
        let bundle = NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier ?? window.appName
        return "purpose.\(agent.id).\(bundle)"
    }

    private func position(_ session: AttachedSession, window: WindowContext) {
        let rect = WindowFinder.appRect(window.bounds)
        let visible = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main)?.visibleFrame ?? rect
        let height: CGFloat = session.state.response.isEmpty ? (session.state.purpose.isEmpty ? 78 : 108) : (session.state.purpose.isEmpty ? 240 : 270)
        // Sit above the title bar; tuck inside its top edge for maximized windows.
        let y = min(rect.maxY, visible.maxY - height)
        let x = max(visible.minX, min(rect.midX - 220, visible.maxX - 440))
        session.panel.setFrame(NSRect(x: x, y: max(visible.minY, y), width: 440, height: height), display: true)
    }

    private func updateAttachments() {
        let windows = WindowFinder.windows()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for session in sessions.values {
            guard let old = session.state.window else { continue }
            guard let current = windows.first(where: { $0.windowID == old.windowID && $0.ownerPID == old.ownerPID }) else {
                session.panel.orderOut(nil); continue
            }
            session.state.window = current
            position(session, window: current)
            // Hide behind other applications, and when the target is minimized or off this Space.
            if frontPID == current.ownerPID || frontPID == ownPID { session.panel.orderFrontRegardless() }
            else { session.panel.orderOut(nil) }
        }
    }

    private func submit(_ state: BubbleState) {
        let prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !state.busy, let window = state.window, let session = sessions[state.agent.id] else { return }
        state.busy = true; state.purpose = prompt; state.response = ""
        UserDefaults.standard.set(prompt, forKey: purposeKey(state.agent, window))
        session.task = Task { [weak self, weak session, state] in
            guard let self else { return }
            defer { state.busy = false }
            do {
                let image = try await WindowCapture.capture(window)
                try Task.checkCancellation()
                let request = TaskRequest(sessionID: UUID(), agent: state.agent, prompt: prompt, window: window, imageData: image)
                let answer = try await responder.respond(to: request)
                try Task.checkCancellation()
                guard session != nil else { return }
                state.response = answer
                if ["focus", "chill"].contains(state.agent.id) {
                    monitor.start(agentID: state.agent.id, targetApp: window.appName) { [weak state] in state?.response = $0 }
                }
            } catch is CancellationError { } catch { state.response = error.localizedDescription }
            if let session { position(session, window: state.window ?? window) }
        }
    }
    private func close(_ id: String) {
        if id == "focus" || id == "chill" { monitor.stop() }
        sessions[id]?.task?.cancel(); sessions[id]?.panel.close(); sessions[id] = nil
    }
    func stopSession() {
        monitor.stop()
        for session in sessions.values { session.task?.cancel(); session.state.response = "Session stopped." }
    }
}
