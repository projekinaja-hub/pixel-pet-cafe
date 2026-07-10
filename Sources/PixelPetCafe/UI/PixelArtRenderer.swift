import AppKit

/// Turns a `PixelArt` canvas into a real `NSImage` at runtime — the one
/// piece both CafeScene (wraps it in an SKTexture) and SwiftUI (Image(nsImage:))
/// need, since custom-painted staff have no PNG on disk to load like the
/// generated sprites do.
enum PixelArtRenderer {
    static func nsImage(_ art: PixelArt) -> NSImage {
        let w = PixelArt.width, h = PixelArt.height
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let c = art.color(x: x, y: y)
                let i = (y * w + x) * 4
                raw[i]     = UInt8((c >> 24) & 0xFF)
                raw[i + 1] = UInt8((c >> 16) & 0xFF)
                raw[i + 2] = UInt8((c >> 8) & 0xFF)
                raw[i + 3] = UInt8(c & 0xFF)
            }
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        raw.withUnsafeBufferPointer { buf in
            rep.bitmapData?.update(from: buf.baseAddress!, count: raw.count)
        }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }

    /// The character's untouchable fundamentals, per canvas cell: true where
    /// the paint editor must refuse the brush. Locked cells are (a) the
    /// generated "detail" layer — ink outline, eyes, ears' inner pixels,
    /// nose, apron stitching — and (b) everything OUTSIDE the character's
    /// silhouette (transparent in all four layers). So drawing can restyle
    /// fur and clothes freely but can never break the character's shape or
    /// face, and can't scribble into the empty space around them.
    static func protectionMask(id: String) -> [Bool] {
        let w = PixelArt.width, h = PixelArt.height
        var detailOpaque = [Bool](repeating: false, count: w * h)
        var anyOpaque = [Bool](repeating: false, count: w * h)
        for suffix in ["bodylight", "bodydark", "clothes", "detail"] {
            guard let url = Bundle.module.url(forResource: "staff_\(id)_\(suffix)_0",
                                              withExtension: "png", subdirectory: "Sprites"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else { continue }
            for y in 0..<min(h, rep.pixelsHigh) {
                for x in 0..<min(w, rep.pixelsWide) {
                    guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                    anyOpaque[y * w + x] = true
                    if suffix == "detail" { detailOpaque[y * w + x] = true }
                }
            }
        }
        return (0..<(w * h)).map { detailOpaque[$0] || !anyOpaque[$0] }
    }

    /// Composites a staff member's CURRENT on-screen look (the 4 generated
    /// layers, with the player's chosen body/clothes tint applied — same
    /// stacking order as CafeScene's staffSprite and StaffLayeredIcon) into
    /// an editable PixelArt. This is what seeds the paint editor: the canvas
    /// opens with the animal already there — shape, ears, eyes, apron — so
    /// the player colors/draws ON their staff rather than facing a blank
    /// grid and losing the character entirely.
    static func captureCurrentLook(id: String, pair: StaffColorPair) -> PixelArt {
        var art = PixelArt.blank()
        func bitmap(_ suffix: String) -> NSBitmapImageRep? {
            guard let url = Bundle.module.url(forResource: "staff_\(id)_\(suffix)_0",
                                              withExtension: "png", subdirectory: "Sprites"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return NSBitmapImageRep(data: data)
        }
        // (layer, flat tint) — nil tint = keep the layer's own authored colors
        let layers: [(String, StaffColor?)] = [
            ("bodylight", pair.body),
            ("bodydark", pair.body.darkened),
            ("clothes", pair.clothes),
            ("detail", nil),
        ]
        for (suffix, tint) in layers {
            guard let rep = bitmap(suffix) else { continue }
            for y in 0..<min(PixelArt.height, rep.pixelsHigh) {
                for x in 0..<min(PixelArt.width, rep.pixelsWide) {
                    guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                    if let tint {
                        art.set(x: x, y: y, color: .packRGBA(r: Int(tint.r), g: Int(tint.g), b: Int(tint.b)))
                    } else {
                        let rgb = c.usingColorSpace(.deviceRGB) ?? c
                        art.set(x: x, y: y, color: .packRGBA(r: Int(rgb.redComponent * 255),
                                                              g: Int(rgb.greenComponent * 255),
                                                              b: Int(rgb.blueComponent * 255)))
                    }
                }
            }
        }
        return art
    }
}

extension UInt32 {
    /// 0xRRGGBBAA packing shared by the editor UI and the runtime renderer.
    static func packRGBA(r: Int, g: Int, b: Int, a: Int = 255) -> UInt32 {
        UInt32((r << 24) | (g << 16) | (b << 8) | a)
    }
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        (Double((self >> 24) & 0xFF) / 255, Double((self >> 16) & 0xFF) / 255,
         Double((self >> 8) & 0xFF) / 255, Double(self & 0xFF) / 255)
    }
}
