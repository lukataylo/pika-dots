import SwiftUI

@MainActor
final class InterventionPresenter {
    private var panel: CompanionPanel?
    private(set) var ownerID: String?
    func dismiss(owner: String? = nil) {
        guard owner == nil || owner == ownerID else { return }
        panel?.close(); panel = nil; ownerID = nil
    }
    func show(agent: AgentDefinition, target: WindowContext, resume: @escaping () -> Void, stop: @escaping () -> Void) {
        guard panel == nil else { return }
        ownerID = agent.id
        let screen = NSScreen.screens.first { $0.frame.intersects(WindowFinder.appRect(target.bounds)) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let panel = CompanionPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.backgroundColor = .windowBackgroundColor
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let finish: () -> Void = { [weak self] in
            self?.dismiss(); resume()
            NSRunningApplication(processIdentifier: target.ownerPID)?.activate(options: [])
        }
        panel.contentView = NSHostingView(rootView:
            VStack(spacing: 18) {
                Image(nsImage: CharacterArtwork.image(for: agent.id) ?? MenuBarArtwork.image).resizable().scaledToFit().frame(width: 90, height: 90)
                Text("A little pause for your focus.").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("YouTube can wait.").foregroundStyle(.secondary)
                HStack {
                    Button("Continue for 1 minute", action: finish).keyboardShortcut(.cancelAction)
                    Button("Stop supervision") { [weak self] in self?.dismiss(); stop() }
                }
                Text("Escape continues. You can always stop or quit Pika Dots.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
                .onExitCommand(perform: finish))
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
