import XCTest
@testable import PixelPetCafe

/// Live typing-speed filter — the half of the pipeline that decides how fast
/// the café *reacts* to your keyboard. The old flat 10-second average is what
/// made typing feel undetected: the numbers below are the regression fence.
final class TypingSpeedTests: XCTestCase {

    private let dt = 0.2   // the real sampler interval

    /// Simulates typing at `wpm` for `seconds` and returns the reading the
    /// menu bar would show at the end.
    private func typeSteadily(wpm: Double, seconds: Double, from start: Double = 0) -> Double {
        let kps = wpm / 12                    // 5 chars/word
        var current = start
        for _ in 0..<Int(seconds / dt) {
            let credited = EnergyEngine.creditedKeys(delta: kps * dt, dt: dt)
            current = EnergyEngine.nextKps(current: current, creditedKeys: credited, dt: dt)
        }
        return current * 12                   // back to WPM
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

    func testRisesFasterThanItFalls() {
        let rise = typeSteadily(wpm: 60, seconds: 0.6)
        let settled = typeSteadily(wpm: 60, seconds: 6.0)
        // decay from the settled reading with no keys at all
        var falling = settled / 12
        for _ in 0..<3 {
            falling = EnergyEngine.nextKps(current: falling, creditedKeys: 0, dt: dt)
        }
        let dropped = settled - falling * 12
        XCTAssertGreaterThan(rise, dropped, "meter must spring up faster than it sags")
    }

    /// Brief pauses between words must not blank the meter out.
    func testShortPauseKeepsTheCafeAwake() {
        var kps = typeSteadily(wpm: 60, seconds: 4.0) / 12
        for _ in 0..<2 {   // 0.4s of no typing — a normal between-word gap
            kps = EnergyEngine.nextKps(current: kps, creditedKeys: 0, dt: dt)
        }
        XCTAssertGreaterThan(kps * 12, 30, "a half-second pause shouldn't kill the animation")
    }

    func testStoppingSettlesToZero() {
        var kps = typeSteadily(wpm: 60, seconds: 4.0) / 12
        for _ in 0..<Int(15 / dt) { kps = EnergyEngine.nextKps(current: kps, creditedKeys: 0, dt: dt) }
        XCTAssertEqual(kps, 0, accuracy: 0.05)
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
        var kps = 0.0
        for _ in 0..<20 {
            let credited = EnergyEngine.creditedKeys(delta: 9_999, dt: dt)
            kps = EnergyEngine.nextKps(current: kps, creditedKeys: credited, dt: dt)
        }
        XCTAssertLessThanOrEqual(kps, EnergyEngine.maxKeysPerSecond + 0.001)
    }

    // MARK: the speed factor this all feeds

    func testFastTypingEarnsTheFullLiveBonus() {
        let kps = typeSteadily(wpm: 60, seconds: 6.0) / 12
        let factor = EnergyEngine.speedFactor(energy: 3000, kps: kps)
        XCTAssertEqual(factor, 1 + EnergyEngine.liveBonusMax, accuracy: 0.02)
    }
}
