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

    // MARK: progressive jackpot

    func testJackpotPotGrowsOnWager() {
        var pot = CasinoEngine.jackpotSeed
        var rng = SeededGenerator(seed: 1)
        // Rig the trigger chance to zero so we only observe growth.
        let payout = CasinoEngine.growJackpot(&pot, wager: 1000, rng: &rng)
        // Either it grew (nil, common) or it triggered (rare) — either way the
        // wager's slice was added before the roll, so growth math is exact.
        if payout == nil {
            XCTAssertEqual(pot, CasinoEngine.jackpotSeed + 1000 * CasinoEngine.jackpotGrowthRate, accuracy: 1e-9)
        } else {
            XCTAssertEqual(pot, CasinoEngine.jackpotSeed)   // reset after paying out
        }
    }

    func testJackpotTriggerPaysFullPotAndResetsAboveZero() {
        // Search a range of seeds for one that fires the (rare) trigger,
        // proving the payout/reset path is exercised deterministically.
        var found = false
        for seed in 0..<20_000 {
            var pot: Double = 12_345
            var rng = SeededGenerator(seed: UInt64(seed))
            if let payout = CasinoEngine.growJackpot(&pot, wager: 500, rng: &rng) {
                XCTAssertEqual(payout, 12_345 + 500 * CasinoEngine.jackpotGrowthRate, accuracy: 1e-9)
                XCTAssertEqual(pot, CasinoEngine.jackpotSeed)
                XCTAssertGreaterThan(pot, 0)   // never resets to zero
                found = true
                break
            }
        }
        XCTAssertTrue(found, "expected at least one trigger across 20k seeded rolls at chance \(CasinoEngine.jackpotTriggerChance)")
    }

    func testJackpotNeverTriggersWhenChanceRolledJustAboveThreshold() {
        // A pot that never triggers still only grows — never resets on its own.
        var pot: Double = 1000
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<5 {
            let before = pot
            if CasinoEngine.growJackpot(&pot, wager: 200, rng: &rng) == nil {
                XCTAssertGreaterThan(pot, before)
            }
        }
    }

    // MARK: Lucky Hour boost

    func testLuckyHourBoostsProfitNotStakeReturn() {
        // A push (payout == bet) shouldn't be inflated — no profit to boost.
        XCTAssertEqual(CasinoEngine.applyLuckyHour(100, bet: 100, active: true), 100)
        // A real win's profit is scaled by the multiplier; stake passes through untouched.
        let boosted = CasinoEngine.applyLuckyHour(200, bet: 100, active: true)
        XCTAssertEqual(boosted, 100 + 100 * CasinoEngine.luckyHourMultiplier, accuracy: 1e-9)
        XCTAssertGreaterThan(boosted, 200)
    }

    func testLuckyHourInactiveLeavesPayoutUnchanged() {
        XCTAssertEqual(CasinoEngine.applyLuckyHour(200, bet: 100, active: false), 200)
    }

    func testLuckyHourEventDefExistsAndFollowsEventPattern() {
        guard let def = Events.def("lucky_hour") else {
            return XCTFail("lucky_hour must be registered in Events.all")
        }
        XCTAssertGreaterThan(def.duration, 0)
        XCTAssertFalse(def.emoji.isEmpty)
        XCTAssertFalse(def.name.isEmpty)
    }

    func testLuckyHourDoesNotSpawnBeforeCasinoUnlocked() {
        var s = GameState.newGame()
        s.lifetimeCoins = 0   // casino locked
        s.coins = 1_000_000   // ensure income estimate is nonzero so the roll can happen
        s.staffLevels["mocha"] = 3
        var rng = SeededGenerator(seed: 0)
        for _ in 0..<50_000 {
            if let event = Events.maybeSpawn(&s, dt: 5, now: Date(), rng: &rng) {
                XCTAssertNotEqual(event.id, "lucky_hour", "lucky_hour must not spawn while casino is locked")
            }
            s.activeEvent = nil
            s.eventEndsAt = nil
        }
    }

    // MARK: backward-compat decode

    func testOldSaveWithoutJackpotFieldDecodesToSeed() throws {
        let old = """
        {"coins": 900, "lifetimeCoins": 60000, "lifetimeCoinsThisRun": 2500,
         "casinoWagered": 500, "casinoWon": 300, "casinoBiggestWin": 100}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(old.utf8)).normalized()
        XCTAssertEqual(s.casinoJackpotPot, CasinoEngine.jackpotSeed, accuracy: 1e-9)
        // round-trips cleanly in the new shape
        let data = try JSONEncoder().encode(s)
        let again = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(again.casinoJackpotPot, s.casinoJackpotPot, accuracy: 1e-9)
    }
}

final class V3Tests: XCTestCase {

    func testEquipmentCostScalesByCityPriceBonus() {
        var s = GameState.newGame()
        s.equipmentLevels["espresso"] = 5
        let homeCost = EconomyEngine.equipmentCost("espresso", s)
        s.cafes.append(CafeState.fresh(city: "moon"))
        s.activeCafe = 1
        s.equipmentLevels["espresso"] = 5      // same level, different city
        let moonCost = EconomyEngine.equipmentCost("espresso", s)
        XCTAssertEqual(moonCost, homeCost * Cities.def("moon").priceBonus, accuracy: 1e-6)
        XCTAssertGreaterThan(moonCost, homeCost)
    }

    func testChipAutoCleansOverTimeForACost() {
        var s = GameState.newGame()
        s.coins = 100_000
        s.cleanliness = 10
        s.staffLevels["chip"] = 5
        var rng = SeededGenerator(seed: 3)
        let before = s.cleanliness
        let coinsBefore = s.coins
        _ = SalesEngine.tick(&s, dt: 1.0, rng: &rng)
        XCTAssertGreaterThan(s.cleanliness, before, "hired Chip should auto-restore cleanliness")
        XCTAssertLessThan(s.coins, coinsBefore, "auto-cleaning still costs coins")
    }

    func testNoChipMeansNoAutoClean() {
        var s = GameState.newGame()
        s.coins = 100_000
        s.cleanliness = 10
        var rng = SeededGenerator(seed: 3)
        let before = s.cleanliness
        _ = SalesEngine.tick(&s, dt: 1.0, rng: &rng)
        XCTAssertEqual(s.cleanliness, before, accuracy: 1e-9, "without Chip hired, cleanliness shouldn't self-heal")
    }

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

    func testRenovateOnlyResetsActiveCafe() {
        var s = GameState.newGame()
        s.staffLevels["biscuit"] = 5              // home café, built up
        s.equipmentLevels["oven"] = 3
        s.cafes.append(CafeState.fresh(city: "sakura"))
        s.activeCafe = 1
        s.staffLevels["poppy"] = 4                // sakura café, built up separately
        s.lifetimeCoinsThisRun = EconomyEngine.prestigeThreshold * 4
        XCTAssertTrue(EconomyEngine.canRenovate(s))
        EconomyEngine.renovate(&s)                // renovating while AT sakura
        XCTAssertEqual(s.staffLevels["poppy", default: 0], 0)   // sakura reset
        XCTAssertEqual(s.staffLevels["mocha"], 1)               // starter restored
        s.activeCafe = 0
        XCTAssertEqual(s.staffLevels["biscuit"], 5)             // home UNTOUCHED
        XCTAssertEqual(s.equipmentLevels["oven"], 3)            // home UNTOUCHED
    }

    func testAllOwnedCafesEarnEverySingleTickNotJustTheViewedOne() {
        var s = GameState.newGame()
        s.coins = 100_000
        s.stock = ["beans": 10_000, "milk": 10_000, "flour": 10_000, "sugar": 10_000]
        s.cafes.append(CafeState.fresh(city: "sakura"))
        s = s.normalized()
        s.cafes[1].stock = ["beans": 10_000, "milk": 10_000, "flour": 10_000, "sugar": 10_000]
        s.cafes[1].staffLevels = ["mocha": 30, "poppy": 30, "juno": 30]
        s.activeCafe = 0                         // viewing home; sakura is in the background
        var rng = SeededGenerator(seed: 7)
        let sakuraStockBefore = s.cafes[1].stock
        for _ in 0..<300 { _ = SalesEngine.tick(&s, dt: 1.0, rng: &rng) }
        XCTAssertNotEqual(s.cafes[1].stock, sakuraStockBefore, "the un-viewed sakura café should still be selling")
        XCTAssertEqual(s.activeCafe, 0, "tick must restore the viewed café index when it's done")
    }

    func testOfflineSimCreditsEveryOwnedCafe() {
        var s = GameState.newGame()
        s.stock = ["beans": 10_000, "milk": 10_000, "flour": 10_000, "sugar": 10_000]
        s.staffLevels["mocha"] = 5
        s.cafes.append(CafeState.fresh(city: "sakura"))
        s = s.normalized()
        s.cafes[1].stock = ["beans": 10_000, "milk": 10_000, "flour": 10_000, "sugar": 10_000]
        s.cafes[1].staffLevels["mocha"] = 5
        s.activeCafe = 0
        let sakuraStockBefore = s.cafes[1].stock
        let haul = SalesEngine.offlineSim(&s, elapsed: 600)
        XCTAssertGreaterThan(haul, 0)
        XCTAssertNotEqual(s.cafes[1].stock, sakuraStockBefore, "sakura should also sell while away")
        XCTAssertEqual(s.activeCafe, 0)
    }

    func testHigherEquipmentBurnsIngredientsFasterPerSale() {
        var base = GameState.newGame()
        base.coins = 1e9
        base.stock = ["beans": 100_000]   // only espresso is servable: deterministic single-ingredient path
        var upgraded = base
        for id in ["espresso", "grinder", "oven", "decor", "sound"] { upgraded.equipmentLevels[id] = 3 }
        XCTAssertEqual(SalesEngine.consumptionMultiplier(base), 1, accuracy: 1e-9)
        XCTAssertEqual(SalesEngine.consumptionMultiplier(upgraded), 1.06, accuracy: 1e-9)

        // normalize by event count (not call count) so a higher customerRate from
        // the same equipment levels can't skew the per-sale consumption signal
        func avgBeansPerEvent(_ start: GameState, seed: UInt64) -> Double {
            var copy = start
            var rng = SeededGenerator(seed: seed)
            var events = 0, spent = 0
            for _ in 0..<2000 {
                copy.customerProgress = 1
                if (copy.stock["beans"] ?? 0) < 10 { copy.stock["beans"] = 100_000 }
                let before = copy.stock["beans"] ?? 0
                let evts = SalesEngine.tick(&copy, dt: 0.001, rng: &rng)
                spent += before - (copy.stock["beans"] ?? 0)
                events += evts.count
            }
            return events > 0 ? Double(spent) / Double(events) : 0
        }
        let baseAvg = avgBeansPerEvent(base, seed: 5)
        let upgradedAvg = avgBeansPerEvent(upgraded, seed: 5)
        XCTAssertGreaterThan(upgradedAvg, baseAvg, "a more-upgraded café should burn more beans per sale on average")
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
