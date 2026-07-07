import XCTest
@testable import PixelPetCafe

final class SatisfactionTests: XCTestCase {

    /// A café with two menu items where one has no stock.
    func splitState() -> GameState {
        var s = GameState.newGame()
        s.lifetimeCoins = 1_000
        s.coins = 1_000
        s = s.normalized()
        SalesEngine.unlockNewMenuItems(&s)     // espresso + latte
        s.stock = ["beans": 100]               // no milk: latte unservable
        return s
    }

    func testDesiredItemOutOfStockCausesSettleOrSadLeave() {
        var settled = 0, sad = 0, happy = 0
        var rng = SeededGenerator(seed: 21)
        for _ in 0..<400 {
            var s = splitState()
            s.customerProgress = 1
            let events = SalesEngine.tick(&s, dt: 0.001, rng: &rng)
            guard let e = events.first else { continue }
            switch e.mood {
            case .settled: settled += 1
            case .sadLeave: sad += 1; XCTAssertEqual(e.price, 0)
            case .happy: happy += 1
            case .angry: XCTFail("espresso was servable — no one should be angry")
            case .noTable: break   // seating gate is a separate mechanic from stock
            }
        }
        XCTAssertGreaterThan(settled, 0, "some latte-lovers should settle for espresso")
        XCTAssertGreaterThan(sad, 0, "some latte-lovers should walk out")
        XCTAssertGreaterThan(happy, settled + sad, "espresso fans should be served happily")
    }

    func testSadLeaveHurtsReputationMoreThanSettling() {
        var s = splitState()
        s.reputation = 50
        var rng = SeededGenerator(seed: 3)
        var sawSettle = false, sawSad = false
        for _ in 0..<300 {
            var copy = s
            copy.customerProgress = 1
            let before = copy.reputation
            let e = SalesEngine.tick(&copy, dt: 0.001, rng: &rng).first
            switch e?.mood {
            case .settled:
                XCTAssertLessThan(copy.reputation, before)
                sawSettle = true
            case .sadLeave:
                XCTAssertEqual(copy.reputation, before - 1, accuracy: 1e-9)
                sawSad = true
            default: break
            }
            if sawSettle && sawSad { break }
        }
        XCTAssertTrue(sawSettle && sawSad)
    }

    // MARK: taste upgrades

    func testTasteUpgradeRaisesPriceAndCosts() {
        var s = GameState.newGame()
        s.coins = 1e9
        let item = SalesEngine.allItems(s).first { $0.id == "espresso_shot" }!
        let before = SalesEngine.price(item, s)
        let cost0 = SalesEngine.tasteUpgradeCost(item, s)
        XCTAssertTrue(SalesEngine.upgradeTaste("espresso_shot", &s))
        XCTAssertEqual(s.menuTaste["espresso_shot"], 1)
        XCTAssertEqual(SalesEngine.price(item, s), before * 1.06, accuracy: 1e-9)
        XCTAssertGreaterThan(SalesEngine.tasteUpgradeCost(item, s), cost0)   // next level dearer
        for _ in 0..<20 { SalesEngine.upgradeTaste("espresso_shot", &s) }
        XCTAssertEqual(s.menuTaste["espresso_shot"], SalesEngine.maxTaste)   // capped
    }

    func testTasteRaisesDesire() {
        var s = GameState.newGame()
        let item = SalesEngine.allItems(s).first { $0.id == "espresso_shot" }!
        let base = SalesEngine.desireWeight(item, species: 1, s)
        s.menuTaste["espresso_shot"] = 5
        XCTAssertEqual(SalesEngine.desireWeight(item, species: 1, s), base * 1.5, accuracy: 1e-9)
    }

    // MARK: city taste + research

    func testCityTasteAffectsDesire() {
        var s = GameState.newGame()
        s.cafes[0].city = "desert"      // drinks ×1.7
        let espresso = SalesEngine.allItems(s).first { $0.id == "espresso_shot" }!
        var home = s; home.cafes[0].city = "home"
        XCTAssertEqual(SalesEngine.desireWeight(espresso, species: 1, s),
                       SalesEngine.desireWeight(espresso, species: 1, home) * 1.7, accuracy: 1e-9)
    }

    func testResearchTasteSpendsOncePerCity() {
        var s = GameState.newGame()
        s.coins = 1e9
        XCTAssertTrue(SalesEngine.researchTaste(&s))
        XCTAssertTrue(s.tasteKnown.contains("home"))
        XCTAssertFalse(SalesEngine.researchTaste(&s))    // already known
    }

    // MARK: events

    func testEventEffects() {
        var s = GameState.newGame()
        let base = SalesEngine.customerRate(s)
        s.activeEvent = "rush"
        s.eventEndsAt = Date().addingTimeInterval(60)
        XCTAssertEqual(SalesEngine.customerRate(s), base * 2, accuracy: 1e-9)
        s.activeEvent = "rain"
        XCTAssertEqual(SalesEngine.customerRate(s), base * 0.7, accuracy: 1e-9)
        let espresso = SalesEngine.allItems(s).first { $0.id == "espresso_shot" }!
        var calm = s; calm.activeEvent = nil; calm.eventEndsAt = nil
        XCTAssertEqual(SalesEngine.price(espresso, s),
                       SalesEngine.price(espresso, calm) * 1.3, accuracy: 1e-9)  // rain drink boost
        s.activeEvent = "supplier"
        XCTAssertEqual(SalesEngine.packPrice("beans", units: 25, s),
                       MenuCatalog.packCost("beans", units: 25) * 0.5, accuracy: 1e-9)
    }

    func testEventExpires() {
        var s = GameState.newGame()
        s.activeEvent = "rush"
        s.eventEndsAt = Date(timeIntervalSinceNow: -5)
        var rng = SeededGenerator(seed: 1)
        _ = Events.maybeSpawn(&s, dt: 1, now: Date(), rng: &rng)
        XCTAssertFalse(Events.isActive("rush", s))
    }

    func testCriticVerdict() {
        var s = GameState.newGame()
        s.cleanliness = 90
        for id in s.menuEnabled { s.menuTaste[id] = 3 }
        s.reputation = 50
        // force a critic by spawning until one hits (deterministic seed scan)
        var found = false
        for seed in 0..<4000 where !found {
            var copy = s
            var rng = SeededGenerator(seed: UInt64(seed))
            if let e = Events.maybeSpawn(&copy, dt: 60, now: Date(), rng: &rng), e.id == "critic" {
                XCTAssertEqual(copy.reputation, 58)
                XCTAssertEqual(copy.lastCriticVerdict, true)
                found = true
            }
        }
        XCTAssertTrue(found, "no critic event in seed scan")
    }

    // MARK: achievements

    func testAchievementsUnlockOnce() {
        var s = GameState.newGame()
        s.salesCount = ["espresso_shot": 150]
        s.lifetimeCoins = 2e6
        let first = Achievements.checkAll(&s)
        XCTAssertTrue(first.contains { $0.id == "first_100" })
        XCTAssertTrue(first.contains { $0.id == "coins_1m" })
        XCTAssertTrue(Achievements.checkAll(&s).isEmpty)     // no double unlocks
        XCTAssertTrue(s.achievements.contains("first_100"))
    }
}
