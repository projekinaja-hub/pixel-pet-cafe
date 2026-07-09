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
