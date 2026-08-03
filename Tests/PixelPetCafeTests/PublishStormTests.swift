import XCTest
import Combine
@testable import PixelPetCafe

/// `GameController.state` is an `@Published` STRUCT, so every single write —
/// and the sim writes it many times per tick via `inout` calls — is a separate
/// Combine emission. `StatusItemController` answers each one by redrawing the
/// menu bar, which reads and decodes PNGs from disk. This test measures how
/// many emissions one second of ordinary play actually produces, because that
/// number is the multiplier on all of that work.
@MainActor
final class PublishStormTests: XCTestCase {

    private func tempController() -> GameController {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ppc-pubtest-\(UUID().uuidString)")
        return GameController(persistence: Persistence(directory: dir))
    }

    func testStateEmissionsPerSecondOfPlay() {
        let controller = tempController()
        var emissions = 0
        let bag = controller.$state.sink { _ in emissions += 1 }
        defer { bag.cancel() }

        emissions = 0                     // ignore the replay of the current value
        controller.start()

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        let perSecond = Double(emissions) / 3.0
        print("PERF state emissions: \(emissions) over 3s = \(String(format: "%.1f", perSecond))/sec")

        // Characterisation, not an aspiration: the sim ticks at 1 Hz but emits
        // ~6x that, because every `inout` mutation of the published struct is
        // its own emission. The mitigation lives on the CONSUMER side —
        // `StatusItemController.updateTitle` now skips any emission that would
        // redraw an identical menu bar, and decoded sprites are cached — so
        // the emission rate itself is merely tracked, not enforced down.
        //
        // The ceiling exists to catch an ACTUAL storm: a new high-frequency
        // publisher (the 5 Hz keystroke sampler writing straight into `state`,
        // say) would blow past this and drag the whole main thread with it.
        XCTAssertLessThan(perSecond, 15,
                          "emission rate exploded to \(perSecond)/sec — something new is writing state in a hot loop")
    }
}
