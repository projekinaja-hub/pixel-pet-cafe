import XCTest
@testable import PixelPetCafe

final class EconomyTests: XCTestCase {

    // MARK: coins per second

    func testNewGameEarnsWithMochaOnly() {
        let s = GameState.newGame()
        let mocha = Catalog.staff.first { $0.id == "mocha" }!
        XCTAssertEqual(EconomyEngine.coinsPerSecond(s), mocha.baseRate, accuracy: 1e-9)
    }

    func testCPSCombinesStaffEquipmentRecipesStars() {
        var s = GameState.newGame()
        s.staffLevels = ["mocha": 2, "biscuit": 3]
        s.equipmentLevels = ["espresso": 2]
        s.unlockedRecipes = ["latte_art"]
        s.stars = 5
        let mocha = Catalog.staff.first { $0.id == "mocha" }!
        let biscuit = Catalog.staff.first { $0.id == "biscuit" }!
        let espresso = Catalog.equipment.first { $0.id == "espresso" }!
        let latte = Catalog.recipes.first { $0.id == "latte_art" }!
        let base = 2 * mocha.baseRate + 3 * biscuit.baseRate
        let expected = base * pow(espresso.multPerLevel, 2) * latte.multiplier * 1.5
        XCTAssertEqual(EconomyEngine.coinsPerSecond(s), expected, accuracy: 1e-9)
    }

    // MARK: cost curve

    func testCostCurveGeometric() {
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 0), 100, accuracy: 1e-9)
        XCTAssertEqual(EconomyEngine.cost(base: 100, level: 3), 100 * pow(1.15, 3), accuracy: 1e-9)
    }

    // MARK: buying

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
        XCTAssertEqual(s.staffLevels["biscuit", default: 0], 0)
    }

    // MARK: tick + recipes

    func testTickAddsEarningsAndLifetime() {
        var s = GameState.newGame()
        let rate = EconomyEngine.coinsPerSecond(s)
        EconomyEngine.tick(&s, dt: 10)
        XCTAssertEqual(s.coins, rate * 10, accuracy: 1e-9)
        XCTAssertEqual(s.lifetimeCoins, rate * 10, accuracy: 1e-9)
        XCTAssertEqual(s.lifetimeCoinsThisRun, rate * 10, accuracy: 1e-9)
    }

    func testRecipesUnlockAtMilestone() {
        var s = GameState.newGame()
        let first = Catalog.recipes.min { $0.unlockAtLifetime < $1.unlockAtLifetime }!
        s.lifetimeCoins = first.unlockAtLifetime - 1
        EconomyEngine.tick(&s, dt: 0)
        XCTAssertFalse(s.unlockedRecipes.contains(first.id))
        s.lifetimeCoins = first.unlockAtLifetime
        EconomyEngine.tick(&s, dt: 0)
        XCTAssertTrue(s.unlockedRecipes.contains(first.id))
    }

    // MARK: offline earnings

    func testOfflineEarningsNormal() {
        let s = GameState.newGame()
        let rate = EconomyEngine.coinsPerSecond(s)
        XCTAssertEqual(EconomyEngine.offlineEarnings(s, elapsed: 3600), rate * 3600, accuracy: 1e-6)
    }

    func testOfflineEarningsCappedAt8Hours() {
        let s = GameState.newGame()
        let rate = EconomyEngine.coinsPerSecond(s)
        XCTAssertEqual(EconomyEngine.offlineEarnings(s, elapsed: 100 * 3600), rate * 8 * 3600, accuracy: 1e-6)
    }

    func testEarlExtendsOfflineCap() {
        var s = GameState.newGame()
        s.staffLevels["earl"] = 3
        XCTAssertEqual(EconomyEngine.offlineCap(s), (8 + 3) * 3600, accuracy: 1e-9)
    }

    func testClockRollbackEarnsNothing() {
        let s = GameState.newGame()
        XCTAssertEqual(EconomyEngine.offlineEarnings(s, elapsed: -500), 0)
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

    func testRenovateResetsRunButKeepsStars() {
        var s = GameState.newGame()
        s.coins = 5_000_000
        s.lifetimeCoins = 9_000_000
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 4
        s.staffLevels = ["mocha": 10, "biscuit": 4]
        s.equipmentLevels = ["oven": 3]
        s.unlockedRecipes = ["latte_art"]
        s.muted = true
        XCTAssertTrue(EconomyEngine.canRenovate(s))
        EconomyEngine.renovate(&s)
        XCTAssertEqual(s.stars, 2)
        XCTAssertEqual(s.coins, 0)
        XCTAssertEqual(s.lifetimeCoinsThisRun, 0)
        XCTAssertEqual(s.lifetimeCoins, 9_000_000)   // lifetime total preserved
        XCTAssertEqual(s.staffLevels["mocha"], 1)    // starter back
        XCTAssertNil(s.staffLevels["biscuit"])
        XCTAssertTrue(s.equipmentLevels.isEmpty)
        XCTAssertTrue(s.unlockedRecipes.isEmpty)
        XCTAssertTrue(s.muted)                       // settings survive
    }

    // MARK: golden tip

    func testGoldenTipIsTenMinutesOfIncomeWithFloor() {
        var s = GameState.newGame()
        XCTAssertEqual(EconomyEngine.goldenTipValue(s), max(600 * EconomyEngine.coinsPerSecond(s), 25), accuracy: 1e-9)
        s.staffLevels = ["mocha": 100]
        XCTAssertEqual(EconomyEngine.goldenTipValue(s), 600 * EconomyEngine.coinsPerSecond(s), accuracy: 1e-6)
    }

    // MARK: formatting

    func testNumberFormatting() {
        XCTAssertEqual(formatNumber(0), "0")
        XCTAssertEqual(formatNumber(950), "950")
        XCTAssertEqual(formatNumber(1_234), "1.2K")
        XCTAssertEqual(formatNumber(56_780_000), "56.8M")
        XCTAssertEqual(formatNumber(3.2e9), "3.2B")
        XCTAssertEqual(formatNumber(7.5e12), "7.5T")
    }
}
