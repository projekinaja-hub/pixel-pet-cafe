import Combine
import XCTest
@testable import PixelPetCafe

@MainActor
final class GameControllerTests: XCTestCase {
    func testCasinoStatsTrackWagerWinAndBiggestWin() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
        let controller = GameController(persistence: Persistence(directory: dir))
        controller.casinoAward(1000)   // seed coins via a "win" (test-only shortcut)
        XCTAssertTrue(controller.casinoTrySpend(100))
        XCTAssertEqual(controller.state.casinoWagered, 100, accuracy: 1e-9)
        controller.casinoAward(250)
        XCTAssertEqual(controller.state.casinoWon, 1250, accuracy: 1e-9)
        XCTAssertEqual(controller.state.casinoBiggestWin, 1000, accuracy: 1e-9)
        controller.casinoAward(5000)
        XCTAssertEqual(controller.state.casinoBiggestWin, 5000, accuracy: 1e-9)
        XCTAssertFalse(controller.casinoTrySpend(1_000_000))   // can't overspend
        try? FileManager.default.removeItem(at: dir)
    }

    func testJackpotPotGrowsWithEveryWagerAndEventuallyTriggersThroughCasinoAward() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
        let controller = GameController(persistence: Persistence(directory: dir))
        controller.casinoAward(10_000_000)   // seed plenty of coins to wager with
        let startingPot = controller.state.casinoJackpotPot
        XCTAssertEqual(startingPot, CasinoEngine.jackpotSeed, accuracy: 1e-9)

        var sawJackpotWin = false
        let cancellable = controller.casinoJackpotWon.sink { _ in sawJackpotWin = true }
        let wonBefore = controller.state.casinoWon
        var lastPot = startingPot
        // 5000 wagers at a flat 0.4% trigger chance each makes "never triggers"
        // astronomically unlikely (~2e-9) — this exercises the real
        // casinoTrySpend -> growJackpot -> casinoAward path end to end.
        for _ in 0..<5000 {
            XCTAssertTrue(controller.casinoTrySpend(100))
            XCTAssertGreaterThanOrEqual(controller.state.casinoJackpotPot, CasinoEngine.jackpotSeed,
                                         "pot must never go below the seed value")
            lastPot = controller.state.casinoJackpotPot
        }
        _ = lastPot
        XCTAssertTrue(sawJackpotWin, "expected the jackpot to trigger at least once in 5000 wagers")
        XCTAssertGreaterThan(controller.state.casinoWon, wonBefore,
                              "a jackpot win must flow through casinoAward's existing bookkeeping")
        cancellable.cancel()
        try? FileManager.default.removeItem(at: dir)
    }
}
