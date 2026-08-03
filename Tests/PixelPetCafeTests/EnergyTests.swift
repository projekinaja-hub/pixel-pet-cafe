import XCTest
@testable import PixelPetCafe

/// TYPING ENERGY core loop (EnergyEngine + GameState v13 fields).
final class EnergyTests: XCTestCase {

    // MARK: speedFactor

    func testEmptyTankCrawls() {
        XCTAssertEqual(EnergyEngine.speedFactor(energy: 0, kps: 0), EnergyEngine.crawlFactor)
        // no live bonus while empty — typing fast doesn't rescue a dead tank
        XCTAssertEqual(EnergyEngine.speedFactor(energy: 0, kps: 10), EnergyEngine.crawlFactor)
    }

    func testFullTankIdleIsNormalSpeed() {
        XCTAssertEqual(EnergyEngine.speedFactor(energy: EnergyEngine.energyCap, kps: 0), 1.0)
    }

    func testFullTankFastTypingHitsMaxBonus() {
        // stated relative to the constant, so tuning the bonus doesn't require
        // editing arithmetic in three places
        let full = 1 + EnergyEngine.liveBonusMax
        XCTAssertEqual(EnergyEngine.speedFactor(energy: EnergyEngine.energyCap,
                                                kps: EnergyEngine.liveBonusFullAtKps), full)
        // bonus is capped — hammering faster than the full-bonus rate stays there
        XCTAssertEqual(EnergyEngine.speedFactor(energy: 100, kps: 12), full)
        // half the full-bonus rate = half the bonus
        XCTAssertEqual(EnergyEngine.speedFactor(energy: 100, kps: EnergyEngine.liveBonusFullAtKps / 2),
                       1 + EnergyEngine.liveBonusMax / 2, accuracy: 1e-9)
    }

    /// Typing must be worth clearly more than a nudge, or the core mechanic
    /// reads as decorative. Measured at +50% it produced only ~1.5x the sales
    /// of never typing at all.
    func testTypingIsWorthAMeaningfulMultiplier() {
        XCTAssertGreaterThanOrEqual(EnergyEngine.liveBonusMax, 1.0)
    }

    /// The empty-tank crawl is what teaches the mechanic, so a new player has
    /// to be able to reach it in one sitting.
    func testStartingTankRunsOutWithinOneSession() {
        let minutes = EnergyEngine.startingTank / EnergyEngine.burnPerSec / 60
        XCTAssertLessThanOrEqual(minutes, 45, "the fuel lesson must land in a first session")
        XCTAssertGreaterThanOrEqual(minutes, 10, "…but not before the player finds their feet")
    }

    // MARK: tank bounds (controller-free simulation of the per-tick formulas)

    func testEnergyNeverExceedsCapOrDropsBelowZero() {
        var energy = 3000.0
        for typed in [0.0, 500, 5000, 0, 99_999, 3, 0] {
            energy = min(EnergyEngine.energyCap, energy + typed * EnergyEngine.energyPerKeystroke)
            energy = max(0, energy - EnergyEngine.burnPerSec * 1.0)
            XCTAssertLessThanOrEqual(energy, EnergyEngine.energyCap)
            XCTAssertGreaterThanOrEqual(energy, 0)
        }
        // long idle stretch: burns to exactly 0, never negative
        for _ in 0..<20_000 {
            energy = max(0, energy - EnergyEngine.burnPerSec * 1.0)
            XCTAssertGreaterThanOrEqual(energy, 0)
        }
        XCTAssertEqual(energy, 0)
    }

    // MARK: rush

    func testApplyRushSpendsAndStartsEvent() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.rushCost + 50
        let now = Date()
        XCTAssertTrue(EnergyEngine.applyRush(&s, now: now))
        XCTAssertEqual(s.energy, 50)
        XCTAssertEqual(s.activeEvent, "rush")
        XCTAssertEqual(s.eventEndsAt, now.addingTimeInterval(300))
    }

    func testApplyRushRefusedWhenUnaffordableOrEventRunning() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.rushCost - 1
        XCTAssertFalse(EnergyEngine.applyRush(&s, now: Date()))
        XCTAssertEqual(s.energy, EnergyEngine.rushCost - 1)   // nothing deducted

        s.energy = EnergyEngine.rushCost
        s.activeEvent = "rain"
        s.eventEndsAt = Date().addingTimeInterval(60)
        XCTAssertFalse(EnergyEngine.applyRush(&s, now: Date()))
        XCTAssertEqual(s.energy, EnergyEngine.rushCost)
        XCTAssertEqual(s.activeEvent, "rain")                 // event untouched
    }

    func testApplyRushClearsExpiredEventFirst() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.rushCost
        s.activeEvent = "rain"
        let now = Date()
        s.eventEndsAt = now.addingTimeInterval(-1)            // already over
        XCTAssertTrue(EnergyEngine.applyRush(&s, now: now))
        XCTAssertEqual(s.activeEvent, "rush")
    }

    // MARK: restock

    func testApplyRestockFillsEveryIngredientToCap() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.restockCost + 500
        s.stock = ["beans": 1]
        XCTAssertTrue(EnergyEngine.applyRestock(&s))
        XCTAssertEqual(s.energy, 500)
        let cap = EconomyEngine.storageCap(s)
        for ing in MenuCatalog.ingredients {
            XCTAssertEqual(s.stock[ing.id], cap, "\(ing.id) should be filled to cap")
        }
    }

    func testApplyRestockNeverLowersOverfilledStock() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.restockCost
        let cap = EconomyEngine.storageCap(s)
        s.stock["beans"] = cap + 25
        XCTAssertTrue(EnergyEngine.applyRestock(&s))
        XCTAssertEqual(s.stock["beans"], cap + 25)
    }

    func testApplyRestockRefusedWhenUnaffordable() {
        var s = GameState.newGame()
        s.energy = EnergyEngine.restockCost - 1
        let before = s.stock
        XCTAssertFalse(EnergyEngine.applyRestock(&s))
        XCTAssertEqual(s.stock, before)
        XCTAssertEqual(s.energy, EnergyEngine.restockCost - 1)
    }

    // MARK: persistence

    func testOldSaveWithoutEnergyFieldsDecodesToDefaults() throws {
        // simulate a pre-v13 save by stripping the new keys from fresh JSON
        let data = try JSONEncoder().encode(GameState.newGame())
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "energy")
        json.removeValue(forKey: "lifetimeKeystrokes")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(GameState.self, from: stripped)
        XCTAssertEqual(decoded.energy, EnergyEngine.startingTank)
        XCTAssertEqual(decoded.lifetimeKeystrokes, 0)
    }

    func testEnergyFieldsRoundTripThroughSave() throws {
        var s = GameState.newGame()
        s.energy = 1234
        s.lifetimeKeystrokes = 9876
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.energy, 1234)
        XCTAssertEqual(decoded.lifetimeKeystrokes, 9876)
    }

    func testNewGameStartsHalfTankWithMonitorOn() {
        let s = GameState.newGame()
        XCTAssertEqual(s.energy, EnergyEngine.startingTank)
        XCTAssertEqual(s.lifetimeKeystrokes, 0)
        XCTAssertTrue(s.workMode)   // energy is the core loop — on by default
    }
}

final class EnergyMigrationTests: XCTestCase {
    func testPrePivotSaveGetsTypingEnabledOnLoad() throws {
        let json = """
        {"coins": 100, "workMode": false, "cafes": [{"city": "home"}]}
        """
        // repairs live in migrated() now, so they run exactly once per save
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8)).migrated()
        XCTAssertTrue(s.workMode, "a save that never typed can't have opted out — energy is the core loop")
    }

    func testExplicitOptOutAfterTypingIsRespected() throws {
        let json = """
        {"coins": 100, "workMode": false, "lifetimeKeystrokes": 5000, "cafes": [{"city": "home"}]}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8)).migrated()
        XCTAssertFalse(s.workMode, "a player who typed and then turned it off keeps their choice")
    }
}
