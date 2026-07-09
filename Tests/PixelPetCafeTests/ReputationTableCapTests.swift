import XCTest
@testable import PixelPetCafe

/// Regression tests for "hearts (reputation) stuck at 0" — a real live save
/// had reputation pinned at 0 despite healthy stock/cleanliness because
/// dine-in demand (which scales with staff levels, uncapped in older saves)
/// permanently outstripped the hard 6-table ceiling, and every noTable
/// event dinged reputation. Sibling bug to the earlier capacity-block
/// reputation ding that was already removed for the kitchen throughput path.
final class ReputationTableCapTests: XCTestCase {
    func testNoTableNeverDingsReputationEvenAtExtremeDemand() {
        var s = GameState.newGame()
        s.coins = 1_000_000_000
        s.tables = 4
        // Demand far beyond what any realistic table count can seat.
        for id in Catalog.staff.map(\.id) { s.staffLevels[id] = 200 }
        s.reputation = 50
        var rng = SeededGenerator(seed: 7)
        let before = s.reputation
        for _ in 0..<200 {
            _ = SalesEngine.tick(&s, dt: 1.0, rng: &rng)
        }
        XCTAssertGreaterThanOrEqual(s.reputation, before - 1e-6,
                                     "table-capacity mismatches must never drag reputation down")
    }

    func testTableAvailabilityCollapsesUnderExtremeStaffLevels() {
        var s = GameState.newGame()
        s.tables = 4
        for id in Catalog.staff.map(\.id) { s.staffLevels[id] = 200 }
        XCTAssertLessThan(SalesEngine.tableAvailability(s), 0.1,
                           "sanity check: this scenario really does saturate table capacity")
    }
}
