import XCTest
@testable import PixelPetCafe

final class EconomyTests: XCTestCase {

    // MARK: costs & buying

    func testCostCurveGeometric() {
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 0, growth: 1.18), 100, accuracy: 1e-9)
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 3, growth: 1.18), 100 * pow(1.18, 3), accuracy: 1e-9)
        var s = GameState.newGame()
        s.equipmentLevels["espresso"] = 4
        XCTAssertEqual(EconomyEngine.equipmentCost("espresso", s), 100 * pow(1.25, 4), accuracy: 1e-6)
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
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 9
        XCTAssertEqual(EconomyEngine.prestigeStars(s), 3)
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
        XCTAssertEqual(s.stars, 2)
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
