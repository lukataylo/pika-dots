import AppKit

struct PageElement: Codable, Equatable, Sendable {
    var id: String
    var role: String
    var label: String
    var value: String? = nil
    var visible: Bool
}

struct BrowserTab: Equatable, Sendable { var index: Int; var title: String; var url: String; var active: Bool }

struct PageSnapshot: Codable, Equatable, Sendable {
    var url: String
    var title: String
    var text: String
    var elements: [PageElement]
    /// The window's tabs; filled from AppleScript, not from the page.
    var tabs: [BrowserTab] = []
    enum CodingKeys: String, CodingKey { case url, title, text, elements }
    func element(_ id: String?) -> PageElement? { elements.first { $0.id == id } }
    var host: String { URL(string: url)?.host ?? url }
}

/// The page re-rendered between reading it and acting on it; the planner reads it again instead of stopping.
struct PageChanged: LocalizedError {
    var errorDescription: String? { "That part of the page changed. Pika is looking again." }
}

/// The operator's whole reach into the browser; a protocol so the planner can be tested against a fake page.
protocol PageDriving: Sendable {
    func snapshot() async throws -> PageSnapshot
    func perform(_ action: OperatorAction) async throws
}

/// Drives the active tab of the Chrome window the companion is attached to, with injected JavaScript.
/// Scripts travel as osascript argv, so page or model text is never spliced into AppleScript source.
final class ChromeOperator: PageDriving {
    static let bundleID = "com.google.Chrome"
    /// The attached window's bounds (top-left origin, as Chrome reports them). Without them, or when no
    /// window matches (it was moved or resized mid-run), the front window is used.
    private let bounds: CGRect?
    init(window bounds: CGRect? = nil) { self.bounds = bounds }
    /// argv: mode (js | newtab | tab | tabs), payload, then optionally the window's four bounds.
    private static let runner = """
    on run argv
        set op to item 1 of argv
        set arg to item 2 of argv
        set sep to character id 9
        tell application id "com.google.Chrome"
            set win to front window
            if (count of argv) is 6 then
                repeat with w in windows
                    set b to bounds of w
                    set isNear to true
                    repeat with i from 1 to 4
                        if (((item i of b) - ((item (i + 2) of argv) as integer)) ^ 2) > 9 then set isNear to false
                    end repeat
                    if isNear then
                        set win to w
                        exit repeat
                    end if
                end repeat
            end if
            if op is "js" then return execute (active tab of win) javascript arg
            if op is "newtab" then
                make new tab at end of tabs of win with properties {URL:arg}
                return "ok"
            end if
            if op is "tab" then
                set n to arg as integer
                if n < 1 or n > (count of tabs of win) then return "missing"
                set active tab index of win to n
                return "ok"
            end if
            set out to ""
            set activeIndex to active tab index of win
            repeat with i from 1 to (count of tabs of win)
                set t to item i of (tabs of win)
                set out to out & i & sep & (title of t) & sep & (URL of t) & sep & (i = activeIndex) & linefeed
            end repeat
            return out
        end tell
    end run
    """

    func snapshot() async throws -> PageSnapshot {
        // A read that lands mid-navigation returns nothing usable; give the new page a moment.
        for attempt in 1...3 {
            let json = try await execute(Self.snapshotJS)
            if var snapshot = try? JSONDecoder().decode(PageSnapshot.self, from: Data(json.utf8)) {
                snapshot.tabs = Self.parseTabs((try? await run("tabs", "")) ?? "")
                return snapshot
            }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(800)) }
        }
        throw PikaError.message("Couldn’t read this Chrome tab. Try reloading the page.")
    }

    private func execute(_ javaScript: String) async throws -> String { try await run("js", javaScript) }

    private func run(_ mode: String, _ payload: String) async throws -> String {
        let window = bounds.map { [$0.minX, $0.minY, $0.maxX, $0.maxY].map { String(Int($0.rounded())) } } ?? []
        return try await Self.execute([mode, payload] + window)
    }

    static func parseTabs(_ text: String) -> [BrowserTab] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let i = Int(f[0]) else { return nil }
            return BrowserTab(index: i, title: f[1], url: f[2], active: f[3] == "true")
        }
    }

    func perform(_ action: OperatorAction) async throws {
        if action.kind == .navigate || action.kind == .newTab {
            guard let url = action.url.flatMap(URL.init(string:)), url.scheme?.lowercased() == "https", url.host != nil else {
                throw PikaError.message("I only open https links.")
            }
        }
        if action.kind == .newTab { _ = try await run("newtab", action.url ?? ""); return }
        if action.kind == .switchTab {
            guard try await run("tab", action.text ?? "") == "ok" else { throw PageChanged() }
            return
        }
        guard [.click, .type, .scroll, .navigate].contains(action.kind) else { return }
        let payload: [String: String?] = ["kind": action.kind.rawValue, "id": action.elementID, "text": action.text, "url": action.url]
        // JSON string literals are valid JavaScript, so this is the escaping for user and model text.
        let literal = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"
        switch try await execute(Self.performJS.replacingOccurrences(of: "__ACTION__", with: literal)) {
        case "ok": return
        case "missing": throw PageChanged()
        case "not-editable": throw PikaError.message("That element doesn’t take text.")
        default: throw PikaError.message("Chrome didn’t accept that action.")
        }
    }

    static func execute(_ arguments: [String]) async throws -> String {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            throw PikaError.message("Open Google Chrome first.")
        }
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", runner] + arguments
        process.standardOutput = output; process.standardError = errors
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try process.run() } catch {
                        continuation.resume(throwing: PikaError.message("Couldn’t start osascript.")); return
                    }
                    // A modal dialog in Chrome can block Apple Events indefinitely.
                    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
                    let out = output.fileHandleForReading.readDataToEndOfFile()
                    let err = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); timeout.cancel()
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: PikaError.message("Chrome didn’t respond in time.")); return
                    }
                    let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if process.terminationStatus == 0 { continuation.resume(returning: text) }
                    else { continuation.resume(throwing: PikaError.message(describe(error: String(decoding: err, as: UTF8.self)))) }
                }
            }
        } onCancel: { process.terminate() }
    }

    static func describe(error: String) -> String {
        if error.contains("-1743") { return "Allow Pika to control Chrome in System Settings → Privacy & Security → Automation." }
        if error.localizedCaseInsensitiveContains("JavaScript") && (error.contains("turned off") || error.contains("Apple Events")) {
            return "In Chrome, turn on View → Developer → Allow JavaScript from Apple Events."
        }
        if error.contains("-600") || error.localizedCaseInsensitiveContains("isn’t running") || error.contains("isn't running") { return "Open Google Chrome first." }
        if error.contains("-1728") { return "Open a Chrome window first." }
        return "Chrome couldn’t run that step."
    }

    static let snapshotJS = #"""
    (() => {
      const clean = s => (s || '').replace(/\s+/g, ' ').trim();
      const sel = 'a[href],button,input:not([type=hidden]),textarea,select,[contenteditable]:not([contenteditable=false]),[role=button],[role=link],[role=textbox],[role=menuitem],[role=tab],[role=checkbox]';
      let next = 0;
      document.querySelectorAll('[data-pika-id]').forEach(e => { next = Math.max(next, parseInt(e.getAttribute('data-pika-id').slice(1)) || 0); });
      const shown = e => { const r = e.getBoundingClientRect(), s = getComputedStyle(e);
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth; };
      const role = e => { const t = e.tagName.toLowerCase();
        if (e.isContentEditable) return 'textbox';
        if ((t === 'button' || t === 'input') && e.type === 'submit' && e.form) return 'submit';
        if (t === 'input') return 'input:' + (e.type || 'text');
        return e.getAttribute('role') || (t === 'a' ? 'link' : t); };
      const label = e => { const t = e.tagName.toLowerCase(), field = t === 'textarea' || (t === 'input' && !['submit', 'button'].includes(e.type)) || e.isContentEditable;
        return clean(e.getAttribute('aria-label') || (e.labels && e.labels[0] && e.labels[0].innerText) || e.getAttribute('placeholder') || (field ? '' : e.innerText || e.value) || e.getAttribute('title') || e.getAttribute('name') || e.getAttribute('alt')).slice(0, 100); };
      const value = e => clean(e.isContentEditable ? e.innerText : (e.value || '')).slice(0, 200);
      const found = [...document.querySelectorAll(sel)].filter(e => !e.disabled && !(e.parentElement && e.parentElement.isContentEditable)).map(e => ({ e, v: shown(e) }));
      const picked = found.filter(x => x.v).concat(found.filter(x => !x.v)).slice(0, 60);
      const elements = picked.map(({ e, v }) => {
        if (!e.hasAttribute('data-pika-id')) e.setAttribute('data-pika-id', 'e' + (++next));
        const t = e.tagName.toLowerCase(), field = t === 'textarea' || t === 'input' || t === 'select' || e.isContentEditable;
        return { id: e.getAttribute('data-pika-id'), role: role(e), label: label(e), value: field ? value(e) : null, visible: v };
      });
      // Google Docs draws text on a canvas; typing goes to a hidden editable frame, offered as one element.
      if (document.querySelector('.docs-texteventtarget-iframe')) elements.unshift({ id: 'docs-body', role: 'textbox', label: 'Document body', value: null, visible: true });
      return JSON.stringify({ url: location.href, title: document.title, text: clean(document.body ? document.body.innerText : '').slice(0, 6000), elements });
    })()
    """#

    static let performJS = #"""
    (() => {
      const a = __ACTION__;
      if (a.kind === 'scroll') { scrollBy(0, (a.text === 'up' ? -0.8 : 0.8) * innerHeight); return 'ok'; }
      if (a.kind === 'navigate') { location.href = a.url; return 'ok'; }
      const e = [...document.querySelectorAll('[data-pika-id]')].find(x => x.getAttribute('data-pika-id') === a.id);
      if (a.id === 'docs-body' && a.kind === 'type') {
        const frame = document.querySelector('.docs-texteventtarget-iframe');
        const doc = frame && frame.contentDocument;
        if (!doc) return 'missing';
        const target = doc.querySelector('[contenteditable=true]') || doc.body;
        target.focus();
        // Docs takes pasted text through its own clipboard handler, which keeps paragraphs.
        const data = new DataTransfer();
        data.setData('text/plain', a.text || '');
        target.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
        return 'ok';
      }
      if (!e) return 'missing';
      e.scrollIntoView({ block: 'center' });
      if (a.kind === 'click') { e.click(); return 'ok'; }
      if (a.kind !== 'type') return 'unsupported';
      const text = a.text || '';
      e.focus();
      if (e.isContentEditable) {
        // insertText goes through the editor's own input pipeline, which rich editors (LinkedIn, Gmail) listen to.
        document.execCommand('selectAll', false);
        if (!document.execCommand('insertText', false, text)) {
          e.textContent = text;
          e.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
        }
        return 'ok';
      }
      const proto = e instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : e instanceof HTMLInputElement ? HTMLInputElement.prototype : null;
      if (!proto) return 'not-editable';
      // React tracks the last value it set; the native setter bypasses that so the input event registers.
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(e, text);
      e.dispatchEvent(new Event('input', { bubbles: true }));
      e.dispatchEvent(new Event('change', { bubbles: true }));
      return 'ok';
    })()
    """#
}
