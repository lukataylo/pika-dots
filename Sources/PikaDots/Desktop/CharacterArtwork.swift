import AppKit

@MainActor
enum CharacterArtwork {
    private static var cache: [String: NSImage] = [:]
    static func image(for id: String) -> NSImage? {
        if let image = cache[id] { return image }
        guard let url = Bundle.module.url(forResource: id, withExtension: "png", subdirectory: "Characters"), let image = NSImage(contentsOf: url) else { return nil }
        cache[id] = image
        return image
    }
}
