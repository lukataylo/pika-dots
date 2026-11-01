import SwiftUI

struct DraggableDot: NSViewRepresentable {
    let agent: AgentDefinition
    let onDrop: (NSPoint) -> Void
    var onClick: (() -> Void)? = nil
    var upsideDown = false
    func makeNSView(context: Context) -> DotDragView { let v = DotDragView(color: agent.color); v.onDrop = onDrop; v.onClick = onClick; v.artwork = CharacterArtwork.image(for: agent.id); v.upsideDown = upsideDown; v.setAccessibilityLabel(agent.name); return v }
    func updateNSView(_ view: DotDragView, context: Context) { view.onDrop = onDrop; view.onClick = onClick; view.artwork = CharacterArtwork.image(for: agent.id); view.upsideDown = upsideDown }
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
    /// Session length in minutes for Focus and Chill; 0 means no limit.
    @Published var lengthMinutes = 0
    @Published var listening = false
    @Published var reply: String?
    /// An outward action (send, connect, post…) waiting for the user's explicit OK.
    @Published var approval: String?
    @Published var replyTitle = ""
    /// A short line the cat says in its speech bubble; replaced by a full reply card when one arrives.
    @Published var speech: String?
    /// Where the bubble's tail points: the cat's centre, measured from the bubble's left edge.
    @Published var tailX: CGFloat = 27
    @Published var peeking = false
    /// Identifies the in-flight request so a cancelled one cannot clear a newer one's busy state.
    var requestToken: UUID?
    var startedAt: Date?
    let agent: AgentDefinition
    @Published var window: WindowContext?
    init(agent: AgentDefinition, window: WindowContext?) {
        self.agent = agent; self.window = window
        if let options = SessionLength.options(for: agent.id) {
            let saved = UserDefaults.standard.object(forKey: SessionLength.key(agent.id)) as? Int
            lengthMinutes = saved.flatMap { options.contains($0) ? $0 : nil } ?? SessionLength.defaultMinutes(for: agent.id)
        }
    }
}

enum SessionLength {
    static func options(for id: String) -> [Int]? {
        switch id { case "focus": [15, 25, 50, 0]; case "chill": [1, 2, 5, 10]; default: nil }
    }
    static func defaultMinutes(for id: String) -> Int { id == "chill" ? 2 : 25 }
    /// Actions takes whole tasks in a sentence, so its pill is wide enough for the example placeholder.
    static func pillWidth(for id: String) -> CGFloat { id == "outreach" ? 360 : 240 }
    static func key(_ id: String) -> String { "length.\(id)" }
    static func label(_ minutes: Int) -> String { minutes == 0 ? "∞" : "\(minutes)m" }
    static func placeholder(for id: String) -> String {
        switch id {
        case "focus": "What are you finishing?"
        case "chill": "What would help you rest?"
        case "explain": "Ask about this window…"
        case "outreach": "Say or type a task, e.g. research German Shepherds and write a Google Doc"
        default: "Give me a purpose…"
        }
    }
}

struct PerchedDot: View {
    @ObservedObject var state: BubbleState
    let onDrop: (NSPoint) -> Void
    let toggle: () -> Void
    let dismiss: () -> Void
    let settings: () -> Void
    let toggleWatch: () -> Void
    var checkNow: (() -> Void)? = nil
    var talk: (() -> Void)? = nil
    var perch: ((CGFloat) -> Void)? = nil
    @State private var hovering = false
    @AppStorage("actions.yolo") private var yolo = false
    var body: some View {
        DraggableDot(agent: state.agent, onDrop: onDrop, onClick: toggle, upsideDown: state.peeking)
            .frame(width: 40, height: 40)
            .padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 2)
            .overlay(alignment: state.peeking ? .bottomTrailing : .topTrailing) {
                if state.watching { Circle().fill(state.supervisionError ? .orange : .green).frame(width: 4, height: 4).padding(5) }
            }
            .overlay(alignment: state.peeking ? .topTrailing : .bottomTrailing) {
                // The purpose pill collapses on send, so the cat carries the "thinking" state.
                if state.busy { ProgressView().controlSize(.mini).padding(2) }
            }
            .overlay(alignment: state.peeking ? .bottomLeading : .topLeading) {
                if let talk, hovering || state.listening {
                    Button(action: talk) {
                        Image(systemName: state.listening ? "waveform" : "mic.fill").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).frame(width: 20, height: 20)
                            .background(state.listening ? Color.red : Color(nsColor: state.agent.color), in: Circle())
                    }.buttonStyle(.plain).padding(2).help(state.listening ? "Stop listening" : "Talk to \(state.agent.name)")
                }
            }
            .overlay(alignment: state.peeking ? .topLeading : .bottomLeading) {
                if yolo && state.agent.id == "outreach" && !(hovering && talk != nil) {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Color.orange, in: Circle()).padding(2)
                        .help("YOLO is on: Actions runs without asking. Payments still ask.")
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                Text(state.supervisionStatus)
                if let checkNow { Button("Check now", action: checkNow) }
                Divider()
                Button(state.expanded ? "Hide purpose" : "Set purpose", action: toggle)
                Button(state.agent.id == "focus" ? (state.watching ? "End session" : "Start session")
                       : state.agent.id == "chill" ? (state.watching ? "End break" : "Start break")
                       : (state.watching ? "Pause supervision" : "Start supervision"), action: toggleWatch)
                if state.agent.id == "outreach" {
                    Toggle("YOLO: run without asking. Payments still ask.", isOn: $yolo)
                    Button("Forget earlier research") { OperatorMemory().clear() }
                }
                if let perch {
                    Menu("Perch") {
                        Button("Left") { perch(0.12) }
                        Button("Centre") { perch(0.5) }
                        Button("Right") { perch(0.88) }
                    }
                }
                Button("Settings…", action: settings)
                Divider()
                Button("Dismiss \(state.agent.name)", systemImage: "xmark.circle", action: dismiss)
            }
            .help("\(state.agent.name) · \(state.supervisionStatus) · drag along the edge to move, right-click for controls")
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
    var talk: () -> Void = {}
    @AppStorage("actions.yolo") private var yolo = false
    var body: some View {
        HStack(spacing: 8) {
            if let options = SessionLength.options(for: state.agent.id) {
                Menu {
                    ForEach(options, id: \.self) { minutes in
                        Button(minutes == 0 ? "No time limit" : "\(minutes) minutes") { state.lengthMinutes = minutes }
                    }
                } label: { Text(SessionLength.label(state.lengthMinutes)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit() }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.primary.opacity(0.07), in: Capsule())
                .help(state.agent.id == "chill" ? "Break length" : "Session length")
            }
            TextField(SessionLength.placeholder(for: state.agent.id), text: $state.prompt)
                .textFieldStyle(.plain).font(.system(size: 11))
                .onSubmit { if !state.busy { submit() } }
                // Borderless non-activating panels can drop the field editor's Return action.
                .onKeyPress(.return) { if !state.busy { submit() }; return .handled }
            if state.agent.id == "outreach" {
                Button { yolo.toggle() } label: { Image(systemName: yolo ? "bolt.fill" : "bolt").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(yolo ? Color.orange : Color.secondary)
                    .help(yolo ? "YOLO on: run without asking. Payments still ask." : "Turn on YOLO: run without asking. Payments still ask.")
            }
            // Actions is voice-first, so its mic is filled and in the cat's colour.
            Button(action: talk) { Image(systemName: state.listening ? "waveform" : state.agent.id == "outreach" ? "mic.fill" : "mic").font(.system(size: state.agent.id == "outreach" ? 12 : 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(state.listening ? Color.red : state.agent.id == "outreach" ? Color(nsColor: state.agent.color) : Color.secondary)
                .help(state.listening ? "Stop listening" : "Speak instead of typing")
            if state.busy { ProgressView().controlSize(.mini) }
            else {
                Button(action: submit) { Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).help("Send")
            }
        }
        .padding(.horizontal, 12).frame(width: SessionLength.pillWidth(for: state.agent.id), height: 32)
        .background(Color(nsColor: state.windowColor), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.07)))
        .environment(\.colorScheme, state.windowIsDark ? .dark : .light)
        .onExitCommand { state.expanded = false }
    }
}

/// The cat's speech bubble, just below it with a tail pointing at the cat. Short lines
/// (nudges, status) show as a compact bubble; full answers and recaps as a readable card.
struct ReplyCard: View {
    static let width: CGFloat = 320
    static let tail: CGFloat = 7
    private static let bodyFont = NSFont.systemFont(ofSize: 12.5)
    private static let speechFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    @ObservedObject var state: BubbleState
    let close: () -> Void
    var decide: (Bool) -> Void = { _ in }
    var dismissSpeech: () -> Void = {}
    @State private var copied = false

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.lineSpacing = spacing
        return ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: style]).height)
    }
    static func bodyHeight(_ text: String) -> CGFloat { min(220, textHeight(text, font: bodyFont, width: width - 28, spacing: 3) + 4) }
    static func height(_ text: String, actions: Bool = false) -> CGFloat { bodyHeight(text) + 56 + (actions ? 34 : 0) + tail }
    static func speechWidth(_ text: String) -> CGFloat {
        let single = ceil((text as NSString).size(withAttributes: [.font: speechFont]).width)
        return min(280, max(78, single + 44))
    }
    /// 26pt of padding plus 18pt for the close button.
    static func speechHeight(_ text: String) -> CGFloat { textHeight(text, font: speechFont, width: speechWidth(text) - 44, spacing: 2) + 20 + tail }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Tail().fill(.regularMaterial).frame(width: 14, height: Self.tail)
                .offset(x: max(10, min(state.tailX, (state.reply == nil ? Self.speechWidth(state.speech ?? "") : Self.width) - 24)) - 7)
            if let reply = state.reply { card(reply) }
            else if let speech = state.speech {
                HStack(alignment: .top, spacing: 6) {
                    Text(speech).font(.system(size: 12.5, weight: .medium)).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: dismissSpeech) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 2).help("Dismiss")
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .frame(width: Self.speechWidth(speech), alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissSpeech)
            }
        }
        .frame(width: Self.width, alignment: .topLeading)
        .onChange(of: state.reply) { copied = false }
        .onExitCommand { if state.reply != nil { close() } else { dismissSpeech() } }
    }

    private func card(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(Color(nsColor: state.agent.color)).frame(width: 7, height: 7)
                Text(state.replyTitle).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy")
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Close")
            }
            ScrollView {
                Text(Self.formatted(text)).font(.system(size: 12.5)).lineSpacing(3)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: Self.bodyHeight(text))
            if state.approval != nil {
                HStack {
                    Spacer()
                    Button("Stop") { decide(false) }.keyboardShortcut(.cancelAction)
                    Button("Approve") { decide(true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }.controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: Self.width, height: Self.height(text, actions: state.approval != nil) - Self.tail, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    private struct Tail: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath(); return path
        }
    }

    static func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
