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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("pika dots").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8)
                    Text("A little company for your day. · 0.3").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Stop all sessions", systemImage: "pause.circle") { app.stopSession() }
                    Divider()
                    Button("Quit Pika Dots", systemImage: "power") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary.opacity(0.4), in: Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Pika Dots options")
            }

            HStack(spacing: 12) {
                Image(systemName: "hand.draw").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(-12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick a pal. Drop them anywhere.").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Drag onto a window to give it a purpose.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(14)
                .background(Color.accentColor.opacity(scheme == .dark ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.accentColor.opacity(0.08)))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("YOUR COMPANIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Text(app.attachedCount == 0 ? "3 ready to help" : "\(app.attachedCount) keeping you company")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 3)
                ForEach(app.agents) { agent in
                    CompanionCard(agent: agent, attachedApp: app.attachedApp(agent.id),
                        onDrop: { app.attach(agent, at: $0) }, onAttach: { app.attachToFrontmost(agent) })
                }
            }
            if !app.notice.isEmpty {
                Label(app.notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock.shield").font(.system(size: 11)).padding(.top, 1)
                Text("Go shares one window. Watch checks it every 45 seconds.")
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .padding(22).frame(width: 370)
        .background {
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [Color.orange.opacity(scheme == .dark ? 0.06 : 0.055), .clear, Color.purple.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

private struct CompanionCard: View {
    let agent: AgentDefinition
    let attachedApp: String?
    let onDrop: (NSPoint) -> Void
    let onAttach: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tint: Color { Color(nsColor: agent.color) }
    private var subtitle: String {
        switch agent.id {
        case "focus": return "Small nudges. Big intentions."
        case "chill": return "Permission to take a breath."
        default: return "A curious pair of extra eyes."
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            DraggableDot(agent: agent, onDrop: onDrop)
                .frame(width: 48, height: 48).padding(4)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomTrailing) {
                    if attachedApp != nil {
                        Circle().fill(.green).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)).padding(3)
                    }
                }
                .help("Drag \(agent.name) onto a window")
            Button(action: onAttach) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(agent.name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
                        Text(attachedApp.map { "With you in \($0)" } ?? subtitle)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hovering ? tint : Color.secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(tint.opacity(hovering ? 0.10 : 0), in: Circle())
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Attach \(agent.name) to the current window")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.95 : 0.65), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(hovering ? tint.opacity(0.35) : Color.primary.opacity(0.055)))
        .shadow(color: .black.opacity(hovering ? 0.045 : 0.015), radius: 8, y: 3)
        .offset(y: hovering && !reduceMotion ? -1 : 0)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
    }
}

@MainActor
final class BubbleState: ObservableObject {
    @Published var prompt = ""
    @Published var purpose = ""
    @Published var response = ""
    @Published var busy = false
    @Published var expanded = true
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
            if !state.response.isEmpty {
                ScrollView {
                    Text(state.response).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.frame(height: 132)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Purpose in \(state.window?.appName ?? "this window")…", text: $state.prompt)
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                        .onSubmit { if !state.busy { submit() } }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.white.opacity(0.07), in: Capsule())
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
            .background(WindowTabShape().fill(Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 0.98))))
        }
        .frame(width: 430)
        .environment(\.colorScheme, .dark)
    }
}
