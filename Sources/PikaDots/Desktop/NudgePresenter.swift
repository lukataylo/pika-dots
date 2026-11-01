import SwiftUI

@MainActor
final class NudgePresenter {
    private var panel: CompanionPanel?
    private var dismissTask: Task<Void, Never>?
    func dismiss() { dismissTask?.cancel(); panel?.close(); panel = nil }
    func show(_ message: String, agent: AgentDefinition) {
        dismiss()
        let panel = CompanionPanel(contentRect: CGRect(x: 0, y: 0, width: 310, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Color(nsColor: agent.color)).frame(width: 12, height: 12).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) { Text(agent.name).font(.headline); Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
                Button { [weak self] in self?.dismiss() } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
            }.padding(16).frame(width: 310, height: 110).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)))
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 330, y: screen.visibleFrame.maxY - 130)) }
        self.panel = panel; panel.orderFrontRegardless()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)); try Task.checkCancellation() } catch { return }
            self?.panel?.orderOut(nil)
        }
    }
}
