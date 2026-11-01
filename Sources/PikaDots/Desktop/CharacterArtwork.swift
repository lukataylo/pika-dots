import AppKit

@MainActor
enum CharacterArtwork {
    private static var cache: [String: NSImage] = [:]
    private static var feet: [String: CGFloat] = [:]

    /// Transparent space below the paws as a fraction of the art's height, so a cat can sit
    /// exactly on a window edge whatever its drawing. The vector fallback cat stands at 5/48.
    static func footInset(for id: String) -> CGFloat {
        if let inset = feet[id] { return inset }
        var inset: CGFloat = 5.0 / 48
        if let bitmap = image(for: id)?.representations.first as? NSBitmapImageRep {
            // NSBitmapImageRep rows run top to bottom; find the lowest opaque row.
            let height = bitmap.pixelsHigh
            outer: for row in stride(from: height - 1, through: 0, by: -1) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) where (bitmap.colorAt(x: x, y: row)?.alphaComponent ?? 0) > 0.5 {
                    inset = CGFloat(height - 1 - row) / CGFloat(height); break outer
                }
            }
        }
        feet[id] = inset
        return inset
    }
    static func image(for id: String) -> NSImage? {
        if let image = cache[id] { return image }
        guard let url = Bundle.module.url(forResource: id, withExtension: "png", subdirectory: "Characters"), let source = NSImage(contentsOf: url) else { return nil }
        // The bundled PNGs are 1254px. Drawn as-is, every animation frame re-decoded the PNG
        // (~30% CPU per cat), so render once into a small bitmap sized for a 48pt cat at 3x.
        let pixels = 192
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 48, height: 48))
        image.addRepresentation(bitmap)
        cache[id] = image
        return image
    }
}
