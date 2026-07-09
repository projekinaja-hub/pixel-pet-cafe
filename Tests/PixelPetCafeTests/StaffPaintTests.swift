import XCTest
@testable import PixelPetCafe

final class StaffPaintTests: XCTestCase {
    func testBlankCanvasHasExpectedSize() {
        let art = PixelArt.blank()
        XCTAssertEqual(art.pixels.count, PixelArt.width * PixelArt.height)
        XCTAssertTrue(art.isBlank)
    }

    func testSetAndGetPixel() {
        var art = PixelArt.blank()
        art.set(x: 3, y: 4, color: 0xFF0000FF)
        XCTAssertEqual(art.color(x: 3, y: 4), 0xFF0000FF)
        XCTAssertFalse(art.isBlank)
    }

    func testOutOfBoundsSetIsIgnored() {
        var art = PixelArt.blank()
        art.set(x: -1, y: 0, color: 0xFF0000FF)
        art.set(x: 100, y: 0, color: 0xFF0000FF)
        XCTAssertTrue(art.isBlank)
    }

    func testShiftedDownMovesEveryPixelDownOneRowAndDropsTheBottomRow() {
        var art = PixelArt.blank()
        art.set(x: 0, y: 0, color: 0xAABBCCFF)
        art.set(x: 5, y: PixelArt.height - 1, color: 0x112233FF)
        let shifted = art.shiftedDown()
        XCTAssertEqual(shifted.color(x: 0, y: 1), 0xAABBCCFF)
        XCTAssertEqual(shifted.color(x: 0, y: 0), 0)
        // the bottom row's pixel has nowhere to go and is dropped, same as
        // the Python generator's Canvas.shifted_down()
        XCTAssertEqual(shifted.color(x: 5, y: PixelArt.height - 1), 0)
    }

    func testNormalizedRecoversFromWrongLengthArray() {
        let corrupt = PixelArt(pixels: [1, 2, 3])
        XCTAssertEqual(corrupt.normalized, .blank())
    }

    func testSetStaffPaintStoresNonBlankArt() {
        var s = GameState.newGame()
        var art = PixelArt.blank()
        art.set(x: 0, y: 0, color: 0xFFFFFFFF)
        EconomyEngine.setStaffPaint("mocha", art, &s)
        XCTAssertEqual(s.staffPaint["mocha"], art)
    }

    func testSetStaffPaintWithBlankArtClearsInsteadOfStoring() {
        var s = GameState.newGame()
        var art = PixelArt.blank()
        art.set(x: 0, y: 0, color: 0xFFFFFFFF)
        EconomyEngine.setStaffPaint("mocha", art, &s)
        EconomyEngine.setStaffPaint("mocha", .blank(), &s)
        XCTAssertNil(s.staffPaint["mocha"])
    }

    func testResetStaffPaintRemovesIt() {
        var s = GameState.newGame()
        var art = PixelArt.blank()
        art.set(x: 0, y: 0, color: 0xFFFFFFFF)
        EconomyEngine.setStaffPaint("mocha", art, &s)
        EconomyEngine.resetStaffPaint("mocha", &s)
        XCTAssertNil(s.staffPaint["mocha"])
    }

    func testStaffPaintIsFree() {
        var s = GameState.newGame()
        let coinsBefore = s.coins
        var art = PixelArt.blank()
        art.set(x: 0, y: 0, color: 0xFFFFFFFF)
        EconomyEngine.setStaffPaint("mocha", art, &s)
        XCTAssertEqual(s.coins, coinsBefore)
    }

    func testStaffPaintRoundTripsThroughCodable() throws {
        var s = GameState.newGame()
        var art = PixelArt.blank()
        art.set(x: 2, y: 2, color: 0x11223344)
        EconomyEngine.setStaffPaint("chip", art, &s)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.staffPaint["chip"], art)
    }

    func testOldSaveWithoutStaffPaintDecodesToEmpty() throws {
        let json = """
        {"coins": 100, "cafes": [{"city": "home"}]}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertTrue(s.staffPaint.isEmpty)
    }
}
