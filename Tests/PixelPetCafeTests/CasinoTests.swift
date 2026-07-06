import XCTest
@testable import PixelPetCafe

final class CasinoTests: XCTestCase {

    // MARK: slots

    func testSlotPayoutTable() {
        XCTAssertEqual(CasinoEngine.slotPayout(["star", "star", "star"]), 60)
        XCTAssertEqual(CasinoEngine.slotPayout(["honey", "honey", "honey"]), 25)
        XCTAssertEqual(CasinoEngine.slotPayout(["beans", "beans", "beans"]), 10)
        XCTAssertEqual(CasinoEngine.slotPayout(["beans", "beans", "berry"]), 1)
        XCTAssertEqual(CasinoEngine.slotPayout(["beans", "berry", "beans"]), 1)
        XCTAssertEqual(CasinoEngine.slotPayout(["matcha", "beans", "berry"]), 0)
    }

    func testSlotsHouseEdge() {
        // over many spins the return should be below 100% (and above 30%)
        var rng = SeededGenerator(seed: 99)
        var returned = 0.0
        let n = 20_000
        for _ in 0..<n {
            returned += CasinoEngine.slotPayout(CasinoEngine.slotSpin(rng: &rng))
        }
        let rtp = returned / Double(n)
        XCTAssertLessThan(rtp, 1.0)
        XCTAssertGreaterThan(rtp, 0.3)
    }

    // MARK: blackjack

    func testHandValuesWithAces() {
        func card(_ r: Int) -> CasinoEngine.Card { .init(rank: r, suit: 0) }
        XCTAssertEqual(CasinoEngine.handValue([card(1), card(13)]), 21)      // A + K
        XCTAssertTrue(CasinoEngine.isBlackjack([card(1), card(10)]))
        XCTAssertEqual(CasinoEngine.handValue([card(1), card(1), card(9)]), 21)   // A A 9
        XCTAssertEqual(CasinoEngine.handValue([card(10), card(9), card(5)]), 24)  // bust
        XCTAssertEqual(CasinoEngine.handValue([card(1), card(5)]), 16)       // soft 16
    }

    func testDealerStandsOnSeventeenAndOutcomes() {
        var rng = SeededGenerator(seed: 5)
        for _ in 0..<200 {
            var g = CasinoEngine.BlackjackGame(bet: 10, rng: &rng)
            if !g.finished { g.stand() }
            let d = CasinoEngine.handValue(g.dealer)
            if CasinoEngine.handValue(g.player) <= 21, !CasinoEngine.isBlackjack(g.player),
               !CasinoEngine.isBlackjack(g.dealer) {
                XCTAssertTrue(d >= 17, "dealer must reach 17+ (got \(d))")
            }
            XCTAssertNotNil(g.outcome)
            switch g.outcome! {
            case .playerBlackjack: XCTAssertEqual(g.payout, 25)
            case .win: XCTAssertEqual(g.payout, 20)
            case .push: XCTAssertEqual(g.payout, 10)
            case .lose: XCTAssertEqual(g.payout, 0)
            }
        }
    }

    func testDoubleDownDoublesBetAndDrawsOneCard() {
        var rng = SeededGenerator(seed: 12)
        var g = CasinoEngine.BlackjackGame(bet: 50, rng: &rng)
        guard !g.finished else { return }   // natural — skip this seed's round
        g.doubleDown()
        XCTAssertEqual(g.bet, 100)
        XCTAssertEqual(g.player.count, 3)
        XCTAssertTrue(g.finished)
    }

    // MARK: roulette

    func testRoulettePayouts() {
        XCTAssertEqual(CasinoEngine.roulettePayout(.straight(17), result: 17), 36)
        XCTAssertEqual(CasinoEngine.roulettePayout(.straight(17), result: 18), 0)
        XCTAssertEqual(CasinoEngine.roulettePayout(.straight(0), result: 0), 36)
        XCTAssertEqual(CasinoEngine.roulettePayout(.red, result: 1), 2)      // 1 is red
        XCTAssertEqual(CasinoEngine.roulettePayout(.black, result: 2), 2)    // 2 is black
        XCTAssertEqual(CasinoEngine.roulettePayout(.red, result: 0), 0)      // zero beats colors
        XCTAssertEqual(CasinoEngine.roulettePayout(.even, result: 0), 0)     // zero isn't even
        XCTAssertEqual(CasinoEngine.roulettePayout(.low, result: 0), 0)
        XCTAssertEqual(CasinoEngine.roulettePayout(.odd, result: 33), 2)
        XCTAssertEqual(CasinoEngine.roulettePayout(.dozen(0), result: 12), 3)
        XCTAssertEqual(CasinoEngine.roulettePayout(.dozen(2), result: 25), 3)
        XCTAssertEqual(CasinoEngine.roulettePayout(.dozen(2), result: 24), 0)
    }
}

final class V3Tests: XCTestCase {

    func testManagerAutoRestocks() {
        var s = GameState.newGame()
        s.coins = 10_000
        s.staffLevels["marble"] = 2      // target 20 per ingredient
        s.stock = ["beans": 0]
        SalesEngine.managerRestock(&s)
        XCTAssertGreaterThanOrEqual(s.stock["beans"] ?? 0, 20)
        XCTAssertGreaterThanOrEqual(s.stock["honey"] ?? 0, 20)
        XCTAssertLessThan(s.coins, 10_000)   // paid for it
    }

    func testManagerStopsWhenBroke() {
        var s = GameState.newGame()
        s.coins = 0
        s.staffLevels["marble"] = 3
        s.stock = ["beans": 0]
        SalesEngine.managerRestock(&s)
        XCTAssertEqual(s.stock["beans"], 0)
    }

    func testReputationCauseAndEffect() {
        var s = GameState.newGame()
        let base = SalesEngine.customerRate(s)
        s.reputation = 100
        XCTAssertGreaterThan(SalesEngine.customerRate(s), base)
        s.reputation = 0
        XCTAssertLessThan(SalesEngine.customerRate(s), base)
        // angry customer drops reputation
        s.stock = [:]
        s.customerProgress = 1
        var rng = SeededGenerator(seed: 3)
        _ = SalesEngine.tick(&s, dt: 0.01, rng: &rng)
        XCTAssertEqual(s.reputation, 0)      // was 0, floored
    }

    func testAdsDrainCoinsAndAutoStop() {
        var s = GameState.newGame()
        s.coins = 10_000
        s.adsActive = true
        var rng = SeededGenerator(seed: 8)
        let rateWithAds = SalesEngine.customerRate(s)
        s.adsActive = false
        XCTAssertEqual(rateWithAds, SalesEngine.customerRate(s) * 1.8, accuracy: 1e-9)
        s.adsActive = true
        s.coins = 0.000001                    // can't afford the campaign
        _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertFalse(s.adsActive)
    }

    func testBuyCityAndBonusesApply() {
        var s = GameState.newGame()
        s.cafes.append(CafeState.fresh(city: "neon"))
        s.activeCafe = 1
        s = s.normalized()               // fills the new café's menu
        let item = SalesEngine.servable(s)[0]
        s.activeCafe = 0
        let homePrice = SalesEngine.price(item, s)
        s.activeCafe = 1
        XCTAssertEqual(SalesEngine.price(item, s), homePrice * 1.5, accuracy: 1e-6)
    }

    func testRoleBonuses() {
        var s = GameState.newGame()
        s.stock = ["beans": 10]
        let espresso = SalesEngine.servable(s).first { $0.id == "espresso_shot" }!
        let base = SalesEngine.price(espresso, s)      // mocha lv1 already applies
        s.staffLevels["mocha"] = 11                    // +10 levels → ×(1.44/1.04)
        XCTAssertEqual(SalesEngine.price(espresso, s), base / 1.04 * 1.44, accuracy: 1e-6)
        XCTAssertEqual(SalesEngine.freeSaleChance(s), 0, accuracy: 1e-9)
        s.staffLevels["bo"] = 30
        XCTAssertEqual(SalesEngine.freeSaleChance(s), 0.5)   // capped
    }

    func testV2SaveMigratesIntoHomeCafe() throws {
        let v2 = """
        {"coins": 900, "lifetimeCoins": 2500, "lifetimeCoinsThisRun": 2500,
         "staffLevels": {"mocha": 4}, "equipmentLevels": {"oven": 1},
         "stock": {"beans": 7}, "menuEnabled": ["espresso_shot"],
         "cleanliness": 77, "stars": 2, "muted": false}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(v2.utf8)).normalized()
        XCTAssertEqual(s.cafes.count, 1)
        XCTAssertEqual(s.cafes[0].city, "home")
        XCTAssertEqual(s.staffLevels["mocha"], 4)
        XCTAssertEqual(s.stock["beans"], 7)
        XCTAssertEqual(s.cleanliness, 77)
        XCTAssertEqual(s.reputation, 50)
        // round-trips in the v3 shape
        let data = try JSONEncoder().encode(s)
        let again = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(again, s)
    }
}
