import XCTest
@testable import PixelPetCafe

final class EquipmentLevelCapTests: XCTestCase {
    func testHomeCafeCapMatchesBase() {
        let s = GameState.newGame()
        XCTAssertEqual(EconomyEngine.equipmentLevelCap(s), EconomyEngine.equipmentLevelCapBase)
    }

    func testLaterCitiesHaveAHigherCapThanEarlierOnes() {
        var s = GameState.newGame()
        let homeCap = EconomyEngine.equipmentLevelCap(s)
        s.cafes.append(CafeState.fresh(city: "moon"))
        s.activeCafe = 1
        XCTAssertGreaterThan(EconomyEngine.equipmentLevelCap(s), homeCap)
    }

    func testBuyEquipmentRefusesPastTheCap() {
        var s = GameState.newGame()
        s.coins = .infinity
        s.equipmentLevels["espresso"] = EconomyEngine.equipmentLevelCap(s)
        let bought = EconomyEngine.buyEquipment("espresso", &s)
        XCTAssertFalse(bought)
        XCTAssertEqual(s.equipmentLevels["espresso"], EconomyEngine.equipmentLevelCap(s))
    }

    func testBuyEquipmentSucceedsOneBelowTheCap() {
        var s = GameState.newGame()
        s.coins = .infinity
        s.reputation = 100   // clear the reputation gate; this test is about the CAP
        s.equipmentLevels["espresso"] = EconomyEngine.equipmentLevelCap(s) - 1
        let bought = EconomyEngine.buyEquipment("espresso", &s)
        XCTAssertTrue(bought)
    }
}
