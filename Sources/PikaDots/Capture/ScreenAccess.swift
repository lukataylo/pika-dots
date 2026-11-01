import AppKit
import ScreenCaptureKit

@MainActor
enum ScreenAccess {
    // A real ScreenCaptureKit probe can recover when CGPreflight is stale after a toggle.
    static var verified: Bool?
    static var available: Bool { verified ?? CGPreflightScreenCaptureAccess() }
    static func probe() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            verified = true
        } catch { verified = false }
        return verified == true
    }
}

enum AppRelauncher {
    @MainActor static func restart() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$2\"", "pika-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }
}
