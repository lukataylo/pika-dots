import SwiftUI

struct DraggableDot: NSViewRepresentable {
    let agent: AgentDefinition
    let onDrop: (NSPoint) -> Void
    func makeNSView(context: Context) -> DotDragView { let v = DotDragView(color: agent.color); v.onDrop = onDrop; return v }
    func updateNSView(_ view: DotDragView, context: Context) { view.onDrop = onDrop }
}

struct RosterView: View {
    @ObservedObject var app: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("pika dots").font(.title2.bold()); Spacer(); Text("YOUR LITTLE TEAM").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            Text("Drag a dot onto any window. Give it a purpose, right where you work.").font(.callout).foregroundStyle(.secondary)
            ForEach(app.agents) { agent in
                HStack(spacing: 12) {
                    DraggableDot(agent: agent) { app.attach(agent, at: $0) }.frame(width: 48, height: 48)
                    Button { app.attachToFrontmost(agent) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(agent.name).font(.headline); Text(agent.summary).font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            if !app.notice.isEmpty { Text(app.notice).font(.caption).foregroundStyle(.orange) }
            Divider()
            Text("Go sends only the attached window image and your task to OpenAI.").font(.caption2).foregroundStyle(.secondary)
            HStack { Button("Stop all") { app.stopSession() }; Spacer(); Button("Quit") { NSApp.terminate(nil) } }.font(.caption)
        }.padding(20).frame(width: 340)
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
