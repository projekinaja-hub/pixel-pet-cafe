import XCTest
@testable import PixelPetCafe

final class StreakTests: XCTestCase {
    func testFirstLaunchStartsStreakAtOne() {
        var s = GameState.newGame()
        EconomyEngine.updateDailyStreak(&s, now: Date())
        XCTAssertEqual(s.dailyStreak, 1)
        XCTAssertNotNil(s.lastPlayedRealDate)
    }

    func testConsecutiveDayIncrementsStreak() {
        var s = GameState.newGame()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        EconomyEngine.updateDailyStreak(&s, now: day1)
        XCTAssertEqual(s.dailyStreak, 1)
        let day2 = day1.addingTimeInterval(24 * 3600)
        EconomyEngine.updateDailyStreak(&s, now: day2)
        XCTAssertEqual(s.dailyStreak, 2)
    }

    func testSameDayDoesNotDoubleCount() {
        var s = GameState.newGame()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        EconomyEngine.updateDailyStreak(&s, now: day1)
        EconomyEngine.updateDailyStreak(&s, now: day1.addingTimeInterval(3600))
        XCTAssertEqual(s.dailyStreak, 1)
    }

    func testMissedDayResetsStreak() {
        var s = GameState.newGame()
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        EconomyEngine.updateDailyStreak(&s, now: day1)
        EconomyEngine.updateDailyStreak(&s, now: day1.addingTimeInterval(24 * 3600))
        XCTAssertEqual(s.dailyStreak, 2)
        let gapDay = day1.addingTimeInterval(4 * 24 * 3600)   // 3-day gap
        EconomyEngine.updateDailyStreak(&s, now: gapDay)
        XCTAssertEqual(s.dailyStreak, 1)
    }

    func testStreakBonusCapsAtMax() {
        var s = GameState.newGame()
        s.dailyStreak = 1000
        XCTAssertEqual(EconomyEngine.dailyStreakMultiplier(s), 1 + EconomyEngine.dailyStreakBonusCap, accuracy: 1e-9)
    }

    func testOldSaveWithoutStreakFieldsDecodesWithDefaults() throws {
        let json = """
        {"coins": 100, "cafes": [{"city": "home"}]}
        """
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(s.dailyStreak, 0)
        XCTAssertNil(s.lastPlayedRealDate)
    }
}
