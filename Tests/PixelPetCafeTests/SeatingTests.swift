import XCTest
@testable import PixelPetCafe

final class SeatingTests: XCTestCase {
    func testTableAvailabilityDropsWithHighDemand() {
        var s = GameState.newGame()
        s.tables = 20
        let roomy = SalesEngine.tableAvailability(s)
        XCTAssertEqual(roomy, 1, accuracy: 1e-9)
        s.tables = 1
        s.staffLevels = ["mocha": 50, "biscuit": 50, "poppy": 50, "juno": 50, "bo": 50]
        let cramped = SalesEngine.tableAvailability(s)
        XCTAssertLessThan(cramped, 1)
    }

    func testNoTableTurnsAwayDineInGuestsUnderPressure() {
        var s = GameState.newGame()
        s.coins = 1_000_000
        s.stock = ["beans": 10_000, "milk": 10_000, "flour": 10_000, "sugar": 10_000]
        s.tables = 1
        s.staffLevels = ["mocha": 60, "biscuit": 60, "poppy": 60, "juno": 60, "bo": 60]
        var rng = SeededGenerator(seed: 11)
        var sawNoTable = false
        for _ in 0..<400 {
            var copy = s
            copy.customerProgress = 1
            if let e = SalesEngine.tick(&copy, dt: 0.001, rng: &rng).first, e.mood == .noTable {
                XCTAssertEqual(e.price, 0)
                XCTAssertTrue(e.dineIn)
                sawNoTable = true
                break
            }
        }
        XCTAssertTrue(sawNoTable, "expected at least one turned-away dine-in guest under heavy seating pressure")
    }

    func testBuyTableIncreasesCapacityAndCost() {
        var s = GameState.newGame()
        s.coins = 100_000
        let cost0 = EconomyEngine.tableCost(s)
        XCTAssertTrue(EconomyEngine.buyTable(&s))
        XCTAssertEqual(s.tables, 3)
        XCTAssertGreaterThan(EconomyEngine.tableCost(s), cost0)
    }

    func testTablesAreCappedAtWhatTheRoomCanActuallyShow() {
        var s = GameState.newGame()
        s.coins = 1_000_000
        while EconomyEngine.buyTable(&s) {}
        XCTAssertEqual(s.tables, EconomyEngine.maxTables(s))
        XCTAssertEqual(EconomyEngine.tableCost(s), .infinity)
        XCTAssertFalse(EconomyEngine.buyTable(&s))
    }

    func testOldSaveWithoutTablesFieldDecodesWithDefault() throws {
        let json = """
        {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        """
        let cafe = try JSONDecoder().decode(CafeState.self, from: Data(json.utf8))
        XCTAssertEqual(cafe.tables, 2)
    }
}
