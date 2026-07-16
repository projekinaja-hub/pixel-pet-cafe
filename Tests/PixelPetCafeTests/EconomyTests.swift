import XCTest
@testable import PixelPetCafe

final class EconomyTests: XCTestCase {

    // MARK: costs & buying

    func testCostCurveGeometric() {
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 0, growth: 1.14), 100, accuracy: 1e-9)
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 3, growth: 1.14), 100 * pow(1.14, 3), accuracy: 1e-9)
        // Economy v2 growth rates: staff 1.14, equipment 1.17.
        XCTAssertEqual(EconomyEngine.staffCostGrowth, 1.14, accuracy: 1e-9)
        XCTAssertEqual(EconomyEngine.equipmentCostGrowth, 1.17, accuracy: 1e-9)
        var s = GameState.newGame()
        s.equipmentLevels["espresso"] = 4
        XCTAssertEqual(EconomyEngine.equipmentCost("espresso", s), 100 * pow(1.17, 4), accuracy: 1e-6)
    }

    func testBuyStaffSpendsCoinsAndLevels() {
        var s = GameState.newGame()
        s.coins = 1_000_000
        let costBefore = EconomyEngine.staffCost("biscuit", s)
        XCTAssertTrue(EconomyEngine.buyStaff("biscuit", &s))
        XCTAssertEqual(s.staffLevels["biscuit"], 1)
        XCTAssertEqual(s.coins, 1_000_000 - costBefore, accuracy: 1e-6)
    }

    func testBuyFailsWhenBroke() {
        var s = GameState.newGame()
        s.coins = 0
        XCTAssertFalse(EconomyEngine.buyStaff("biscuit", &s))
        XCTAssertFalse(EconomyEngine.buyEquipment("espresso", &s))
    }

    // MARK: offline cap

    func testEarlExtendsOfflineCap() {
        var s = GameState.newGame()
        s.staffLevels["earl"] = 3
        XCTAssertEqual(EconomyEngine.offlineCap(s), (8 + 3) * 3600, accuracy: 1e-9)
    }

    // MARK: prestige

    func testPrestigeStarsFormula() {
        var s = GameState.newGame()
        // log formula: 1 + floor(10 * log10(run / threshold))
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 9
        XCTAssertEqual(EconomyEngine.prestigeStars(s), 10)   // 1 + floor(9.54)
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 1e18
        XCTAssertEqual(EconomyEngine.prestigeStars(s), 181, "even a 1e24 run stays on a human scale")
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold - 1
        XCTAssertEqual(EconomyEngine.prestigeStars(s), 0)
        XCTAssertFalse(EconomyEngine.canRenovate(s))
    }

    func testRenovateResetsRunKeepsStyleAndCustoms() {
        var s = GameState.newGame()
        s.coins = 5_000_000
        s.lifetimeCoins = 9_000_000
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 4
        s.staffLevels = ["mocha": 10, "biscuit": 4]
        s.equipmentLevels = ["oven": 3]
        s.stock = ["beans": 500]
        s.cleanliness = 12
        s.owner.species = "owl"
        s.barCharacter = "juno"
        let custom = CustomMenuItem(id: "c1", name: "Leo Special", icon: "cookie",
                                    category: .special, ingredients: ["honey": 2])
        s.customItems = [custom]
        EconomyEngine.renovate(&s)
        XCTAssertEqual(s.stars, 7)   // 1 + floor(10 * log10(4))
        XCTAssertEqual(s.coins, 0)
        XCTAssertEqual(s.staffLevels, ["mocha": 1])
        XCTAssertEqual(s.stock, GameState.starterStock)
        XCTAssertEqual(s.cleanliness, 100)
        XCTAssertEqual(s.owner.species, "owl")           // style survives
        XCTAssertEqual(s.barCharacter, "juno")
        XCTAssertEqual(s.customItems, [custom])          // custom items survive
        XCTAssertTrue(s.menuEnabled.contains("c1"))
        XCTAssertTrue(s.menuEnabled.contains("honey_cake"))  // lifetime 9M keeps unlocks
    }

    // MARK: formatting

    func testNumberFormatting() {
        XCTAssertEqual(formatNumber(0), "0")
        XCTAssertEqual(formatNumber(950), "950")
        XCTAssertEqual(formatNumber(1_234), "1.2K")
        XCTAssertEqual(formatNumber(56_780_000), "56.8M")
        XCTAssertEqual(formatNumber(3.2e9), "3.2B")
        XCTAssertEqual(formatNumber(7.5e12), "7.5T")
        XCTAssertEqual(formatNumber(3.4e15), "3.4Qa")
        XCTAssertEqual(formatNumber(2.25e18), "2.3Qi")
    }
}


final class StarMigrationTests: XCTestCase {
    func testSaneStarCountsAreUntouched() {
        XCTAssertEqual(EconomyEngine.normalizedStars(0), 0)
        XCTAssertEqual(EconomyEngine.normalizedStars(172), 172)
        XCTAssertEqual(EconomyEngine.normalizedStars(1000), 1000)
    }

    func testAbsurdSqrtEraStarCountsCollapseToLogScale() {
        // 1.43e9 stars (a real save) -> ~183, matching what the log prestige
        // formula would have granted for the same lifetime run.
        XCTAssertEqual(EconomyEngine.normalizedStars(1_434_965_406), 183)
        XCTAssertGreaterThanOrEqual(EconomyEngine.normalizedStars(1_001), 60)
    }

    func testNormalizedRepairsStarsOnLoad() {
        var s = GameState.newGame()
        s.stars = 1_434_965_406
        XCTAssertEqual(s.normalized().stars, 183)
    }
}
