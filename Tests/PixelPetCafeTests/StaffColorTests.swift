import XCTest
@testable import PixelPetCafe

final class StaffColorTests: XCTestCase {
    func testUncustomizedStaffUsesShippedDefault() {
        let s = GameState.newGame()
        let pair = StaffPalette.pair(for: "mocha", in: s)
        XCTAssertEqual(pair, StaffPalette.defaults["mocha"])
    }

    func testSetStaffColorOverridesDefault() {
        var s = GameState.newGame()
        let body = StaffColor(r: 10, g: 20, b: 30)
        let clothes = StaffColor(r: 40, g: 50, b: 60)
        EconomyEngine.setStaffColor("mocha", body: body, clothes: clothes, &s)
        let pair = StaffPalette.pair(for: "mocha", in: s)
        XCTAssertEqual(pair.body, body)
        XCTAssertEqual(pair.clothes, clothes)
    }

    func testSetStaffColorIsFree() {
        var s = GameState.newGame()
        let coinsBefore = s.coins
        EconomyEngine.setStaffColor("mocha", body: StaffColor(r: 1, g: 2, b: 3), clothes: StaffColor(r: 4, g: 5, b: 6), &s)
        XCTAssertEqual(s.coins, coinsBefore)
    }

    func testResetStaffColorRestoresDefault() {
        var s = GameState.newGame()
        EconomyEngine.setStaffColor("mocha", body: StaffColor(r: 1, g: 2, b: 3), clothes: StaffColor(r: 4, g: 5, b: 6), &s)
        EconomyEngine.resetStaffColor("mocha", &s)
        XCTAssertEqual(StaffPalette.pair(for: "mocha", in: s), StaffPalette.defaults["mocha"])
    }

    func testDarkenedClampsAtZero() {
        let c = StaffColor(r: 10, g: 400, b: 0)
        let d = c.darkened
        XCTAssertEqual(d.r, 0)
        XCTAssertEqual(d.g, 360)
        XCTAssertEqual(d.b, 0)
    }

    func testEveryStaffRoleHasADefault() {
        for def in Catalog.staff {
            XCTAssertNotNil(StaffPalette.defaults[def.id], "\(def.id) is missing a default palette entry")
        }
    }

    func testStaffColorsRoundTripsThroughCodable() throws {
        var s = GameState.newGame()
        EconomyEngine.setStaffColor("chip", body: StaffColor(r: 99, g: 88, b: 77), clothes: StaffColor(r: 66, g: 55, b: 44), &s)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.staffColors["chip"], s.staffColors["chip"])
    }

    func testOldSaveWithoutStaffColorsDecodesToEmpty() throws {
        let json = """
        {"coins": 100, "cafes": [{"city": "home"}]}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertTrue(s.staffColors.isEmpty)
    }
}
