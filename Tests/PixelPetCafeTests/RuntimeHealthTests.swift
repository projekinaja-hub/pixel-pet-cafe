import XCTest
@testable import PixelPetCafe

/// RuntimeHealth: the detector for the failure mode that has cost this project
/// the most time — a moving part dying while the app believes it is fine.
/// Each case below is a real incident.
final class RuntimeHealthTests: XCTestCase {

    private func probe(tick: TimeInterval = 1,
                       keys: TimeInterval? = 0.2,
                       render: TimeInterval? = 0.016) -> RuntimeHealth.Probe {
        RuntimeHealth.Probe(tickAge: tick, keySampleAge: keys, renderAge: render)
    }

    // MARK: healthy

    func testAllPartsMovingIsHealthy() {
        XCTAssertTrue(RuntimeHealth.isHealthy(probe()))
    }

    /// Ordinary scheduling jitter on a busy machine must never cry wolf — a
    /// false alarm would train the player to ignore the real one.
    func testOrdinaryJitterIsNotAFault() {
        XCTAssertTrue(RuntimeHealth.isHealthy(probe(tick: 2.5, keys: 1.0, render: 0.5)))
    }

    // MARK: real incidents

    /// The frozen popover: RunLoop timers silently stopped firing.
    func testStalledSimulationIsDetected() {
        XCTAssertEqual(RuntimeHealth.faults(probe(tick: 90)), [.simStalled])
    }

    /// The dead key monitor: it sat "installed" and delivered nothing forever,
    /// while `monitor != nil` still reported healthy.
    func testTypingNotBeingCountedIsDetected() {
        XCTAssertEqual(RuntimeHealth.faults(probe(keys: 30)), [.typingNotCounting])
    }

    /// The long-idle freeze: SpriteKit's display link died, so the picture
    /// froze while the simulation kept running.
    func testStalledRenderIsDetected() {
        XCTAssertEqual(RuntimeHealth.faults(probe(render: 20)), [.renderStalled])
    }

    func testEverythingDeadReportsEveryFault() {
        let faults = RuntimeHealth.faults(probe(tick: 600, keys: 600, render: 600))
        XCTAssertEqual(Set(faults), Set(RuntimeHealth.Fault.allCases))
    }

    // MARK: silence that is correct, not broken

    /// Typing switched off: nothing should be polling, so silence is right.
    func testTypingOffIsNotAFault() {
        XCTAssertTrue(RuntimeHealth.isHealthy(probe(keys: nil)))
    }

    /// The popover is closed, so the scene is paused deliberately. Flagging
    /// this would fire constantly — the app is closed almost all the time.
    func testOffscreenSceneIsNotAFault() {
        XCTAssertTrue(RuntimeHealth.isHealthy(probe(render: nil)))
    }

    // MARK: contract

    /// Every fault must be explainable to the player and name its recovery,
    /// since the entire point is to stop leaving them guessing.
    func testEveryFaultHasAPlayerFacingMessage() {
        for fault in RuntimeHealth.Fault.allCases {
            let msg = RuntimeHealth.message(for: fault)
            XCTAssertFalse(msg.isEmpty, "\(fault) has no message")
            XCTAssertTrue(msg.lowercased().contains("restart"),
                          "\(fault) must tell the player what is being done: \(msg)")
        }
    }

    /// Deadlines must sit above each part's real period, or the detector
    /// becomes a false-alarm generator.
    func testDeadlinesAreLooserThanTheRealPeriods() {
        XCTAssertGreaterThan(RuntimeHealth.tickStaleAfter, 1)          // 1s tick
        XCTAssertGreaterThan(RuntimeHealth.keySampleStaleAfter, 0.2)   // 0.2s sampler
        XCTAssertGreaterThan(RuntimeHealth.renderStaleAfter, 1.0 / 30) // ~60fps
    }
}
