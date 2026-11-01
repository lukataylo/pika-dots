import SwiftUI

struct DraggableDot: NSViewRepresentable {
    let agent: AgentDefinition
    let onDrop: (NSPoint) -> Void
    func makeNSView(context: Context) -> DotDragView { let v = DotDragView(color: agent.color); v.onDrop = onDrop; return v }
    func updateNSView(_ view: DotDragView, context: Context) { view.onDrop = onDrop }
}

struct RosterView: View {
    @ObservedObject var app: AppController
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("pika dots").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8)
                    Text("A little company for your day.").font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text("Your window stays yours until you press Go.")
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
    let agent: AgentDefinition
    @Published var window: WindowContext?
    init(agent: AgentDefinition, window: WindowContext?) { self.agent = agent; self.window = window }
}

struct TaskBubble: View {
    @ObservedObject var state: BubbleState
    let submit: () -> Void
    let close: () -> Void
    let onDrop: (NSPoint) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                DraggableDot(agent: state.agent, onDrop: onDrop).frame(width: 48, height: 48).help("Drag me onto another window")
                TextField("My purpose in \(state.window?.appName ?? "this app")…", text: $state.prompt)
                    .textFieldStyle(.plain).font(.system(size: 14, weight: .medium))
                    .onSubmit { if !state.busy { submit() } }
                if state.busy { ProgressView().controlSize(.small) }
                else { Button(action: submit) { Image(systemName: "arrow.up.circle.fill").font(.title2) }.buttonStyle(.plain).disabled(state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Button(action: close) { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 10)
            if !state.purpose.isEmpty {
                Text(state.purpose).font(.caption).foregroundStyle(Color(nsColor: state.agent.color)).lineLimit(2).padding(.horizontal, 18).padding(.bottom, 8)
            }
            if !state.response.isEmpty {
                Divider()
                ScrollView { Text(state.response).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }.frame(height: 160)
            }
            HStack { Text(state.window?.label ?? "No window selected").lineLimit(1); Spacer(); Text("OpenAI · Go shares window") }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
        }
        .frame(width: 440)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.98)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
    }
}
