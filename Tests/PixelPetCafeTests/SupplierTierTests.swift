import XCTest
@testable import PixelPetCafe

/// "Ingredient prices are the same after upgrades, so we get too much money"
/// — premium suppliers scale cost-of-goods with the kitchen's own multiplier.
final class SupplierTierTests: XCTestCase {
    func testFreshCafeIsUnaffected() {
        let s = GameState.newGame()
        XCTAssertEqual(MenuCatalog.supplierTier(s), 1.0, accuracy: 1e-9)
    }

    func testUpgradedKitchenPaysMoreForIngredients() {
        var s = GameState.newGame()
        let baseCost = MenuCatalog.livePackCost("beans", units: 25, s)
        s.equipmentLevels["espresso"] = 20
        let upgradedCost = MenuCatalog.livePackCost("beans", units: 25, s)
        // Economy v2: equipMultiplier at 20 levels = 1 + 0.06×20 = 2.2, so
        // the supplier tier is 2.2^0.9 ≈ 2.03× the base ingredient cost.
        XCTAssertGreaterThan(upgradedCost, baseCost * 1.9,
                              "a level-20 kitchen should pay meaningfully premium ingredient prices")
    }

    func testSupplierTierIsSubLinearInEquipMultiplier() {
        var s = GameState.newGame()
        s.equipmentLevels["espresso"] = 30
        let equip = SalesEngine.equipMultiplier(s)
        XCTAssertLessThan(MenuCatalog.supplierTier(s), equip,
                           "cost growth must stay below price growth so upgrading remains net-positive")
        XCTAssertGreaterThan(MenuCatalog.supplierTier(s), pow(equip, 0.8))
    }
}
