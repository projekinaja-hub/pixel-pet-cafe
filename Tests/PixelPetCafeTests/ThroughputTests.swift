import XCTest
@testable import PixelPetCafe

final class ThroughputTests: XCTestCase {

    // MARK: prep time

    func testPrepTimeBaseValuesOrderQuickToSlow() {
        var s = GameState.newGame()
        s.lifetimeCoins = 10_000_000
        s = s.normalized()
        SalesEngine.unlockNewMenuItems(&s)
        let items = SalesEngine.allItems(s)
        func t(_ id: String) -> Double { SalesEngine.prepTime(items.first { $0.id == id }!, s) }
        XCTAssertEqual(t("espresso_shot"), 5, accuracy: 1e-9)
        XCTAssertEqual(t("latte"), 12, accuracy: 1e-9)
        XCTAssertEqual(t("matcha_latte"), 13, accuracy: 1e-9)
        XCTAssertEqual(t("hot_cocoa"), 14, accuracy: 1e-9)
        XCTAssertEqual(t("croissant"), 20, accuracy: 1e-9)
        XCTAssertEqual(t("berry_tart"), 26, accuracy: 1e-9)
        XCTAssertEqual(t("honey_cake"), 32, accuracy: 1e-9)
        // espresso quick, drinks next, pastries slower, honey cake slowest
        XCTAssertLessThan(t("espresso_shot"), t("latte"))
        XCTAssertLessThan(t("latte"), t("croissant"))
        XCTAssertLessThan(t("croissant"), t("honey_cake"))
    }

    func testPrepTimeSpeedsUpWithRelevantEquipmentAndFloors() {
        var s = GameState.newGame()
        let espresso = SalesEngine.allItems(s).first { $0.id == "espresso_shot" }!
        XCTAssertEqual(SalesEngine.prepTime(espresso, s), 5, accuracy: 1e-9)

        s.equipmentLevels["espresso"] = 10
        let faster = SalesEngine.prepTime(espresso, s)
        XCTAssertLessThan(faster, 5)
        XCTAssertEqual(faster, max(1.5, 5 / pow(1.06, 10)), accuracy: 1e-9)

        s.equipmentLevels["espresso"] = 200   // extreme — must never hit ~0s
        XCTAssertEqual(SalesEngine.prepTime(espresso, s), 1.5, accuracy: 1e-9)

        // decor/sound have no speed role at all
        var s2 = GameState.newGame()
        s2.equipmentLevels["decor"] = 30
        s2.equipmentLevels["sound"] = 30
        XCTAssertEqual(SalesEngine.prepTime(espresso, s2), 5, accuracy: 1e-9)

        // oven speeds up pastries, not drinks
        var s3 = GameState.newGame()
        s3.equipmentLevels["oven"] = 10
        XCTAssertEqual(SalesEngine.prepTime(espresso, s3), 5, accuracy: 1e-9)
    }

    // MARK: capacity

    func testFreshCafeCapacityComfortablyExceedsBaselineDemand() {
        let s = GameState.newGame()
        XCTAssertGreaterThan(SalesEngine.capacityPerSec(s), SalesEngine.customerRate(s))
    }

    func testCapacityIsHigherForAFasterDrinkOnlyMenuThanASlowerPastryOnlyMenu() {
        let drinkOnly = GameState.newGame()   // starter menu: espresso only, 5s
        var pastryOnly = GameState.newGame()
        pastryOnly.lifetimeCoins = 2_000_000
        pastryOnly = pastryOnly.normalized()
        SalesEngine.unlockNewMenuItems(&pastryOnly)
        pastryOnly.menuEnabled = ["croissant"]   // 20s
        XCTAssertGreaterThan(SalesEngine.capacityPerSec(drinkOnly), SalesEngine.capacityPerSec(pastryOnly))
    }

    func testNoServableStockDisablesTheCapCompletely() {
        var s = GameState.newGame()
        s.stock = [:]
        XCTAssertTrue(SalesEngine.avgPrepTime(s).isInfinite)
        XCTAssertTrue(SalesEngine.capacityPerSec(s).isInfinite)
    }

    // MARK: the critical floor — protects every micro-tick test in the suite

    func testMicroTickFloorGuaranteesTheLoneArrivalIsServedNotCapacityBlocked() {
        let fresh = GameState.newGame()
        for seed: UInt64 in 0..<20 {
            var copy = fresh
            copy.customerProgress = 1
            var rng = SeededGenerator(seed: seed)
            let events = SalesEngine.tick(&copy, dt: 0.001, rng: &rng)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events[0].mood, .happy,
                            "capacity floor must guarantee the lone arrival isn't capacity-blocked (seed \(seed))")
        }
    }

    // MARK: capacity actually binds under a burst

    func testHighBurstArrivalsHitCapacityAndTurnCustomersAwayDistinctFromStockOut() {
        var s = GameState.newGame()
        s.stock = ["beans": 100_000]   // plenty of stock — never a stock-out
        s.customerProgress = 20        // way more than one tick's serve slots
        var rng = SeededGenerator(seed: 4)
        let events = SalesEngine.tick(&s, dt: 0.001, rng: &rng)
        XCTAssertEqual(events.count, 20)
        let capacityBlocked = events.filter { $0.mood == .sadLeave && $0.itemName.isEmpty }
        XCTAssertEqual(capacityBlocked.count, 19, "only one serve-slot should clear at this dt; the rest are capacity-blocked")
    }

    func testCapacityBlockingNeverDingsReputationEvenAtExtremeMismatch() {
        // A chronically under-capacity café (huge equipment, tiny service staff)
        // can accumulate thousands of blocked "customers" worth of progress in
        // a single tick, every tick. Any nonzero per-tick reputation ding here —
        // no matter how small — eventually loses to this happening every tick
        // forever, permanently pinning reputation at 0 with no way to recover.
        // Capacity-blocking already costs real revenue (zero payout); it must
        // NOT also cost reputation.
        var s = GameState.newGame()
        s.stock = ["beans": 10_000_000]
        s.equipmentLevels = ["espresso": 60]   // massive customerRate boost, minimal capacity boost
        s.reputation = 100
        s.customerProgress = 5000              // far more than any single tick could ever serve
        var rng = SeededGenerator(seed: 7)
        let before = s.reputation
        _ = SalesEngine.tick(&s, dt: 0.001, rng: &rng)
        XCTAssertEqual(s.reputation, before, accuracy: 1e-9,
                       "capacity-blocking must never touch reputation, at any scale")
    }

    // MARK: offline sim capacity clamp

    func testOfflineSimClampsThroughputWhenDemandOutpacesCapacity() {
        var s = GameState.newGame()
        s.stock = ["beans": 10_000_000]   // never stock-limited
        s.stars = 200                     // pushes demand far past a lone barista's capacity
        s.reputation = 100
        s.cleanliness = 100
        let cap = SalesEngine.capacityPerSec(s)
        let window = EconomyEngine.offlineCap(s)
        let demand = SalesEngine.customerRate(s) * window
        XCTAssertGreaterThan(demand, cap * window, "test setup should actually stress capacity")
        let before = s.stock["beans"]!
        _ = SalesEngine.offlineSim(&s, elapsed: window)
        let consumed = Double(before - (s.stock["beans"] ?? 0))
        XCTAssertLessThanOrEqual(consumed, cap * window + 1)
    }

    // MARK: capacity fairness for heavy-equipment / typing-boost play styles

    func testHeavyEquipmentInvestmentAlsoLiftsCapacityNotJustPrepTime() {
        // A café that poured everything into gear rather than mocha/poppy/biscuit
        // shouldn't have throughput collapse to almost nothing — better tools
        // should meaningfully help the same hands move faster, too.
        var underStaffed = GameState.newGame()
        let before = SalesEngine.capacityPerSec(underStaffed)
        underStaffed.equipmentLevels = ["espresso": 46, "grinder": 16, "oven": 11, "decor": 13, "sound": 5]
        XCTAssertGreaterThan(SalesEngine.capacityPerSec(underStaffed), before,
                              "heavy equipment investment should raise capacity even with staff left at their starting levels")
    }

    func testWorkModeBoostSpeedsUpServiceThroughputNotJustArrivals() {
        var s = GameState.newGame()
        s.stock = ["beans": 100_000]
        s.customerProgress = 20
        var rng = SeededGenerator(seed: 4)
        var boosted = s
        let unboosted = SalesEngine.tick(&s, dt: 0.001, boost: 1, rng: &rng)
        var rng2 = SeededGenerator(seed: 4)
        let withBoost = SalesEngine.tick(&boosted, dt: 0.001, boost: 3, rng: &rng2)
        let unboostedServed = unboosted.filter { $0.mood != .sadLeave }.count
        let boostedServed = withBoost.filter { $0.mood != .sadLeave }.count
        XCTAssertGreaterThanOrEqual(boostedServed, unboostedServed,
                                     "typing-speed boost should let capacity keep up better, not just bring in more arrivals")
    }

    // MARK: Delivery

    func testDeliveryUnlockedAtTenOfTwelveCities() {
        var s = GameState.newGame()
        for _ in 0..<8 { s.cafes.append(CafeState.fresh(city: "sakura")) }
        XCTAssertEqual(s.cafes.count, 9)
        XCTAssertFalse(s.deliveryUnlocked)
        s.cafes.append(CafeState.fresh(city: "neon"))
        XCTAssertEqual(s.cafes.count, 10)
        XCTAssertTrue(s.deliveryUnlocked)
    }

    func testDeliveryFillRateIsMuchHigherWhenInvestedInServiceCapacityThanWhenNot() {
        func tenCafeState() -> GameState {
            var s = GameState.newGame()
            for _ in 0..<9 { s.cafes.append(CafeState.fresh(city: "sakura")) }
            s.activeCafe = 0
            s.stock = ["beans": 100_000_000]
            s.reputation = 100
            s.cleanliness = 100
            return s
        }
        // Under-invested: owns 10 cities and has pumped rate-only staff (Bo,
        // Earl — neither counts toward serviceWorkers/prepTime), so demand is
        // high but actual serving capacity is still just the baseline barista.
        var underInvested = tenCafeState()
        underInvested.staffLevels["bo"] = 100
        underInvested.staffLevels["earl"] = 100
        XCTAssertTrue(underInvested.deliveryUnlocked)

        // Over-invested: same idea, but the investment went into fast,
        // high-level baristas/service staff + prep-speed equipment instead.
        var overInvested = tenCafeState()
        overInvested.staffLevels["mocha"] = 100
        overInvested.staffLevels["poppy"] = 100
        overInvested.staffLevels["biscuit"] = 100
        overInvested.equipmentLevels["espresso"] = 20

        var rngA = SeededGenerator(seed: 1)
        var rngB = SeededGenerator(seed: 1)
        _ = SalesEngine.tick(&underInvested, dt: 1, rng: &rngA)
        _ = SalesEngine.tick(&overInvested, dt: 1, rng: &rngB)

        let underTotal = underInvested.cafe.deliveryOrdersServed + underInvested.cafe.deliveryOrdersMissed
        let overTotal = overInvested.cafe.deliveryOrdersServed + overInvested.cafe.deliveryOrdersMissed
        XCTAssertGreaterThan(underTotal, 0)
        XCTAssertGreaterThan(overTotal, 0)
        let underFillRate = underInvested.cafe.deliveryOrdersServed / underTotal
        let overFillRate = overInvested.cafe.deliveryOrdersServed / overTotal

        XCTAssertLessThan(underFillRate, 0.01, "rate-only investment (no service capacity) should miss almost all delivery demand")
        XCTAssertGreaterThan(overFillRate, underFillRate * 10,
                              "investing in service staff/speed equipment should dramatically raise the fill rate")
    }

    // MARK: persistence

    func testCafeStateDecodesNewThroughputFieldsWithDefaultsWhenMissing() throws {
        let json = """
        {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        """
        let cafe = try JSONDecoder().decode(CafeState.self, from: Data(json.utf8))
        XCTAssertEqual(cafe.serviceBuffer, 0)
        XCTAssertEqual(cafe.deliveryOrdersServed, 0)
        XCTAssertEqual(cafe.deliveryOrdersMissed, 0)
        // round-trips cleanly in the new shape
        var mutated = cafe
        mutated.serviceBuffer = 0.7
        mutated.deliveryOrdersServed = 42
        mutated.deliveryOrdersMissed = 7
        let data = try JSONEncoder().encode(mutated)
        let again = try JSONDecoder().decode(CafeState.self, from: data)
        XCTAssertEqual(again.serviceBuffer, 0.7, accuracy: 1e-9)
        XCTAssertEqual(again.deliveryOrdersServed, 42, accuracy: 1e-9)
        XCTAssertEqual(again.deliveryOrdersMissed, 7, accuracy: 1e-9)
    }
}
