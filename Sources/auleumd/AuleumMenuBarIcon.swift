import AppKit

enum AuleumGlyph {
    /// The menu bar icon is a black-and-white reduction of the app icon:
    /// the curtain with its rod and lit center opening, drawn as the ink
    /// itself with a transparent background. The artwork was generated
    /// with the image model; the PNGs in Resources are the template
    /// renderings (18/36/54 px).
    static func image() -> NSImage {
        if let image = menuBarImage {
            return image
        }
        return fallbackImage
    }

    private static let menuBarImage: NSImage? = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        var added = false
        for scale in 1...3 {
            let name = scale == 1 ? "MenuBarIcon" : "MenuBarIcon@\(scale)x"
            guard let url = resourceURL(name),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else {
                continue
            }
            representation.size = NSSize(width: 18, height: 18)
            image.addRepresentation(representation)
            added = true
        }
        guard added else { return nil }
        image.isTemplate = true
        return image
    }()

    private static let fallbackImage: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let symbol = NSImage(
            systemSymbolName: "curtains.closed",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) {
            symbol.isTemplate = true
            return symbol
        }
        return NSImage(size: NSSize(width: 18, height: 18))
    }()

    private static func resourceURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return url
        }
        // Running the bare executable from the repository (previews, tests).
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/\(name).png")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    static func brandImage(size: CGFloat = 48, filled: Bool = true) -> NSImage {
        let symbolName = filled ? "lock.fill" : "lock.open"
        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: size * 0.72, weight: .medium)
        ) else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let target = NSRect(
                x: rect.midX - symbol.size.width / 2,
                y: rect.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: target)
            return true
        }
        image.isTemplate = true
        return image
    }
}
