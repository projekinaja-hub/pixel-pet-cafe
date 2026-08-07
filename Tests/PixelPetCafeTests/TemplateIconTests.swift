import XCTest
import AppKit
@testable import PixelPetCafe

/// The "subtle" menu-bar look converts the sprite to a template image. Done
/// wrong, that produces something fully transparent — and a transparent menu
/// bar icon doesn't look subtle, it looks like the app crashed.
@MainActor
final class TemplateIconTests: XCTestCase {

    /// A little pixel-art stand-in: dark outline, mid body, pale belly.
    ///
    /// Built by writing raw bytes. The first version used
    /// `NSBitmapImageRep.setColor`, which produced a completely transparent
    /// image — so the test was feeding the conversion a blank swatch and then
    /// blaming the conversion for the blank result.
    private func swatch(w: Int = 8, h: Int = 8) -> NSImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let rgb: (UInt8, UInt8, UInt8)
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                    rgb = (52, 34, 41)          // outline
                } else if y < h / 2 {
                    rgb = (150, 102, 66)        // body
                } else {
                    rgb = (247, 233, 205)       // pale belly
                }
                bytes[i] = rgb.0; bytes[i + 1] = rgb.1; bytes[i + 2] = rgb.2; bytes[i + 3] = 255
            }
        }
        var image = NSImage(size: NSSize(width: w, height: h))
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return }
            image = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }
        return image
    }

    /// Guards the guard: if the fixture is blank, every other assertion here
    /// is meaningless.
    func testTheFixtureItselfIsNotBlank() {
        let a = alphas(swatch())
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { $0 > 0.99 }, "the test swatch is transparent, so it tests nothing")
    }

    /// Reads the image's pixels through CoreGraphics.
    ///
    /// This helper has now been wrong twice, in both cases reporting a
    /// perfectly good image as entirely transparent: first via `colorAt`
    /// (unreliable across bitmap formats), then by looking for an
    /// `NSBitmapImageRep` the image no longer has. Measuring the same way the
    /// implementation writes is the only version that stays honest.
    private func pixels(_ image: NSImage) -> (w: Int, h: Int, bytes: [UInt8]) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (0, 0, [])
        }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, bytes)
    }

    private func alphas(_ image: NSImage) -> [CGFloat] {
        let p = pixels(image)
        return stride(from: 0, to: p.bytes.count, by: 4).map { CGFloat(p.bytes[$0 + 3]) / 255 }
    }

    private func alpha(_ image: NSImage, x: Int, y: Int) -> CGFloat {
        let p = pixels(image)
        guard p.w > 0, x < p.w, y < p.h else { return 0 }
        return CGFloat(p.bytes[(y * p.w + x) * 4 + 3]) / 255
    }

    func testTemplateIsFlaggedAsATemplate() {
        XCTAssertTrue(StatusItemController.templated(swatch()).isTemplate,
                      "without isTemplate, AppKit won't recolour it for the menu bar")
    }

    /// THE failure that matters: an icon nobody can see.
    func testTemplateIsActuallyVisible() {
        let a = alphas(StatusItemController.templated(swatch()))
        XCTAssertFalse(a.isEmpty, "the conversion produced no pixels at all")
        let visible = a.filter { $0 > 0.15 }.count
        XCTAssertGreaterThan(Double(visible) / Double(a.count), 0.5,
                             "only \(visible)/\(a.count) pixels are visible — the icon would look missing")
    }

    /// Darkness becomes ink: the outline must end up more opaque than the pale
    /// belly, or the sprite flattens into a featureless blob.
    func testDarkerPixelsCarryMoreInk() {
        let img = StatusItemController.templated(swatch())
        let outline = alpha(img, x: 0, y: 0)     // border is outline on every side
        let belly = alpha(img, x: 4, y: 4)       // interior fur
        XCTAssertGreaterThan(outline, belly, "the outline should read stronger than pale fur")
        XCTAssertGreaterThan(belly, 0.15, "pale fur must still be part of the silhouette")
    }

    func testFullyTransparentPixelsStayTransparent() {
        var bytes = [UInt8](repeating: 0, count: 2 * 2 * 4)     // all zero = clear
        var img = NSImage(size: NSSize(width: 2, height: 2))
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 2, height: 2,
                                      bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return }
            img = NSImage(cgImage: cg, size: NSSize(width: 2, height: 2))
        }
        XCTAssertTrue(alphas(StatusItemController.templated(img)).allSatisfy { $0 < 0.01 },
                      "empty space around the sprite must not become ink")
    }
}
