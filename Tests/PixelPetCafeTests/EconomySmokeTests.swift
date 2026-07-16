import XCTest
@testable import PixelPetCafe

/// Economy v2 sanity bands: end-to-end "does the money feel right" checks
/// that pin the overall scale of the rebalanced curves (linear equipment,
/// flat star bonus, 0.08 base rate, 1.14/1.17 cost growth) without pinning
/// any single formula. If a rebalance moves these outside the bands, the
/// change is too big to ship silently.
final class EconomySmokeTests: XCTestCase {
    /// A brand-new café, played for 60 simulated seconds, should earn a
    /// modest-but-alive first minute: more than pocket change, nowhere near
    /// mid-game money.
    func testFreshCafeSixtySecondHaulIsInBand() {
        var s = GameState.newGame()
        var rng = SeededGenerator(seed: 42)
        let before = s.coins
        for _ in 0..<60 {
            _ = SalesEngine.tick(&s, dt: 1, rng: &rng)
        }
        let haul = s.coins - before
        XCTAssertGreaterThanOrEqual(haul, 5, "a fresh café's first minute should not feel dead")
        XCTAssertLessThanOrEqual(haul, 500, "a fresh café's first minute should not shower coins")
    }

    /// A representative mid-game café (sakura, all equipment Lv 10, all
    /// staff Lv 5, deep stock, healthy reputation) should sit in the
    /// tens-to-hundreds of coins per second.
    func testMidGameIncomeEstimateIsInBand() {
        var s = GameState.newGame()
        s.cafes[0].city = "sakura"
        s.lifetimeCoins = 1_000_000
        SalesEngine.unlockNewMenuItems(&s)
        for def in Catalog.equipment { s.equipmentLevels[def.id] = 10 }
        for def in Catalog.staff { s.staffLevels[def.id] = 5 }
        for ing in MenuCatalog.ingredients { s.stock[ing.id] = 1000 }
        s.reputation = 70
        let income = SalesEngine.incomeEstimate(s)
        XCTAssertGreaterThanOrEqual(income, 20, "mid-game should clearly outearn the early game")
        XCTAssertLessThanOrEqual(income, 5000, "mid-game must not already be at end-game scale")
    }
}
