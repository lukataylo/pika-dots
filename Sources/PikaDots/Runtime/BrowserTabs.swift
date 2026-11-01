import AppKit

/// The one action Pika takes in another app: closing the front YouTube tab, and only
/// when the user enabled it. The script re-checks the URL so it can never close other pages.
enum BrowserTabs {
    enum Outcome: Equatable { case closed, notYouTube, unsupported, notAllowed, failed }

    static func script(bundleID: String) -> String? {
        let tab: String
        switch bundleID {
        case "com.apple.Safari": tab = "current tab"
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser": tab = "active tab"
        default: return nil
        }
        return """
        tell application id "\(bundleID)"
            set t to \(tab) of front window
            if (URL of t) contains "youtube.com" then
                close t
                return "closed"
            end if
        end tell
        return "kept"
        """
    }

    @MainActor
    static func closeYouTube(pid: pid_t, completion: @escaping @MainActor (Outcome) -> Void) {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, let source = script(bundleID: bundleID) else {
            completion(.unsupported); return
        }
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = output; process.standardError = errors
        process.terminationHandler = { finished in
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let outcome: Outcome = finished.terminationStatus == 0
                ? (text.contains("closed") ? .closed : .notYouTube)
                : (error.contains("-1743") ? .notAllowed : .failed)
            Task { @MainActor in completion(outcome) }
        }
        do { try process.run() } catch { completion(.failed) }
    }
}
