import XCTest
@testable import PixelPetCafe

/// Regression tests for staff roles that used to go fully dead partway
/// through the level range — exposed once per-café level caps went up to
/// 135 (fancier cities), since several roles hard-capped their bonus at
/// level 25 with nothing beyond, and Marble did nothing at all past level 1.
final class RolePlateauFixTests: XCTestCase {
    func testJunoKeepsGrowingPastTheOldHardCap() {
        var s = GameState.newGame()
        s.staffLevels["juno"] = 25
        let at25 = SalesEngine.priceMultiplier(s)
        s.staffLevels["juno"] = 60
        let at60 = SalesEngine.priceMultiplier(s)
        XCTAssertGreaterThan(at60, at25, "Juno's price bonus must keep growing past level 25")
    }

    func testMochaAndPoppyKeepGrowingPastTheOldHardCap() {
        var s = GameState.newGame()
        s.staffLevels["mocha"] = 25
        let mochaAt25 = SalesEngine.categoryBonus(.drink, s)
        s.staffLevels["mocha"] = 60
        let mochaAt60 = SalesEngine.categoryBonus(.drink, s)
        XCTAssertGreaterThan(mochaAt60, mochaAt25)

        s.staffLevels["poppy"] = 25
        let poppyAt25 = SalesEngine.categoryBonus(.pastry, s)
        s.staffLevels["poppy"] = 60
        let poppyAt60 = SalesEngine.categoryBonus(.pastry, s)
        XCTAssertGreaterThan(poppyAt60, poppyAt25)
    }

    func testMarbleLevelOneOnlyGatesHiringNoDiscount() {
        var s = GameState.newGame()
        s.staffLevels["marble"] = 1
        XCTAssertEqual(MenuCatalog.marbleDiscount(s), 1, accuracy: 1e-9)
    }

    func testMarbleDiscountGrowsWithLevelAndFloors() {
        var s = GameState.newGame()
        s.staffLevels["marble"] = 10
        let atTen = MenuCatalog.marbleDiscount(s)
        XCTAssertLessThan(atTen, 1)
        s.staffLevels["marble"] = 500
        XCTAssertEqual(MenuCatalog.marbleDiscount(s), MenuCatalog.marbleDiscountFloor, accuracy: 1e-9)
    }

    func testMarbleDiscountActuallyReducesRestockCost() {
        var plain = GameState.newGame()
        plain.staffLevels["marble"] = 0
        var discounted = GameState.newGame()
        discounted.staffLevels["marble"] = 50
        let plainCost = MenuCatalog.livePackCost("beans", units: 25, plain)
        let discountedCost = MenuCatalog.livePackCost("beans", units: 25, discounted)
        XCTAssertLessThan(discountedCost, plainCost)
    }
}
