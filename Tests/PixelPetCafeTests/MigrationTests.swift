import XCTest
@testable import PixelPetCafe

/// Versioned save migrations. The repairs these cover used to live in
/// `normalized()`, which runs on EVERY load — so they could fire repeatedly,
/// and the energy restore was farmable by relaunching. These tests pin the
/// "exactly once" contract.
final class MigrationTests: XCTestCase {

    /// An old save: no version field at all decodes as version 0.
    private func legacySave() -> GameState {
        var s = GameState.newGame()
        s.saveVersion = 0
        return s
    }

    // MARK: run-once contract

    func testMigrationStampsCurrentVersion() {
        XCTAssertEqual(legacySave().migrated().saveVersion, GameState.currentSaveVersion)
    }

    func testAlreadyCurrentSaveIsUntouched() {
        var s = GameState.newGame()
        s.energy = 12
        s.stars = 40
        s.reputation = 3
        XCTAssertEqual(s.saveVersion, GameState.currentSaveVersion)
        let after = s.migrated()
        XCTAssertEqual(after.energy, 12, "a current save must not be 'repaired' again")
        XCTAssertEqual(after.stars, 40)
        XCTAssertEqual(after.reputation, 3)
    }

    /// THE bug this refactor exists for: the empty-tank repair was reachable
    /// on every single load, so quitting and relaunching refilled the tank
    /// forever as long as lifetime keystrokes stayed under the threshold.
    func testEmptyTankRepairCannotBeFarmedByRelaunching() {
        var s = legacySave()
        s.energy = 0
        s.lifetimeKeystrokes = 10        // still under deadCountingThreshold

        let firstLoad = s.migrated()
        XCTAssertEqual(firstLoad.energy, EnergyEngine.startingTank, "the one legitimate repair should happen")

        // player burns the tank down again, then relaunches
        var spent = firstLoad
        spent.energy = 0
        let secondLoad = spent.migrated()
        XCTAssertEqual(secondLoad.energy, 0, "relaunching must NOT refill the tank again")
    }

    func testRepeatedMigrationIsIdempotent() {
        var s = legacySave()
        s.energy = 0
        s.stars = 5_000_000
        s.reputation = 0
        let once = s.migrated()
        let twice = once.migrated()
        XCTAssertEqual(once, twice)
    }

    // MARK: the version-1 repairs themselves

    func testLegacyStarExplosionIsCollapsed() {
        var s = legacySave()
        s.stars = 1_434_965_406          // real value minted by the old sqrt formula
        XCTAssertLessThan(s.migrated().stars, 1000)
    }

    func testLegacyClosedCafeReputationGrindIsForgiven() {
        var s = legacySave()
        s.reputation = 0
        XCTAssertGreaterThanOrEqual(s.migrated().reputation, SalesEngine.closedReputationFloor)
    }

    func testPrePivotSaveGetsTypingTurnedOn() {
        var s = legacySave()
        s.workMode = false
        s.lifetimeKeystrokes = 0
        XCTAssertTrue(s.migrated().workMode)
    }

    /// Someone who has really played and then deliberately switched typing off
    /// must keep it off.
    func testDeliberateOptOutIsRespected() {
        var s = legacySave()
        s.workMode = false
        s.lifetimeKeystrokes = 50_000
        XCTAssertFalse(s.migrated().workMode, "a real player's choice must survive migration")
    }

    // MARK: normalized() stays idempotent

    func testNormalizedIsIdempotent() {
        let once = GameState.newGame().normalized()
        XCTAssertEqual(once, once.normalized())
    }

    func testNormalizedDoesNotRepairEnergy() {
        var s = GameState.newGame()
        s.energy = 0
        s.lifetimeKeystrokes = 0
        XCTAssertEqual(s.normalized().energy, 0,
                       "one-time repairs must live in migrated(), never normalized()")
    }

    // MARK: round-trip

    func testVersionSurvivesEncodeDecode() throws {
        let s = GameState.newGame().migrated()
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.saveVersion, GameState.currentSaveVersion)
    }

    /// A save written before the version field existed has no such key.
    func testSaveWithoutVersionKeyDecodesAsLegacy() throws {
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(GameState.newGame())) as! [String: Any]
        json.removeValue(forKey: "saveVersion")
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.saveVersion, 0, "a versionless save must be treated as legacy")
    }
}
