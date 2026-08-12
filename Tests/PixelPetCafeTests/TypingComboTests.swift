import XCTest
@testable import PixelPetCafe

/// Typing now pays money directly, not only speed. The danger in that idea is
/// entirely in the arithmetic: at 48 WPM you type 240 keystrokes a minute, so
/// "+1% per 10 keystrokes" is +24%/min — +1,440% in an hour and +30,000% over
/// a working day. Uncapped, it makes every upgrade, hire, city and prestige in
/// the game irrelevant within a day. The cap and the decay are the feature.
final class TypingComboTests: XCTestCase {

    // MARK: earning it

    func testTenKeystrokesIsOnePercent() {
        XCTAssertEqual(TypingCombo.next(current: 0, keystrokes: 10, dt: 1, typing: true),
                       1.0, accuracy: 0.001)
    }

    func testItAccumulatesWhileTyping() {
        var c = 0.0
        for _ in 0..<10 { c = TypingCombo.next(current: c, keystrokes: 10, dt: 1, typing: true) }
        XCTAssertEqual(c, 10.0, accuracy: 0.001)
    }

    func testFullComboDoublesTheMoney() {
        XCTAssertEqual(TypingCombo.multiplier(percent: TypingCombo.maxPercent), 2.0, accuracy: 0.001)
        XCTAssertEqual(TypingCombo.multiplier(percent: 0), 1.0, accuracy: 0.001)
    }

    // MARK: THE reason this is capped

    /// A working day of typing must not end in a 300x café.
    func testADayOfTypingCannotRunAway() {
        var c = 0.0
        // 8 hours at 48 WPM = 4 keys/sec, ticked once a second
        for _ in 0..<(8 * 3600) { c = TypingCombo.next(current: c, keystrokes: 4, dt: 1, typing: true) }
        XCTAssertEqual(c, TypingCombo.maxPercent, accuracy: 0.001,
                       "the combo must sit at the cap, not climb past it")
        XCTAssertLessThanOrEqual(TypingCombo.multiplier(percent: c), 2.0,
                                 "uncapped, this run would have been ~300x income")
    }

    func testABurstOfTypingCannotSkipPastTheCap() {
        let c = TypingCombo.next(current: 0, keystrokes: 1_000_000, dt: 1, typing: true)
        XCTAssertEqual(c, TypingCombo.maxPercent, accuracy: 0.001)
    }

    // MARK: losing it

    func testItDecaysWhenYouStop() {
        let c = TypingCombo.next(current: 50, keystrokes: 0, dt: 10, typing: false)
        XCTAssertEqual(c, 40.0, accuracy: 0.001)
    }

    func testItDrainsCompletelyAndStopsAtZero() {
        var c = TypingCombo.maxPercent
        for _ in 0..<200 { c = TypingCombo.next(current: c, keystrokes: 0, dt: 1, typing: false) }
        XCTAssertEqual(c, 0, accuracy: 0.001, "it must bottom out at zero, never go negative")
    }

    func testItHoldsSteadyWhileTypingRatherThanDecaying() {
        let c = TypingCombo.next(current: 50, keystrokes: 10, dt: 1, typing: true)
        XCTAssertGreaterThan(c, 50, "typing should never lose you combo")
    }

    /// Keys typed in the same tick that typing stopped were still genuinely
    /// typed, so they count — gaining and decaying can both happen in one step.
    func testKeystrokesStillCountOnTheTickTypingStops() {
        let c = TypingCombo.next(current: 10, keystrokes: 20, dt: 1, typing: false)
        XCTAssertEqual(c, 11.0, accuracy: 0.001)   // +2 earned, -1 decayed
    }

    // MARK: it can't produce nonsense

    func testExtremeAndInvalidInputsStayInRange() {
        for (cur, keys, dt, typing) in [(Double.nan, 5, 1.0, true),
                                        (Double.infinity, 0, 1.0, false),
                                        (-500.0, 0, 1.0, false),
                                        (50.0, -10, 1.0, true),
                                        (50.0, 5, 0.0, true)] {
            let c = TypingCombo.next(current: cur, keystrokes: keys, dt: dt, typing: typing)
            XCTAssertTrue(c.isFinite, "combo went non-finite from \(cur)")
            XCTAssertGreaterThanOrEqual(c, 0)
            XCTAssertLessThanOrEqual(c, TypingCombo.maxPercent)
        }
    }

    func testTheAdvertisedTimeToCapIsTrue() {
        // 1000 keystrokes ~= 4 minutes at 48 WPM, which is what the UI claims.
        XCTAssertEqual(TypingCombo.keystrokesToCap, 1000)
        var c = 0.0
        for _ in 0..<250 { c = TypingCombo.next(current: c, keystrokes: 4, dt: 1, typing: true) }
        XCTAssertEqual(c, TypingCombo.maxPercent, accuracy: 0.001,
                       "250 seconds at 4 keys/sec should be exactly the cap")
    }
}

/// The combo maths was tested; the WIRING was not. This is the only thing that
/// proves `pay` actually reaches the wallet rather than being computed and
/// dropped somewhere between GameController and SalesEngine.
final class TypingComboPayoutTests: XCTestCase {
    private func earned(pay: Double) -> Double {
        var s = GameState.newGame().normalized()
        s.coins = 0
        for ing in MenuCatalog.ingredients { s.stock[ing.id] = 999 }
        var rng = SeededGenerator(seed: 42)          // same customers both runs
        for _ in 0..<600 { _ = SalesEngine.tick(&s, dt: 1, boost: 1, pay: pay, rng: &rng) }
        return s.coins
    }

    func testFullComboActuallyDoublesWhatYouEarn() {
        let single = earned(pay: 1)
        let double = earned(pay: TypingCombo.multiplier(percent: TypingCombo.maxPercent))
        XCTAssertGreaterThan(single, 0, "the fixture earned nothing; it proves nothing")
        // Slightly OVER 2x is correct, not a bug: doubled pay also grows
        // lifetimeCoins twice as fast, which unlocks pricier menu items sooner.
        // The band catches the thing that matters — pay reaching the wallet at
        // all — without pinning that second-order effect.
        XCTAssertGreaterThan(double / single, 1.95, "combo isn't reaching the payout")
        XCTAssertLessThan(double / single, 2.5, "payout is compounding more than doubling")
    }
}
