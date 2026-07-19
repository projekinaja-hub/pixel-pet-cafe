import XCTest
@testable import PixelPetCafe

final class SalesTests: XCTestCase {

    // MARK: setup helpers

    func richState() -> GameState {
        var s = GameState.newGame()
        s.coins = 10_000
        s.stock = ["beans": 100, "milk": 100, "flour": 100, "sugar": 100]
        return s
    }

    // MARK: servable & stock gating

    func testServableRequiresStock() {
        var s = GameState.newGame()   // starter stock, espresso enabled
        XCTAssertTrue(SalesEngine.servable(s).contains { $0.id == "espresso_shot" })
        s.stock["beans"] = 0
        XCTAssertFalse(SalesEngine.servable(s).contains { $0.id == "espresso_shot" })
    }

    func testTickServesAndConsumesIngredients() {
        var s = richState()
        s.customerProgress = 0.999
        var rng = SeededGenerator(seed: 7)
        let beansBefore = s.stock["beans"]!
        let coinsBefore = s.coins
        // dt large enough to guarantee at least one customer
        let events = SalesEngine.tick(&s, dt: 60, rng: &rng)
        XCTAssertFalse(events.isEmpty)
        XCTAssertFalse(events.allSatisfy(\.angry))
        XCTAssertGreaterThan(s.coins, coinsBefore)
        XCTAssertLessThan(s.stock["beans"]! + s.stock["milk"]! + s.stock["flour"]!,
                          beansBefore + 200)  // something was consumed
        XCTAssertLessThan(s.cleanliness, 100)
        XCTAssertNotNil(s.lastSaleAt)
    }

    func testNoStockMeansAngryCustomersAndNoIncome() {
        var s = GameState.newGame()
        s.stock = [:]
        s.lastSaleAt = Date()   // unservable but within the open grace window
        s.customerProgress = 2.5
        var rng = SeededGenerator(seed: 1)
        let coinsBefore = s.coins
        let events = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy(\.angry))
        XCTAssertEqual(s.coins, coinsBefore)
    }

    func testPreferenceWeighting() {
        // species 0 prefers drinks: over many picks, drinks should dominate pastries
        var s = richState()
        s.lifetimeCoins = 10_000   // unlock latte + croissant
        s = s.normalized()
        SalesEngine.unlockNewMenuItems(&s)
        var rng = SeededGenerator(seed: 42)
        var drinks = 0, pastries = 0
        for _ in 0..<300 {
            var copy = s
            copy.customerProgress = 1
            let ev = SalesEngine.tick(&copy, dt: 0.001, rng: &rng)
            guard let e = ev.first, !e.angry else { continue }
            if e.customerSpecies == 0 {
                if e.itemIcon == "croissant" { pastries += 1 } else { drinks += 1 }
            }
        }
        XCTAssertGreaterThan(drinks, pastries)
    }

    // MARK: closed & dirt

    func testClosedWhenUnservableTooLong() {
        var s = GameState.newGame()
        s.stock = [:]
        s.lastSaleAt = Date(timeIntervalSinceNow: -400)
        XCTAssertTrue(SalesEngine.isClosed(s))
        s.lastSaleAt = Date(timeIntervalSinceNow: -30)
        XCTAssertFalse(SalesEngine.isClosed(s))
        s.stock = GameState.starterStock   // restock reopens instantly
        s.lastSaleAt = Date(timeIntervalSinceNow: -400)
        XCTAssertFalse(SalesEngine.isClosed(s))
    }

    func testDirtSpotsScaleWithFilth() {
        var s = GameState.newGame()
        s.cleanliness = 100
        XCTAssertEqual(SalesEngine.dirtSpots(s), 0)
        s.cleanliness = 55
        XCTAssertEqual(SalesEngine.dirtSpots(s), 2)
        s.cleanliness = 0
        XCTAssertEqual(SalesEngine.dirtSpots(s), 5)
    }

    func testCleaningActions() {
        var s = GameState.newGame()
        s.cleanliness = 40
        SalesEngine.cleanSpot(&s)
        XCTAssertEqual(s.cleanliness, 55)
        s.coins = 1_000_000
        XCTAssertTrue(SalesEngine.sweepAll(&s))
        XCTAssertEqual(s.cleanliness, 100)
    }

    // MARK: offline sim

    func testOfflineSimEarnsAndStopsWhenStockRunsOut() {
        var s = GameState.newGame()
        s.stock = ["beans": 5]     // only 5 espressos possible
        let haul = SalesEngine.offlineSim(&s, elapsed: 8 * 3600)
        XCTAssertGreaterThan(haul, 0)
        XCTAssertEqual(s.stock["beans"], 0)
        let price = SalesEngine.price(SalesEngine.servable(GameState.newGame())[0], s)
        // net of staff wages (newGame starts with Mocha Lv 1 -> 0.5% share)
        XCTAssertEqual(haul, 5 * price * (1 - EconomyEngine.wageShare(s)), accuracy: 1e-6)
    }

    func testOfflineSimZeroWithNoStock() {
        var s = GameState.newGame()
        s.stock = [:]
        XCTAssertEqual(SalesEngine.offlineSim(&s, elapsed: 3600), 0)
        XCTAssertEqual(SalesEngine.offlineSim(&s, elapsed: -100), 0)
    }

    // MARK: purchases & custom items

    func testBuyPackAddsStock() {
        var s = GameState.newGame()
        s.coins = 1_000
        XCTAssertTrue(SalesEngine.buyPack("beans", units: 25, &s))
        XCTAssertEqual(s.stock["beans"], GameState.starterStock["beans"]! + 25)
        XCTAssertEqual(s.coins, 1_000 - MenuCatalog.packCost("beans", units: 25), accuracy: 1e-9)
        XCTAssertEqual(MenuCatalog.packCost("beans", units: 100), 2 * 100 * 0.9, accuracy: 1e-9)
    }

    func testCustomItemPricing() {
        let item = CustomMenuItem(id: "c1", name: "Berry Honey Latte", icon: "latte",
                                  category: .drink,
                                  ingredients: ["beans": 1, "berry": 1, "honey": 1])
        // (2 + 5 + 8) × 6 = 90
        XCTAssertEqual(MenuCatalog.customPrice(item), 90)
    }

    // MARK: migration

    func testV1SaveDecodesWithDefaults() throws {
        let v1 = """
        {"coins": 500, "lifetimeCoins": 2000, "lifetimeCoinsThisRun": 2000,
         "staffLevels": {"mocha": 3}, "equipmentLevels": {"espresso": 2},
         "unlockedRecipes": ["latte_art"], "stars": 1, "muted": true}
        """
        let s0 = try JSONDecoder().decode(GameState.self, from: Data(v1.utf8))
        let s = s0.normalized()
        XCTAssertEqual(s.coins, 500)
        XCTAssertEqual(s.staffLevels["mocha"], 3)
        XCTAssertTrue(s.muted)
        XCTAssertEqual(s.stock, GameState.starterStock)          // filled in
        XCTAssertTrue(s.menuEnabled.contains("espresso_shot"))   // unlocked by lifetime
        XCTAssertTrue(s.menuEnabled.contains("croissant"))       // 2000 ≥ 1500
        XCTAssertFalse(s.menuEnabled.contains("matcha_latte"))
        XCTAssertEqual(s.owner, OwnerConfig())
        XCTAssertEqual(s.cleanliness, 100)
    }
}
