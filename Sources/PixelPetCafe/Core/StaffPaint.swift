import Foundation

/// A single freehand-painted staff portrait, matching the 16×20 canvas every
/// generated staff sprite uses (see tools/generate_sprites.py's `character`
/// builder). When present for a staff id, it replaces the generated sprite
/// (and the simpler body/clothes color-mixing) entirely — literal drawing,
/// not just recoloring. `pixels` is row-major (row 0 = top, matching the
/// generator's own Canvas), each entry 0xRRGGBBAA or 0 for transparent.
struct PixelArt: Codable, Equatable {
    static let width = 16
    static let height = 20

    var pixels: [UInt32]

    static func blank() -> PixelArt {
        PixelArt(pixels: Array(repeating: 0, count: width * height))
    }

    /// Normalizes a decoded/pasted array to the expected length so a
    /// corrupt or version-mismatched save can't crash pixel lookups.
    var normalized: PixelArt {
        guard pixels.count == Self.width * Self.height else { return .blank() }
        return self
    }

    private func index(x: Int, y: Int) -> Int { y * Self.width + x }

    func color(x: Int, y: Int) -> UInt32 {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return 0 }
        return pixels[index(x: x, y: y)]
    }

    mutating func set(x: Int, y: Int, color: UInt32) {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return }
        pixels[index(x: x, y: y)] = color
    }

    var isBlank: Bool { !pixels.contains { $0 != 0 } }

    /// Mirrors tools/generate_sprites.py's Canvas.shifted_down() exactly —
    /// the walk cycle's second frame is the whole portrait nudged down one
    /// row, so custom art gets the same subtle bob every generated staff
    /// member already has, instead of standing perfectly still.
    func shiftedDown() -> PixelArt {
        var out = PixelArt.blank()
        for y in 0..<(Self.height - 1) {
            for x in 0..<Self.width {
                out.set(x: x, y: y + 1, color: color(x: x, y: y))
            }
        }
        return out
    }
}
