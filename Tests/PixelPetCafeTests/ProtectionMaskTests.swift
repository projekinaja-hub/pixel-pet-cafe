import XCTest
@testable import PixelPetCafe

/// The paint editor must never let drawing break a character's fundamentals:
/// the ink outline / face (the generated "detail" layer) and everything
/// outside the silhouette are locked. These tests pin the mask itself.
final class ProtectionMaskTests: XCTestCase {
    func testCornersOutsideTheSilhouetteAreLocked() {
        let mask = PixelArtRenderer.protectionMask(id: "mocha")
        XCTAssertEqual(mask.count, PixelArt.width * PixelArt.height)
        // The 16x20 canvas corners are empty space around every character.
        XCTAssertTrue(mask[0], "top-left corner should be locked (outside silhouette)")
        XCTAssertTrue(mask[PixelArt.width - 1], "top-right corner should be locked")
        XCTAssertTrue(mask[(PixelArt.height - 1) * PixelArt.width], "bottom-left corner should be locked")
    }

    func testSomeBodyPixelsRemainPaintable() {
        let mask = PixelArtRenderer.protectionMask(id: "mocha")
        let paintable = mask.filter { !$0 }.count
        // A character whose every pixel is locked would make the editor
        // pointless — the fur/clothes interior must stay paintable.
        XCTAssertGreaterThan(paintable, 40, "expected a meaningful paintable interior")
        // And a meaningful number of locked pixels too (outline + face +
        // the empty space around the sprite).
        XCTAssertGreaterThan(mask.filter { $0 }.count, 100)
    }

    func testEveryStaffRoleHasAValidMask() {
        for def in Catalog.staff {
            let mask = PixelArtRenderer.protectionMask(id: def.id)
            XCTAssertEqual(mask.count, PixelArt.width * PixelArt.height)
            XCTAssertTrue(mask.contains(false), "\(def.id) should have paintable pixels")
            XCTAssertTrue(mask.contains(true), "\(def.id) should have locked pixels")
        }
    }
}
