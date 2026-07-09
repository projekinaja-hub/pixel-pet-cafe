import XCTest
@testable import PixelPetCafe

final class StaffLevelCapTests: XCTestCase {
    func testHomeCafeCapMatchesBase() {
        let s = GameState.newGame()
        XCTAssertEqual(EconomyEngine.staffLevelCap(s), EconomyEngine.staffLevelCapBase)
    }

    func testLaterCitiesHaveAHigherCapThanEarlierOnes() {
        var s = GameState.newGame()
        let homeCap = EconomyEngine.staffLevelCap(s)
        s.cafes.append(CafeState.fresh(city: "moon"))
        s.activeCafe = 1
        let moonCap = EconomyEngine.staffLevelCap(s)
        XCTAssertGreaterThan(moonCap, homeCap)
    }

    func testCapIncreasesMonotonicallyWithUnlockOrder() {
        var previousCap = -1
        for city in Cities.all {
            var s = GameState.newGame()
            s.cafes = [CafeState.fresh(city: city.id)]
            s.activeCafe = 0
            let cap = EconomyEngine.staffLevelCap(s)
            XCTAssertGreaterThan(cap, previousCap, "\(city.id) should have a higher cap than the previous city")
            previousCap = cap
        }
    }

    func testBuyStaffRefusesPastTheCap() {
        var s = GameState.newGame()
        s.coins = .infinity
        s.staffLevels["chip"] = EconomyEngine.staffLevelCap(s)
        let bought = EconomyEngine.buyStaff("chip", &s)
        XCTAssertFalse(bought)
        XCTAssertEqual(s.staffLevels["chip"], EconomyEngine.staffLevelCap(s))
    }

    func testBuyStaffSucceedsOneBelowTheCap() {
        var s = GameState.newGame()
        s.coins = .infinity
        s.staffLevels["chip"] = EconomyEngine.staffLevelCap(s) - 1
        let bought = EconomyEngine.buyStaff("chip", &s)
        XCTAssertTrue(bought)
        XCTAssertEqual(s.staffLevels["chip"], EconomyEngine.staffLevelCap(s))
    }

    func testCapDoesNotAffordablyChargeCoinsWhenRefused() {
        var s = GameState.newGame()
        s.coins = 1_000_000_000
        s.staffLevels["chip"] = EconomyEngine.staffLevelCap(s)
        let coinsBefore = s.coins
        _ = EconomyEngine.buyStaff("chip", &s)
        XCTAssertEqual(s.coins, coinsBefore)
    }
}
