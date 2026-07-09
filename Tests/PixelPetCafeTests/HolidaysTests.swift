import XCTest
@testable import PixelPetCafe

final class HolidaysTests: XCTestCase {
    func testNoHolidayOnAnOrdinaryDay() {
        XCTAssertNil(Holidays.on(dayOfSeason: 5, season: .spring))
    }

    func testKnownHolidayIsFound() {
        let h = Holidays.on(dayOfSeason: 1, season: .spring)
        XCTAssertEqual(h?.name, "Bloom Festival")
    }

    func testTodayMatchesCurrentSeasonAndDay() {
        var s = GameState.newGame()
        s.season = .winter
        s.calendarStartedAt = Date().addingTimeInterval(-23 * GameCalendar.dayLength) // day 24 of winter
        XCTAssertEqual(Holidays.today(s)?.name, "New Year's Eve")
    }

    func testEverySeasonHasAtLeastOneHoliday() {
        for season in Season.allCases {
            XCTAssertFalse(Holidays.forSeason(season).isEmpty, "\(season) has no holidays")
        }
    }

    func testHolidayBoostsPriceMultiplier() {
        var s = GameState.newGame()
        s.season = .winter
        s.calendarStartedAt = Date().addingTimeInterval(-23 * GameCalendar.dayLength)
        let onHoliday = SalesEngine.priceMultiplier(s)
        s.calendarStartedAt = Date() // ordinary day 0
        let ordinary = SalesEngine.priceMultiplier(s)
        XCTAssertGreaterThan(onHoliday, ordinary)
    }

    func testHolidayBoostsCustomerRate() {
        var s = GameState.newGame()
        s.season = .summer
        s.calendarStartedAt = Date() // day 1 of summer = Summer Kickoff
        let onHoliday = SalesEngine.customerRate(s)
        s.calendarStartedAt = Date().addingTimeInterval(-5 * GameCalendar.dayLength) // ordinary day
        let ordinary = SalesEngine.customerRate(s)
        XCTAssertGreaterThan(onHoliday, ordinary)
    }
}
