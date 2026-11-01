import AppKit
import ScreenCaptureKit

@MainActor
struct WindowCapture {
    static func capture(_ context: WindowContext) async throws -> Data {
        guard ScreenAccess.available else {
            throw PikaError.message("Screen access is off. Open Pika Dots settings to enable it, then retry.")
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            ScreenAccess.verified = true
        } catch {
            ScreenAccess.verified = false
            throw PikaError.message("Screen access changed. Check permissions in Pika settings, then restart.")
        }
        guard let window = content.windows.first(where: { $0.windowID == context.windowID }) else {
            throw PikaError.message("This window is no longer available. Drag the dot onto an open window again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(2, 1600 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        // JPEG keeps uploads a few hundred KB instead of several MB of PNG, which makes requests faster and steadier.
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            throw PikaError.message("Could not encode the selected window.")
        }
        return data
    }
}
