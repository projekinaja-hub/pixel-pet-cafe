import XCTest
@testable import PixelPetCafe

final class GoalsTests: XCTestCase {

    // MARK: recordProgress / claim

    func testRecordProgressOnlyAffectsMatchingUnclaimedGoalAndClamps() {
        var s = GameState.newGame()
        s.activeGoals = [
            ActiveGoal(kind: .serveDrinks, progress: 0, claimed: false, rewardCoins: 100),
            ActiveGoal(kind: .cleanCafe, progress: 0, claimed: false, rewardCoins: 100),
        ]
        Goals.recordProgress(&s, .serveDrinks, amount: 3)
        XCTAssertEqual(s.activeGoals[0].progress, 3)
        XCTAssertEqual(s.activeGoals[1].progress, 0)   // unrelated kind untouched

        // clamps at the goal's target (serveDrinks target is 15)
        Goals.recordProgress(&s, .serveDrinks, amount: 1_000)
        XCTAssertEqual(s.activeGoals[0].progress, Goals.def(.serveDrinks).target)
    }

    func testRecordProgressIgnoresAlreadyClaimedGoal() {
        var s = GameState.newGame()
        s.activeGoals = [ActiveGoal(kind: .cleanCafe, progress: 5, claimed: true, rewardCoins: 50)]
        Goals.recordProgress(&s, .cleanCafe, amount: 1)
        XCTAssertEqual(s.activeGoals[0].progress, 5)   // untouched once claimed
    }

    func testClaimGrantsRewardExactlyOnce() {
        var s = GameState.newGame()
        s.activeGoals = [ActiveGoal(kind: .cleanCafe, progress: Goals.def(.cleanCafe).target,
                                     claimed: false, rewardCoins: 250)]
        let coinsBefore = s.coins
        let first = Goals.claim(&s, .cleanCafe)
        XCTAssertEqual(first, 250)
        XCTAssertEqual(s.coins, coinsBefore + 250, accuracy: 1e-9)
        XCTAssertTrue(s.activeGoals[0].claimed)

        let second = Goals.claim(&s, .cleanCafe)   // already claimed
        XCTAssertEqual(second, 0)
        XCTAssertEqual(s.coins, coinsBefore + 250, accuracy: 1e-9)   // unchanged
    }

    func testClaimRefusesIncompleteGoal() {
        var s = GameState.newGame()
        s.activeGoals = [ActiveGoal(kind: .cleanCafe, progress: 1, claimed: false, rewardCoins: 250)]
        XCTAssertEqual(Goals.claim(&s, .cleanCafe), 0)
        XCTAssertFalse(s.activeGoals[0].claimed)
    }

    // MARK: progress actually increments at the real call sites

    func testServingADrinkIncrementsServeDrinksGoalNotServePastries() {
        var s = GameState.newGame()   // starter menu: espresso_shot only (drink)
        s.coins = 10_000
        s.stock = ["beans": 100, "milk": 100, "flour": 100, "sugar": 100]
        s.customerProgress = 0.999
        s.activeGoals = [
            ActiveGoal(kind: .serveDrinks, progress: 0, claimed: false, rewardCoins: 60),
            ActiveGoal(kind: .servePastries, progress: 0, claimed: false, rewardCoins: 60),
        ]
        var rng = SeededGenerator(seed: 7)
        let events = SalesEngine.tick(&s, dt: 60, rng: &rng)   // dt large enough to guarantee a serve
        XCTAssertFalse(events.isEmpty)
        XCTAssertFalse(events.allSatisfy(\.angry))
        XCTAssertGreaterThan(s.activeGoals.first { $0.kind == .serveDrinks }!.progress, 0)
        XCTAssertEqual(s.activeGoals.first { $0.kind == .servePastries }!.progress, 0)
    }

    func testCleanSpotAndSweepAllIncrementCleanCafeGoal() {
        var s = GameState.newGame()
        s.activeGoals = [ActiveGoal(kind: .cleanCafe, progress: 0, claimed: false, rewardCoins: 60)]
        s.cleanliness = 50
        SalesEngine.cleanSpot(&s)
        XCTAssertEqual(s.activeGoals[0].progress, 1)

        s.coins = 10_000
        s.cleanliness = 50
        SalesEngine.sweepAll(&s)
        XCTAssertEqual(s.activeGoals[0].progress, 2)
    }

    func testResearchTasteIncrementsResearchTasteGoal() {
        var s = GameState.newGame()
        s.coins = 1_000_000
        s.activeGoals = [ActiveGoal(kind: .researchTaste, progress: 0, claimed: false, rewardCoins: 60)]
        XCTAssertTrue(SalesEngine.researchTaste(&s))
        XCTAssertEqual(s.activeGoals[0].progress, 1)
    }

    @MainActor
    func testCasinoAwardIncrementsCasinoWinGoal() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
        let controller = GameController(persistence: Persistence(directory: dir))
        controller.setGoalsForTesting([ActiveGoal(kind: .casinoWin, progress: 0, claimed: false, rewardCoins: 60)])
        controller.casinoAward(500)
        XCTAssertEqual(controller.state.activeGoals[0].progress, 1)
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    func testBuyEquipmentIncrementsUpgradeEquipmentGoal() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
        let controller = GameController(persistence: Persistence(directory: dir))
        controller.casinoAward(1_000_000)   // seed coins (test-only shortcut, mirrors GameControllerTests)
        controller.setGoalsForTesting([ActiveGoal(kind: .upgradeEquipment, progress: 0, claimed: false, rewardCoins: 60)])
        controller.buyEquipment(Catalog.equipment[0].id)
        XCTAssertEqual(controller.state.activeGoals[0].progress, 1)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: refresh cadence

    func testRefreshIfNeededDoesNothingWithinTheSameDay() {
        var s = GameState.newGame()   // normalized() already seeded activeGoals + goalsDay
        let before = s.activeGoals
        var rng = SeededGenerator(seed: 3)
        let awarded = Goals.refreshIfNeeded(&s, now: s.calendarStartedAt.addingTimeInterval(10), rng: &rng)
        XCTAssertEqual(awarded, 0)
        XCTAssertEqual(s.activeGoals, before)
    }

    func testRefreshIfNeededRotatesOnNewCalendarDay() {
        var s = GameState.newGame()
        let dayOneKinds = Set(s.activeGoals.map(\.kind))
        var rng = SeededGenerator(seed: 3)
        let nextDay = s.calendarStartedAt.addingTimeInterval(GameCalendar.dayLength + 1)
        let awarded = Goals.refreshIfNeeded(&s, now: nextDay, rng: &rng)
        XCTAssertEqual(awarded, 0)   // nothing was complete, so nothing auto-paid
        XCTAssertEqual(s.goalsDay, 1)
        XCTAssertEqual(s.activeGoals.count, Goals.activeCount)
        _ = dayOneKinds   // (kinds may coincidentally repeat; count/day are the reliable assertions)
    }

    func testRefreshIfNeededAutoAwardsCompletedUnclaimedGoalsOnRollover() {
        var s = GameState.newGame()
        s.coins = 0
        s.lifetimeCoins = 0
        for i in s.activeGoals.indices {
            s.activeGoals[i].progress = Goals.def(s.activeGoals[i].kind).target
            s.activeGoals[i].rewardCoins = 42
        }
        let pendingTotal = Double(s.activeGoals.count) * 42
        var rng = SeededGenerator(seed: 9)
        let nextDay = s.calendarStartedAt.addingTimeInterval(GameCalendar.dayLength + 1)
        let awarded = Goals.refreshIfNeeded(&s, now: nextDay, rng: &rng)
        XCTAssertEqual(awarded, pendingTotal, accuracy: 1e-9)
        XCTAssertEqual(s.coins, pendingTotal, accuracy: 1e-9)
        XCTAssertEqual(s.lifetimeCoins, pendingTotal, accuracy: 1e-9)
        // the new set is fresh (unclaimed, zero progress)
        XCTAssertTrue(s.activeGoals.allSatisfy { !$0.claimed && $0.progress == 0 })
    }

    // MARK: backward compatibility

    func testOldSaveWithoutGoalsFieldsDecodesWithDefaultsThenSeedsOnNormalize() throws {
        let json = """
        {"coins": 500, "lifetimeCoins": 500, "cafes": [
            {"city": "home", "staffLevels": {"mocha": 1}, "stock": {}, "menuEnabled": []}
        ]}
        """
        let state = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertTrue(state.activeGoals.isEmpty)
        XCTAssertEqual(state.goalsDay, -1)

        let normalized = state.normalized()
        XCTAssertEqual(normalized.activeGoals.count, Goals.activeCount)
        XCTAssertTrue(normalized.activeGoals.allSatisfy { !$0.claimed && $0.progress == 0 })
        XCTAssertGreaterThanOrEqual(normalized.goalsDay, 0)
    }
}
