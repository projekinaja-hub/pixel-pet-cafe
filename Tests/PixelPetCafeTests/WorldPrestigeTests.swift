import XCTest
@testable import PixelPetCafe

/// "Move to a New Country" — the big, whole-game prestige built on top of
/// (and much rarer than) EconomyEngine.renovate(), which only resets the
/// active café. See EconomyEngine.moveToNewCountry.
final class WorldPrestigeTests: XCTestCase {

    /// Builds a state that clears both gates: lifetime coin threshold and
    /// owning enough cities.
    private func eligibleState() -> GameState {
        var s = GameState.newGame()
        for city in ["sakura", "neon", "seaside", "forest", "desert"] {
            s.cafes.append(CafeState.fresh(city: city))
        }
        s = s.normalized()
        s.lifetimeCoins = EconomyEngine.worldPrestigeCoinThreshold * 2
        s.lifetimeCoinsThisRun = 500_000
        return s
    }

    // MARK: gating

    func testCannotMoveWithoutEnoughLifetimeCoins() {
        var s = GameState.newGame()
        for city in ["sakura", "neon", "seaside", "forest", "desert"] {
            s.cafes.append(CafeState.fresh(city: city))
        }
        s = s.normalized()
        s.lifetimeCoins = 1_000 // far below threshold
        XCTAssertFalse(EconomyEngine.canMoveToNewCountry(s))
        let before = s
        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s, before, "a below-threshold call must be a no-op")
    }

    func testCannotMoveWithoutEnoughCities() {
        var s = GameState.newGame() // only Home
        s.lifetimeCoins = EconomyEngine.worldPrestigeCoinThreshold * 2
        XCTAssertFalse(EconomyEngine.canMoveToNewCountry(s))
        let before = s
        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s, before)
    }

    func testCanMoveWhenBothGatesClear() {
        let s = eligibleState()
        XCTAssertTrue(EconomyEngine.canMoveToNewCountry(s))
    }

    // MARK: the reset itself

    func testResetGoesBackToJustFreshHomeCafe() {
        var s = eligibleState()
        s.cafes[0].staffLevels["biscuit"] = 12
        s.cafes[0].equipmentLevels["oven"] = 8
        s.cafes[0].tables = 6
        s.stars = 7
        s.reputation = 12
        s.marketPrices["beans"] = 999
        s.menuTaste["latte"] = 9
        s.tasteKnown = ["sakura"]
        s.activeEvent = "rush"
        s.eventEndsAt = Date().addingTimeInterval(60)
        s.customItems = [CustomMenuItem(id: "custom1", name: "Test Brew", icon: "☕️", category: .drink, ingredients: ["beans": 1])]

        EconomyEngine.moveToNewCountry(&s)

        XCTAssertEqual(s.cafes.count, 1)
        XCTAssertEqual(s.cafes[0].city, "home")
        XCTAssertEqual(s.activeCafe, 0)
        XCTAssertEqual(s.staffLevels["mocha"], 1)          // fresh starter staff
        XCTAssertEqual(s.staffLevels["biscuit", default: 0], 0)
        XCTAssertEqual(s.equipmentLevels["oven", default: 0], 0)
        XCTAssertEqual(s.tables, 2)
        XCTAssertEqual(s.stars, 0)
        XCTAssertEqual(s.reputation, 50)
        XCTAssertEqual(s.marketPrices["beans"], MenuCatalog.ingredients.first { $0.id == "beans" }?.unitCost)
        XCTAssertEqual(s.menuTaste["latte", default: 0], 0)
        XCTAssertTrue(s.tasteKnown.isEmpty)
        XCTAssertNil(s.activeEvent)
        XCTAssertNil(s.eventEndsAt)
        XCTAssertTrue(s.customItems.isEmpty)
    }

    // MARK: 10% jumpstart

    func testJumpstartIsTenPercentOfLifetimeCoinsThisRun() {
        var s = eligibleState()
        s.lifetimeCoinsThisRun = 800_000
        s.coins = 12_345 // current wallet must NOT be the basis
        let expectedJumpstart = 80_000.0
        XCTAssertEqual(EconomyEngine.worldJumpstartCoins(s), expectedJumpstart)

        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s.coins, expectedJumpstart)
        XCTAssertEqual(s.lifetimeCoinsThisRun, 0, "this run's counter restarts at 0 for the new run")
    }

    func testJumpstartIgnoresCurrentWalletBalance() {
        var sHoarded = eligibleState()
        sHoarded.lifetimeCoinsThisRun = 500_000
        sHoarded.coins = 500_000 // never spent anything

        var sSpent = eligibleState()
        sSpent.lifetimeCoinsThisRun = 500_000
        sSpent.coins = 0 // spent it all on upgrades before resetting

        EconomyEngine.moveToNewCountry(&sHoarded)
        EconomyEngine.moveToNewCountry(&sSpent)

        XCTAssertEqual(sHoarded.coins, sSpent.coins, "jumpstart must not depend on unspent wallet balance")
    }

    // MARK: permanent bonus

    func testWorldsVisitedIncrementsAndStacksAcrossResets() {
        var s = eligibleState()
        XCTAssertEqual(s.worldsVisited, 0)
        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s.worldsVisited, 1)

        // Re-qualify for a second move.
        for city in ["sakura", "neon", "seaside", "forest", "desert"] {
            s.cafes.append(CafeState.fresh(city: city))
        }
        s.lifetimeCoins = EconomyEngine.worldPrestigeCoinThreshold * 4
        s.lifetimeCoinsThisRun = 500_000
        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s.worldsVisited, 2, "worldsVisited must not itself be reset by a world move")
    }

    func testPermanentBonusAppliesToPriceMultiplierAndStacks() {
        var base = GameState.newGame()
        base.worldsVisited = 0
        var withOneWorld = base
        withOneWorld.worldsVisited = 1
        var withTwoWorlds = base
        withTwoWorlds.worldsVisited = 2

        let m0 = SalesEngine.priceMultiplier(base)
        let m1 = SalesEngine.priceMultiplier(withOneWorld)
        let m2 = SalesEngine.priceMultiplier(withTwoWorlds)

        XCTAssertEqual(m1, m0 * (1 + EconomyEngine.worldPermanentBonusPerVisit), accuracy: 0.0001)
        XCTAssertEqual(m2, m0 * (1 + EconomyEngine.worldPermanentBonusPerVisit * 2), accuracy: 0.0001)
    }

    // MARK: survivors

    func testAchievementsSettingsAndCasinoStatsSurviveAWorldMove() {
        var s = eligibleState()
        s.achievements = ["stars_10", "first_sale"]
        s.owner.species = "fox"
        s.barCharacter = "mocha"
        s.muted = true
        s.workMode = true
        s.casinoJackpotPot = 4_242
        s.casinoWagered = 1_000
        s.casinoWon = 250
        s.casinoBiggestWin = 99

        EconomyEngine.moveToNewCountry(&s)

        XCTAssertEqual(s.achievements, ["stars_10", "first_sale"])
        XCTAssertEqual(s.owner.species, "fox")
        XCTAssertEqual(s.barCharacter, "mocha")
        XCTAssertTrue(s.muted)
        XCTAssertTrue(s.workMode)
        XCTAssertEqual(s.casinoJackpotPot, 4_242)
        XCTAssertEqual(s.casinoWagered, 1_000)
        XCTAssertEqual(s.casinoWon, 250)
        XCTAssertEqual(s.casinoBiggestWin, 99)
    }

    func testLifetimeCoinsSurvivesAWorldMove() {
        var s = eligibleState()
        let lifetime = s.lifetimeCoins
        EconomyEngine.moveToNewCountry(&s)
        XCTAssertEqual(s.lifetimeCoins, lifetime, "the all-time total (which gates this very threshold) must persist")
    }

    // MARK: backward-compat decode

    func testOldSaveMissingWorldsVisitedDecodesToZero() throws {
        var s = GameState.newGame()
        s.worldsVisited = 3 // will be stripped out below to simulate an old save
        let encoder = JSONEncoder()
        var data = try encoder.encode(s)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "worldsVisited")
        data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.worldsVisited, 0, "an old save missing the field must default to 0, not crash")
    }
}
