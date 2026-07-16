import XCTest
@testable import PixelPetCafe

/// The daily check-in reward (real calendar days, like the login streak —
/// NOT the compressed in-game calendar): the first popover open of each real
/// day grants ~15 minutes of income, floored at 500 coins.
@MainActor
final class DailyCheckInTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeController() -> GameController {
        GameController(persistence: Persistence(directory: dir))
    }

    func testFirstOpenOfTheDayGrantsCheckInCoins() {
        let controller = makeController()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let coinsBefore = controller.state.coins
        let lifetimeBefore = controller.state.lifetimeCoins
        let runBefore = controller.state.lifetimeCoinsThisRun
        controller.refreshStreakOnInteraction(now: day1)
        let granted = controller.state.coins - coinsBefore
        XCTAssertGreaterThanOrEqual(granted, GameController.checkInMinCoins,
                                     "the grant is floored at 500 coins")
        XCTAssertEqual(controller.state.lifetimeCoins - lifetimeBefore, granted, accuracy: 1e-9)
        XCTAssertEqual(controller.state.lifetimeCoinsThisRun - runBefore, granted, accuracy: 1e-9)
        XCTAssertNotNil(controller.state.lastCheckInDate)
        XCTAssertEqual(controller.banner?.emoji, "🎁")
    }

    func testSecondOpenSameDayDoesNotGrantAgain() {
        let controller = makeController()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        controller.refreshStreakOnInteraction(now: day1)
        let coinsAfterFirst = controller.state.coins
        controller.refreshStreakOnInteraction(now: day1.addingTimeInterval(5 * 3600))
        XCTAssertEqual(controller.state.coins, coinsAfterFirst, accuracy: 1e-9,
                       "the check-in pays out once per real calendar day")
    }

    func testNextRealDayGrantsAgain() {
        let controller = makeController()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        controller.refreshStreakOnInteraction(now: day1)
        let coinsAfterFirst = controller.state.coins
        controller.refreshStreakOnInteraction(now: day1.addingTimeInterval(24 * 3600))
        XCTAssertGreaterThanOrEqual(controller.state.coins - coinsAfterFirst,
                                     GameController.checkInMinCoins,
                                     "a new real day grants a fresh check-in")
    }

    func testOldSaveWithoutCheckInFieldDecodesToNil() throws {
        let json = """
        {"coins": 100, "cafes": [{"city": "home"}]}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertNil(s.lastCheckInDate)
    }
}
