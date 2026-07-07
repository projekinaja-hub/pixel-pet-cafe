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
}
