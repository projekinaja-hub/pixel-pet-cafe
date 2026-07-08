import XCTest
@testable import PixelPetCafe

final class CalendarTests: XCTestCase {

    // MARK: calendar / season cycling

    func testSeasonStartsSpringAtDayZero() {
        XCTAssertEqual(GameCalendar.season(forDay: 0), .spring)
    }

    func testSeasonCyclesThroughAllFourOverElapsedTime() {
        var s = GameState.newGame()
        let start = Date()
        s.calendarStartedAt = start
        var seenSeasons: [Season] = []
        // Sample once per season length so we sweep spring -> summer -> autumn
        // -> winter -> back to spring across roughly one full year.
        let seasonLength = GameCalendar.dayLength * Double(GameCalendar.daysPerSeason)
        for i in 0..<5 {
            let now = start.addingTimeInterval(seasonLength * Double(i) + 1)
            GameCalendar.advance(&s, now: now)
            seenSeasons.append(s.season)
        }
        XCTAssertEqual(seenSeasons, [.spring, .summer, .autumn, .winter, .spring])
    }

    func testSeasonSurvivesAnOfflineGap() {
        // Mirrors offlineSim's own pattern: construct a state with an old
        // anchor, advance as if returning after days away, verify the season
        // reflects real elapsed time rather than staying stuck at spring.
        var s = GameState.newGame()
        let seasonLength = GameCalendar.dayLength * Double(GameCalendar.daysPerSeason)
        s.calendarStartedAt = Date().addingTimeInterval(-(seasonLength * 2.5))  // ~2.5 seasons ago
        _ = SalesEngine.offlineSim(&s, elapsed: 60)   // short earnings window, long calendar gap
        XCTAssertEqual(s.season, .autumn)   // spring(0) -> summer(1) -> autumn(2.5)
    }

    func testDayOfSeasonIsOneIndexedAndWrapsPerSeason() {
        var s = GameState.newGame()
        let start = Date()
        s.calendarStartedAt = start
        GameCalendar.advance(&s, now: start.addingTimeInterval(GameCalendar.dayLength * 0.5))
        XCTAssertEqual(GameCalendar.dayOfSeason(s, now: start.addingTimeInterval(GameCalendar.dayLength * 0.5)), 1)
        let elevenDaysIn = start.addingTimeInterval(GameCalendar.dayLength * 10.5)
        XCTAssertEqual(GameCalendar.dayOfSeason(s, now: elevenDaysIn), 11)
    }

    func testTickAdvancesSeasonOverManyTicks() {
        var s = GameState.newGame()
        s.calendarStartedAt = Date().addingTimeInterval(-(GameCalendar.dayLength * Double(GameCalendar.daysPerSeason) * 1.5))
        var rng = SeededGenerator(seed: 1)
        _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertEqual(s.season, .summer)
    }

    // MARK: seasonal ingredient pricing

    func testSeasonalMultiplierIsNeutralInSpring() {
        for ing in MenuCatalog.ingredients {
            XCTAssertEqual(SeasonalPricing.multiplier(ing.id, .spring), 1.0, accuracy: 1e-9)
        }
    }

    func testSeasonalMultiplierChangesLivePrice() {
        var s = GameState.newGame()
        s.marketPrices["berry"] = MenuCatalog.ingredientDef("berry")!.unitCost   // pin out the random walk
        s.season = .spring
        let springPrice = MenuCatalog.currentUnitCost("berry", s)
        s.season = .summer
        let summerPrice = MenuCatalog.currentUnitCost("berry", s)
        s.season = .winter
        let winterPrice = MenuCatalog.currentUnitCost("berry", s)
        XCTAssertLessThan(summerPrice, springPrice, "berries should be cheaper in their in-season summer")
        XCTAssertGreaterThan(winterPrice, springPrice, "berries should be pricier out of season in winter")
    }

    func testSeasonalMultiplierComposesWithMarketDriftAndStaysClampedToRawBase() {
        // The seasonal multiplier layers on top of the drifted price rather
        // than shifting MarketEngine's own clamp, so the raw drifted price
        // (before the seasonal multiplier) must still respect the
        // documented 0.5x-2x band against the flat base unitCost — exactly
        // like MarketTests.testPriceDriftStaysWithinBounds already checks.
        var s = GameState.newGame()
        s.season = .winter
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<1_000 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
            for ing in MenuCatalog.ingredients {
                let raw = s.marketPrices[ing.id] ?? ing.unitCost
                XCTAssertGreaterThanOrEqual(raw, ing.unitCost * MarketEngine.minMultiplier - 1e-9)
                XCTAssertLessThanOrEqual(raw, ing.unitCost * MarketEngine.maxMultiplier + 1e-9)
                // effective price = raw (clamped) x seasonal multiplier
                let expected = raw * SeasonalPricing.multiplier(ing.id, s.season)
                XCTAssertEqual(MenuCatalog.currentUnitCost(ing.id, s), expected, accuracy: 1e-9)
            }
        }
    }

    // MARK: storage capacity

    func testStorageCapEnforcedOnPackBuying() {
        var s = GameState.newGame()
        s.coins = 1_000_000
        s.stock["beans"] = EconomyEngine.storageCap(s) - 10   // 10 units of headroom left
        XCTAssertFalse(SalesEngine.buyPack("beans", units: 25, &s), "a pack bigger than remaining headroom should be rejected outright")
        XCTAssertEqual(s.stock["beans"], EconomyEngine.storageCap(s) - 10, "rejected buy must not partially fill")
        s.stock["beans"] = EconomyEngine.storageCap(s)
        XCTAssertFalse(SalesEngine.buyPack("beans", units: 25, &s), "no headroom left at all")
    }

    func testStorageCapEnforcedOnManagerRestock() {
        var s = GameState.newGame()
        s.coins = 10_000_000
        s.staffLevels["marble"] = 5
        s.refillThreshold = 1.0
        s.stock = ["beans": 0]
        var rng = SeededGenerator(seed: 9)
        for _ in 0..<20 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        }
        XCTAssertLessThanOrEqual(s.stock["beans"] ?? 0, EconomyEngine.storageCap(s))
    }

    func testStorageUpgradeCostAndCapFollowEscalatingCeilingPattern() {
        var s = GameState.newGame()
        s.coins = 10_000_000
        let cap0 = EconomyEngine.storageCap(s)
        let cost0 = EconomyEngine.storageCost(s)
        XCTAssertTrue(EconomyEngine.buyStorage(&s))
        XCTAssertEqual(s.storageLevel, 1)
        XCTAssertGreaterThan(EconomyEngine.storageCap(s), cap0)
        XCTAssertGreaterThan(EconomyEngine.storageCost(s), cost0)
        while EconomyEngine.buyStorage(&s) {}
        XCTAssertEqual(s.storageLevel, EconomyEngine.maxStorageLevel)
        XCTAssertEqual(EconomyEngine.storageCost(s), .infinity)
        XCTAssertFalse(EconomyEngine.buyStorage(&s))
    }

    // MARK: refill threshold

    func testRefillThresholdChangesRestockBehavior() {
        var low = GameState.newGame()
        low.coins = 1_000_000
        low.staffLevels["marble"] = 5
        low.refillThreshold = 0.2
        low.stock = ["beans": 0]
        SalesEngine.managerRestock(&low)

        var high = GameState.newGame()
        high.coins = 1_000_000
        high.staffLevels["marble"] = 5
        high.refillThreshold = 1.0
        high.stock = ["beans": 0]
        SalesEngine.managerRestock(&high)

        XCTAssertLessThan(low.stock["beans"] ?? 0, high.stock["beans"] ?? 0)
        XCTAssertEqual(high.stock["beans"], EconomyEngine.storageCap(high))
    }

    func testRefillThresholdNeverExceedsStorageCap() {
        XCTAssertEqual(SalesEngine.managerTarget({
            var s = GameState.newGame()
            s.staffLevels["marble"] = 1
            s.refillThreshold = 1.0
            return s
        }()), EconomyEngine.storageCap(GameState.newGame()))
    }

    // MARK: backward compatibility

    func testOldSaveWithoutCalendarStartedAtDecodesWithDefault() throws {
        let json = """
        {"coins": 500, "lifetimeCoins": 500, "cafes": [
            {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        ]}
        """
        let state = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        // Decodes to "now" rather than crashing/nil — sensible default.
        XCTAssertEqual(state.calendarStartedAt.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertEqual(state.season, .spring)
    }

    func testOldSaveWithoutStorageFieldsDecodesWithDefaults() throws {
        let json = """
        {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        """
        let cafe = try JSONDecoder().decode(CafeState.self, from: Data(json.utf8))
        XCTAssertEqual(cafe.storageLevel, 0)
        XCTAssertEqual(cafe.refillThreshold, 1.0, accuracy: 1e-9)
    }
}
