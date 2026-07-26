import XCTest
@testable import PixelPetCafe

/// Live typing-speed filter — the half of the pipeline that decides how fast
/// the café *reacts* to your keyboard. The old flat 10-second average is what
/// made typing feel undetected: the numbers below are the regression fence.
final class TypingSpeedTests: XCTestCase {

    private let dt = 0.2   // the real sampler interval

    /// Mirrors the production sampler: per-sample key counts go into a
    /// trailing window, the window gives the measured rate, and the display
    /// value eases toward it.
    private struct Meter {
        var shown = 0.0
        private var window: [Double] = []
        private let slots = Int(EnergyEngine.rateWindow / 0.2)

        mutating func sample(keys: Double, dt: Double = 0.2) {
            window.append(EnergyEngine.creditedKeys(delta: keys, dt: dt))
            if window.count > slots { window.removeFirst(window.count - slots) }
            let measured = EnergyEngine.windowedKps(keysInWindow: window.reduce(0, +))
            shown = EnergyEngine.nextKps(current: shown, measured: measured, dt: dt)
        }
        var wpm: Double { shown * 12 }
    }

    /// Simulates typing at `wpm` for `seconds` and returns the reading the
    /// menu bar would show at the end.
    private func typeSteadily(wpm: Double, seconds: Double) -> Double {
        var m = Meter()
        for _ in 0..<Int(seconds / dt) { m.sample(keys: (wpm / 12) * dt) }
        return m.wpm
    }

    // MARK: responsiveness — the actual bug

    /// THE regression test. A real 50 WPM typist must clear the lowest
    /// brewing-animation threshold (12 WPM) within one second of starting.
    /// The old 10s-window math read ~5 WPM after a second and needed ~3s to
    /// cross 12 — so the café sat still while the player was typing.
    func testReactsWithinOneSecond() {
        XCTAssertGreaterThan(typeSteadily(wpm: 50, seconds: 1.0), 12)
    }

    func testReachesTopAnimationTierWhileTypingFast() {
        // 80 WPM sustained for two seconds should be well past the 50 WPM tier
        XCTAssertGreaterThan(typeSteadily(wpm: 80, seconds: 2.0), 50)
    }

    func testConvergesOnTheRealSpeed() {
        // sustained typing settles within 10% of the true rate
        let reading = typeSteadily(wpm: 60, seconds: 6.0)
        XCTAssertEqual(reading, 60, accuracy: 6)
    }

    /// A handful of casual keystrokes must NOT read as sprinting. Measuring
    /// off a single 0.2s sample made one key look like 60 WPM, so tapping a
    /// few keys pinned the whole meter — this is that regression.
    func testAFewCasualKeysDoNotReadAsFastTyping() {
        var m = Meter()
        m.sample(keys: 1)                      // three keys, one per sample
        m.sample(keys: 1)
        m.sample(keys: 1)
        XCTAssertLessThan(m.wpm, 20, "3 keystrokes must not look like real typing")
        // 3 keys inside a 2s window really is ~18 WPM, and it stays there
        // until those keys age out — then it returns to rest.
        for _ in 0..<20 { m.sample(keys: 0) }
        XCTAssertLessThan(m.wpm, 8)
    }

    func testOneKeystrokeIsWorthAboutOneKeystroke() {
        var m = Meter()
        m.sample(keys: 1)
        for _ in 0..<5 { m.sample(keys: 0) }
        // 1 key over a 2s window = 0.5 keys/sec = 6 WPM, never 60
        XCTAssertLessThan(m.wpm, 8)
    }

    func testRisesFasterThanItFalls() {
        let rise = typeSteadily(wpm: 60, seconds: 0.6)
        var m = Meter()
        for _ in 0..<Int(6.0 / dt) { m.sample(keys: (60.0 / 12) * dt) }
        let settled = m.wpm
        for _ in 0..<3 { m.sample(keys: 0) }
        XCTAssertGreaterThan(rise, settled - m.wpm, "must spring up faster than it sags")
    }

    /// Brief pauses between words must not blank the meter out.
    func testShortPauseKeepsTheCafeAwake() {
        var m = Meter()
        for _ in 0..<Int(4.0 / dt) { m.sample(keys: (60.0 / 12) * dt) }
        for _ in 0..<2 { m.sample(keys: 0) }   // 0.4s gap — a normal word break
        XCTAssertGreaterThan(m.wpm, 30, "a half-second pause shouldn't kill the animation")
    }

    func testStoppingSettlesToZero() {
        var m = Meter()
        for _ in 0..<Int(4.0 / dt) { m.sample(keys: (60.0 / 12) * dt) }
        for _ in 0..<Int(15 / dt) { m.sample(keys: 0) }
        XCTAssertEqual(m.shown, 0, accuracy: 0.05)
    }

    // MARK: credited keys

    func testNoKeysNoCredit() {
        XCTAssertEqual(EnergyEngine.creditedKeys(delta: 0, dt: dt), 0)
        XCTAssertEqual(EnergyEngine.creditedKeys(delta: -5, dt: dt), 0)   // counter reset
    }

    func testNormalTypingIsCreditedInFull() {
        // 60 WPM = 5 keys/sec = 1 key per 0.2s sample — nothing is dropped
        XCTAssertEqual(EnergyEngine.creditedKeys(delta: 1, dt: dt), 1, accuracy: 0.0001)
    }

    func testCatchUpAfterAStallIsCapped() {
        // timer stalled 10 minutes and the counter jumped 50k: credit is
        // bounded by the honest-typing ceiling rather than dumped in whole
        let credited = EnergyEngine.creditedKeys(delta: 50_000, dt: 600)
        XCTAssertEqual(credited, EnergyEngine.maxKeysPerSecond * 600, accuracy: 0.0001)
        XCTAssertLessThan(credited, 50_000)
    }

    func testSpeedReadingIsBoundedByTheCap() {
        // even an absurd counter jump can't show an impossible speed
        var m = Meter()
        for _ in 0..<20 { m.sample(keys: 9_999) }
        XCTAssertLessThanOrEqual(m.shown, EnergyEngine.maxKeysPerSecond + 0.001)
    }

    /// Holding a key down fires ~15 repeats/sec at the OS level; that is not
    /// typing, so the credit ceiling has to sit below it.
    func testKeyAutoRepeatCannotOutrunTheCeiling() {
        XCTAssertLessThan(EnergyEngine.maxKeysPerSecond, 15)
        var m = Meter()
        for _ in 0..<20 { m.sample(keys: 15 * dt) }
        XCTAssertLessThanOrEqual(m.wpm, EnergyEngine.maxKeysPerSecond * 12 + 0.1)
    }

    // MARK: the speed factor this all feeds

    func testFastTypingEarnsTheFullLiveBonus() {
        let kps = typeSteadily(wpm: 60, seconds: 6.0) / 12
        let factor = EnergyEngine.speedFactor(energy: 3000, kps: kps)
        XCTAssertEqual(factor, 1 + EnergyEngine.liveBonusMax, accuracy: 0.02)
    }
}
