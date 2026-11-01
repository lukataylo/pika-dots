import SwiftUI

struct DraggableDot: NSViewRepresentable {
    let agent: AgentDefinition
    let onDrop: (NSPoint) -> Void
    var onClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DotDragView { let v = DotDragView(color: agent.color); v.onDrop = onDrop; v.onClick = onClick; v.artwork = CharacterArtwork.image(for: agent.id); v.setAccessibilityLabel(agent.name); return v }
    func updateNSView(_ view: DotDragView, context: Context) { view.onDrop = onDrop; view.onClick = onClick; view.artwork = CharacterArtwork.image(for: agent.id) }
}

struct RosterView: View {
    @ObservedObject var app: AppController
    var body: some View {
        HStack(spacing: 14) {
            ForEach(app.agents) { agent in
                ShelfCompanion(agent: agent, attached: app.attachedApp(agent.id) != nil,
                    onDrop: { app.attach(agent, at: $0) },
                    onClick: { app.attachToFrontmost(agent) })
            }
            Button { app.manageCompanions() } label: { Image(systemName: "plus").font(.system(size: 12)).frame(width: 20, height: 28) }.buttonStyle(.plain).help("Create or edit companions")
            Button { app.showSettings() } label: { Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 20, height: 28) }.buttonStyle(.plain).help("Settings & permissions")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.primary.opacity(0.07)))
        .padding(6)
        .contextMenu {
            Button("Create or edit companions…", systemImage: "sparkles") { app.manageCompanions() }
            Divider()
            Button("Stop all sessions", systemImage: "pause.circle") { app.stopSession() }
            Divider()
            Button("Quit Pika Dots", systemImage: "power") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Companion shelf")
        .help(app.notice.isEmpty ? "Drag a companion onto a window. Right-click for options." : app.notice)
    }
}

private struct ShelfCompanion: View {
    let agent: AgentDefinition
    let attached: Bool
    let onDrop: (NSPoint) -> Void
    let onClick: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 3) {
            DraggableDot(agent: agent, onDrop: onDrop, onClick: onClick)
                .frame(width: 40, height: 40)
                .offset(y: hovering && !reduceMotion ? -2 : 0)
            Button(agent.name, action: onClick).buttonStyle(.plain).font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 2)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClick)
        }.frame(width: 48)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: hovering)
            .help("\(agent.name) · \(agent.summary)")
            .accessibilityLabel(agent.name)
    }
}

@MainActor
final class BubbleState: ObservableObject {
    @Published var prompt = ""
    @Published var purpose = ""
    @Published var response = ""
    @Published var busy = false
    @Published var permissionNeeded = false
    @Published var expanded = false
    @Published var windowColor: NSColor = .windowBackgroundColor
    @Published var windowIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    @Published var watching = false
    @Published var supervisionStatus = "Not supervising"
    @Published var supervisionError = false
    @Published var activity = ""
    @Published var lastChecked = ""
    var startedAt: Date?
    let agent: AgentDefinition
    @Published var window: WindowContext?
    init(agent: AgentDefinition, window: WindowContext?) { self.agent = agent; self.window = window }
}

struct PerchedDot: View {
    @ObservedObject var state: BubbleState
    let onDrop: (NSPoint) -> Void
    let toggle: () -> Void
    let dismiss: () -> Void
    let settings: () -> Void
    let toggleWatch: () -> Void
    var checkNow: (() -> Void)? = nil
    var body: some View {
        DraggableDot(agent: state.agent, onDrop: onDrop, onClick: toggle)
            .frame(width: 40, height: 40)
            .padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 2)
            .overlay(alignment: .topTrailing) {
                if state.watching { Circle().fill(state.supervisionError ? .orange : .green).frame(width: 4, height: 4).padding(5) }
            }
            .overlay(alignment: .bottomTrailing) {
                // The purpose pill collapses on send, so the cat carries the "thinking" state.
                if state.busy { ProgressView().controlSize(.mini).padding(2) }
            }
            .contextMenu {
                Text(state.supervisionStatus)
                if let checkNow { Button("Check now", action: checkNow) }
                Divider()
                Button(state.expanded ? "Hide purpose" : "Set purpose", action: toggle)
                Button(state.watching ? "Pause supervision" : "Start supervision", action: toggleWatch)
                Button("Settings…", action: settings)
                Divider()
                Button("Dismiss \(state.agent.name)", systemImage: "xmark.circle", action: dismiss)
            }
            .help("\(state.agent.name) · \(state.supervisionStatus) · right-click for controls")
    }
}

struct WindowTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cap = min(20.0, rect.width / 4)
        let shoulder = min(34.0, rect.width / 3)
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addCurve(to: CGPoint(x: cap, y: 8), control1: CGPoint(x: 12, y: rect.maxY), control2: CGPoint(x: 8, y: 12))
        p.addQuadCurve(to: CGPoint(x: shoulder, y: 0), control: CGPoint(x: cap, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - shoulder, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - cap, y: 12), control: CGPoint(x: rect.maxX - cap, y: 0))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control1: CGPoint(x: rect.maxX - 8, y: 12), control2: CGPoint(x: rect.maxX - 12, y: rect.maxY))
        p.closeSubpath(); return p
    }
}

struct TaskBubble: View {
    @ObservedObject var state: BubbleState
    let submit: () -> Void
    let close: () -> Void
    let settings: () -> Void
    let toggleWatch: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            TextField("Give me a purpose…", text: $state.prompt)
                .textFieldStyle(.plain).font(.system(size: 11))
                .onSubmit { if !state.busy { submit() } }
                // Borderless non-activating panels can drop the field editor's Return action.
                .onKeyPress(.return) { if !state.busy { submit() }; return .handled }
            if state.busy { ProgressView().controlSize(.mini) }
            else {
                Button(action: submit) { Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).help("Send")
            }
        }
        .padding(.horizontal, 12).frame(width: 240, height: 32)
        .background(Color(nsColor: state.windowColor), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.07)))
        .environment(\.colorScheme, state.windowIsDark ? .dark : .light)
        .onExitCommand { state.expanded = false }
    }
}
