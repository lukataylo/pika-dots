import SwiftUI

struct CompanionEditor: View {
    @ObservedObject var app: AppController
    @State private var selected: String?
    @State private var name = ""
    @State private var summary = ""
    @State private var color = Color.orange
    @State private var mode: AgentMode = .promptable
    @State private var purpose = ""
    @State private var watchYouTube = false
    @State private var pauseOnDistraction = false
    @State private var skill = "# My companion\nBe helpful, kind, and concise."
    @State private var key = ""
    @State private var status = ""
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !skill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (mode == .promptable || !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your pika dots").font(.system(size: 19, weight: .bold, design: .rounded))
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(app.agents) { agent in
                            Button { load(agent) } label: {
                                HStack { Circle().fill(Color(nsColor: agent.color)).frame(width: 10, height: 10); Text(agent.name); Spacer() }
                                    .padding(8).background(selected == agent.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button("New companion", systemImage: "plus") { reset() }
            }.padding(18).frame(width: 175)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                HStack { Text(selected == nil ? "Create a companion" : "Edit companion").font(.title2.bold()); Spacer(); ColorPicker("Colour", selection: $color).labelsHidden() }
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Short description", text: $summary).textFieldStyle(.roundedBorder)
                Picker("Behavior", selection: $mode) { Text("Promptable").tag(AgentMode.promptable); Text("Supervisor").tag(AgentMode.supervisor) }.pickerStyle(.segmented)
                Text(mode == .promptable ? "Click your dot to ask it a task." : "Starts on drop with a default purpose. Custom supervisors send this window to OpenAI immediately, then every 15 seconds while foreground. YouTube title checks run every 2 seconds.").font(.caption).foregroundStyle(.secondary)
                if mode == .supervisor { TextField("Default purpose (required)", text: $purpose).textFieldStyle(.roundedBorder) }
                if mode == .supervisor {
                    Toggle("Treat YouTube as a distraction", isOn: $watchYouTube)
                    Toggle("Pause screen on YouTube", isOn: $pauseOnDistraction).disabled(!watchYouTube)
                    Text("Turn YouTube detection off for video research. Pause screen interrupts browser typing until you continue or stop; it never closes tabs.").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Skill Markdown").font(.headline)
                TextEditor(text: $skill).font(.system(size: 12, design: .monospaced)).padding(5).background(.background).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary)).frame(minHeight: 160)
                Text("Saved as a .md file in Application Support. Saving updates this companion and dismisses its active attachment.").font(.caption2).foregroundStyle(.secondary)
                HStack {
                    if selected != nil { Button("Delete", role: .destructive) { remove() } }
                    Spacer()
                    Button("Save companion") { save() }.keyboardShortcut("s").disabled(!valid)
                }
                Divider()
                HStack {
                    SecureField("OpenAI API key (stored in this Mac’s Keychain)", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save key") {
                        do { try KeychainConfiguration.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; status = "API key saved securely." }
                        catch { status = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text(status).font(.caption).foregroundStyle(.secondary).frame(height: 28, alignment: .topLeading)
            }.padding(22) }.frame(width: 510)
        }.frame(height: 630)
    }
    private func reset() { selected = nil; name = ""; summary = ""; mode = .promptable; purpose = ""; watchYouTube = false; pauseOnDistraction = false; color = .orange; skill = "# My companion\nBe helpful, kind, and concise."; status = "" }
    private func load(_ agent: AgentDefinition) { selected = agent.id; name = agent.name; summary = agent.summary; color = Color(nsColor: agent.color); mode = agent.mode; purpose = agent.defaultPurpose; watchYouTube = agent.watchYouTube; pauseOnDistraction = agent.pauseOnDistraction; skill = agent.skillText; status = "" }
    private func save() {
        let agent = AgentDefinition(id: selected ?? UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: NSColor(color), summary: summary, skillText: skill, mode: mode, defaultPurpose: purpose, watchYouTube: watchYouTube, pauseOnDistraction: pauseOnDistraction)
        do { try app.saveCompanion(agent); selected = agent.id; status = "Companion saved." } catch { status = error.localizedDescription }
    }
    private func remove() { guard let selected else { return }; do { try app.deleteCompanion(selected); reset() } catch { status = error.localizedDescription } }
}
