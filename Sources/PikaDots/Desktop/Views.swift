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
            HStack { Text("pika dots").font(.title2.bold()); Spacer(); Text("DEMO").font(.caption2.bold()).foregroundStyle(.secondary) }
            Text("Drag a companion onto a window, or click its name to attach to the current app.").font(.callout).foregroundStyle(.secondary)
            ForEach(app.agents) { agent in
                HStack(spacing: 12) {
                    DraggableDot(agent: agent) { app.attach(agent, at: $0) }.frame(width: 48, height: 48)
                    Button { app.attachToFrontmost(agent) } label: {
                        VStack(alignment: .leading) { Text(agent.name).font(.headline); Text(agent.summary).font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            Divider()
            HStack { Button("Stop session") { app.stopSession() }; Spacer(); Button("Quit") { NSApp.terminate(nil) } }.font(.caption)
        }.padding(20).frame(width: 330)
    }
}

@MainActor
final class BubbleState: ObservableObject {
    @Published var prompt = ""
    @Published var response = ""
    @Published var busy = false
    let agent: AgentDefinition
    let window: WindowContext?
    init(agent: AgentDefinition, window: WindowContext?) { self.agent = agent; self.window = window }
}

struct TaskBubble: View {
    @ObservedObject var state: BubbleState
    let submit: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Color(nsColor: state.agent.color)).frame(width: 18, height: 18)
                Text(state.agent.name).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Text(state.window?.label ?? "Desktop · no window selected").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            TextField("Give \(state.agent.name) a job…", text: $state.prompt).textFieldStyle(.roundedBorder).onSubmit { if !state.busy { submit() } }
            HStack { Text("Local demo provider").font(.caption2).foregroundStyle(.secondary); Spacer(); if state.busy { ProgressView().controlSize(.small) }; Button("Go", action: submit).disabled(state.busy || state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if !state.response.isEmpty { ScrollView { Text(state.response).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180) }
        }.padding(18).frame(width: 350).background(.regularMaterial)
    }
}
