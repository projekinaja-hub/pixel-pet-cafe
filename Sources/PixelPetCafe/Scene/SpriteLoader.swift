import AppKit
import SpriteKit

/// Loads generated pixel sprites from the bundle with crisp nearest filtering.
enum SpriteLoader {
    private static var cache: [String: SKTexture] = [:]

    static func texture(_ name: String) -> SKTexture {
        if let t = cache[name] { return t }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites"),
              let image = NSImage(contentsOf: url) else {
            let t = SKTexture()  // missing art: empty texture, game still runs
            cache[name] = t
            return t
        }
        let t = SKTexture(image: image)
        t.filteringMode = .nearest
        cache[name] = t
        return t
    }
}
