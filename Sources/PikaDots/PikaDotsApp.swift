import SwiftUI

@main
struct PikaDotsApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra("Pika Dots", systemImage: "circle.hexagongrid.fill") {
            RosterView(app: controller)
        }.menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppController: ObservableObject {
    let agents = SkillLoader.load()
    private let responder: any AgentResponding = DemoResponder()
    private let monitor = SessionMonitor()
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private var activeState: BubbleState?

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    func attachToFrontmost(_ agent: AgentDefinition) {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = windows.first { ($0[kCGWindowOwnerPID as String] as? Int32) != ownPID && ($0[kCGWindowLayer as String] as? Int) == 0 }
        if let raw = info?[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: raw) {
            attach(agent, at: NSPoint(x: rect.midX, y: CGDisplayBounds(CGMainDisplayID()).height - rect.midY))
        } else { attach(agent, at: NSEvent.mouseLocation) }
    }

    func attach(_ agent: AgentDefinition, at point: NSPoint) {
        task?.cancel(); monitor.stop(); panel?.close()
        let state = BubbleState(agent: agent, window: WindowFinder.window(at: point))
        activeState = state
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 386, height: 330), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: TaskBubble(state: state, submit: { [weak self] in self?.submit(state) }, close: { [weak self] in self?.closeBubble() }))
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, min(point.x - 193, visible.maxX - 386)), y: max(visible.minY, min(point.y - 330, visible.maxY - 330))))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func submit(_ state: BubbleState) {
        let prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !state.busy else { return }
        task?.cancel(); state.busy = true
        let request = TaskRequest(sessionID: UUID(), agent: state.agent, prompt: prompt, window: state.window)
        task = Task { [weak self, state] in
            guard let self else { return }
            defer { state.busy = false }
            do {
                state.response = try await responder.respond(to: request)
                try Task.checkCancellation()
                if ["focus", "chill"].contains(state.agent.id) {
                    monitor.start(agentID: state.agent.id, targetApp: state.window?.appName) { [weak state] message in state?.response = message }
                }
            } catch is CancellationError { } catch { state.response = error.localizedDescription }
        }
    }
    func closeBubble() { task?.cancel(); monitor.stop(); panel?.close(); panel = nil; activeState = nil; monitor.stop() }
    func stopSession() { task?.cancel(); monitor.stop(); activeState?.response = "Session stopped." }
}
