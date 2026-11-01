import SwiftUI

struct DraggableDot: NSViewRepresentable {
    let agent: AgentDefinition
    let onDrop: (NSPoint) -> Void
    var onClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DotDragView { let v = DotDragView(color: agent.color); v.onDrop = onDrop; v.onClick = onClick; return v }
    func updateNSView(_ view: DotDragView, context: Context) { view.onDrop = onDrop; view.onClick = onClick }
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
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .padding(5)
        .contextMenu {
            Button("Create or edit companions…", systemImage: "sparkles") { app.manageCompanions() }
            Divider()
            Button("Stop all sessions", systemImage: "pause.circle") { app.stopSession() }
            Divider()
            Button("Quit Pika Dots", systemImage: "power") { NSApp.terminate(nil) }
        }
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
                .frame(width: 20, height: 20)
                .offset(y: hovering && !reduceMotion ? -2 : 0)
            Text(agent.name).font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 2)
        }.frame(width: 34)
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
    @Published var expanded = false
    @Published var windowColor: NSColor = .windowBackgroundColor
    @Published var windowIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    @Published var watching = false
    @Published var activity = ""
    @Published var lastChecked = ""
    let agent: AgentDefinition
    @Published var window: WindowContext?
    init(agent: AgentDefinition, window: WindowContext?) { self.agent = agent; self.window = window }
}

struct PerchedDot: View {
    @ObservedObject var state: BubbleState
    let onDrop: (NSPoint) -> Void
    let toggle: () -> Void
    let dismiss: () -> Void
    var body: some View {
        DraggableDot(agent: state.agent, onDrop: onDrop, onClick: toggle)
            .frame(width: 20, height: 20)
            .padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 2)
            .background(WindowTabShape().fill(Color(nsColor: state.windowColor)))
            .overlay(alignment: .topTrailing) {
                if state.watching { Circle().fill(.green).frame(width: 4, height: 4).padding(5) }
            }
            .contextMenu {
                Button(state.expanded ? "Hide purpose" : "Set purpose", action: toggle)
                Button("Dismiss \(state.agent.name)", systemImage: "xmark.circle", action: dismiss)
            }
            .help("\(state.agent.name) · click to expand, right-click to dismiss")
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
    let toggleWatch: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                TextField("Purpose…", text: $state.prompt)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit { if !state.busy { submit() } }
                if state.busy { ProgressView().controlSize(.mini) }
                else { Button(action: submit) { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(.plain).help("Send this window to OpenAI") }
                Button(action: toggleWatch) { Image(systemName: state.watching ? "pause.circle.fill" : "eye") }
                    .buttonStyle(.plain).foregroundStyle(state.watching ? Color.green : Color.secondary)
                    .help(state.watching ? "Stop watching" : "Watch this window every 45 seconds")
                Button { state.expanded = false } label: { Image(systemName: "chevron.down").font(.system(size: 8)) }.buttonStyle(.plain).help("Collapse")
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain).help("Dismiss companion")
            }
            .padding(.horizontal, 18).frame(height: 40)
            .background(WindowTabShape().fill(Color(nsColor: state.windowColor)))
            if !state.response.isEmpty {
                ScrollView { Text(state.response).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .frame(height: 132).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 6).padding(.bottom, 6)
            }
        }.frame(width: 280)
            .environment(\.colorScheme, state.windowIsDark ? .dark : .light)
            .onExitCommand { state.expanded = false }
    }
}
