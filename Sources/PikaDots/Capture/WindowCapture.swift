import AppKit
import ScreenCaptureKit

struct WindowCapture {
    static func capture(_ context: WindowContext) async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw PikaError.message("Allow Pika Dots in System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app. Only the selected window is sent when you press Go.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == context.windowID }) else {
            throw PikaError.message("This window is no longer available. Drag the dot onto an open window again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(2, 1600 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw PikaError.message("Could not encode the selected window.")
        }
        return data
    }
}
