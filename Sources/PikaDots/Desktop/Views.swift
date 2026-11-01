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
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .padding(5)
        .contextMenu {
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
        DraggableDot(agent: agent, onDrop: onDrop, onClick: onClick)
            .frame(width: 48, height: 48).padding(4)
            .background(Color(nsColor: agent.color).opacity(hovering ? 0.13 : 0), in: Circle())
            .overlay(alignment: .bottom) {
                if attached { Circle().fill(Color(nsColor: agent.color)).frame(width: 4, height: 4).offset(y: 3) }
            }
            .offset(y: hovering && !reduceMotion ? -3 : 0)
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
    @Published var expanded = true
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
    var body: some View {
        DraggableDot(agent: state.agent, onDrop: onDrop, onClick: toggle)
            .frame(width: 48, height: 48)
            .overlay(alignment: .topTrailing) {
                if state.watching { Circle().fill(.green).frame(width: 7, height: 7).padding(4) }
            }
            .help("Click to set a purpose; drag to move to another window")
    }
}

struct WindowTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 12, y: rect.maxY), control2: CGPoint(x: 8, y: 12))
        p.addQuadCurve(to: CGPoint(x: 34, y: 0), control: CGPoint(x: 22, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - 34, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 20, y: 12), control: CGPoint(x: rect.maxX - 22, y: 0))
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
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Purpose in \(state.window?.appName ?? "this window")…", text: $state.prompt)
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                        .onSubmit { if !state.busy { submit() } }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.065), in: Capsule())
                    if state.busy { ProgressView().controlSize(.mini) }
                    else { Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 19)) }.buttonStyle(.plain).help("Send this window and purpose to OpenAI") }
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Detach companion")
                }
                HStack(spacing: 6) {
                    Button(action: toggleWatch) {
                        Label(state.watching ? "Watching · stop" : "Watch", systemImage: state.watching ? "pause.circle.fill" : "eye")
                    }.buttonStyle(.plain).foregroundStyle(state.watching ? Color.green : Color.secondary)
                    Spacer()
                    Text(state.watching ? state.activity : "Go shares this window with OpenAI").lineLimit(1)
                    Button { state.expanded = false } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).help("Collapse to dot")
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 27).padding(.top, 10).padding(.bottom, 8)
            .background(WindowTabShape().fill(Color(nsColor: state.windowColor)))
            if !state.response.isEmpty {
                ScrollView {
                    Text(state.response).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.frame(height: 132)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.bottom, 6)
            }

        }
        .frame(width: 430)
        .environment(\.colorScheme, state.windowIsDark ? .dark : .light)
    }
}
