import XCTest
@testable import PixelPetCafe

final class MarketTests: XCTestCase {

    // MARK: price drift

    func testPriceDriftStaysWithinBounds() {
        var s = GameState.newGame()
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<2_000 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
            for ing in MenuCatalog.ingredients {
                let price = MenuCatalog.currentUnitCost(ing.id, s)
                XCTAssertGreaterThanOrEqual(price, ing.unitCost * MarketEngine.minMultiplier - 1e-9)
                XCTAssertLessThanOrEqual(price, ing.unitCost * MarketEngine.maxMultiplier + 1e-9)
            }
        }
    }

    func testPriceActuallyChangesOverTime() {
        var s = GameState.newGame()
        let initial = MenuCatalog.currentUnitCost("beans", s)
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<500 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        }
        let later = MenuCatalog.currentUnitCost("beans", s)
        XCTAssertGreaterThan(abs(later - initial), 1e-6, "price should have moved from its starting value")
    }

    func testPriceHistoryIsTrimmedAndRecorded() {
        var s = GameState.newGame()
        var rng = SeededGenerator(seed: 5)
        for _ in 0..<200 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        }
        let history = s.priceHistory["beans"] ?? []
        XCTAssertFalse(history.isEmpty)
        XCTAssertLessThanOrEqual(history.count, MarketEngine.historyLimit)
        XCTAssertEqual(history.last, MenuCatalog.currentUnitCost("beans", s))
    }

    func testLivePackCostTracksMarketPrice() {
        var s = GameState.newGame()
        s.marketPrices["beans"] = 4.0    // pretend the market spiked
        XCTAssertEqual(MenuCatalog.livePackCost("beans", units: 25, s), 100, accuracy: 1e-9)
        XCTAssertEqual(SalesEngine.packPrice("beans", units: 25, s), 100, accuracy: 1e-9)
    }

    // MARK: spoilage

    func testReasonablyStockedCafeDoesNotSpoil() {
        var s = GameState.newGame()
        s.stock = GameState.starterStock   // typical starting buffer, no consumption history
        var rng = SeededGenerator(seed: 11)
        _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertEqual(s.stock["beans"], GameState.starterStock["beans"])
        XCTAssertEqual(s.stock["milk"], GameState.starterStock["milk"])
    }

    func testSpoilageDoesNotTouchStockBelowBuffer() {
        var s = GameState.newGame()
        s.stock["beans"] = 140   // below the 150-unit minimum buffer floor
        var rng = SeededGenerator(seed: 12)
        _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertEqual(s.stock["beans"], 140)
    }

    func testSpoilageTriggersOnGenuineOverstock() {
        var s = GameState.newGame()
        s.stock["beans"] = 9_999   // classic "bought way too much and forgot" pile
        var rng = SeededGenerator(seed: 13)
        _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        XCTAssertLessThan(s.stock["beans"] ?? 0, 9_999)
        // still shouldn't vaporize the whole pile in one tick
        XCTAssertGreaterThan(s.stock["beans"] ?? 0, 9_000)
    }

    func testSpoilageBufferNeverUndercutsManagerRestockTarget() {
        var s = GameState.newGame()
        s.coins = 10_000_000
        s.staffLevels["marble"] = 20     // manager target = 200/ingredient
        s.stock = ["beans": 0]
        var rng = SeededGenerator(seed: 14)
        for _ in 0..<20 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        }
        // manager should be able to hold its restock target without spoilage
        // immediately eating it back down tick after tick
        XCTAssertGreaterThanOrEqual(s.stock["beans"] ?? 0, 190)
    }

    // MARK: backward compatibility

    func testOldSaveWithoutMarketFieldsDecodesWithDefaults() throws {
        let json = """
        {"coins": 500, "lifetimeCoins": 500, "cafes": [
            {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        ]}
        """
        let state = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertTrue(state.marketPrices.isEmpty)
        XCTAssertTrue(state.priceHistory.isEmpty)
        // and it should normalize cleanly to live base prices
        let normalized = state.normalized()
        XCTAssertEqual(normalized.marketPrices["beans"], 2)
        XCTAssertEqual(normalized.priceHistory["beans"], [2])
    }

    func testOldSaveWithoutConsumptionEMADecodesWithDefault() throws {
        let json = """
        {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        """
        let cafe = try JSONDecoder().decode(CafeState.self, from: Data(json.utf8))
        XCTAssertTrue(cafe.consumptionEMA.isEmpty)
    }
}
