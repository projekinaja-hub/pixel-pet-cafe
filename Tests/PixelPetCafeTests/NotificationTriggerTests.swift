import XCTest
@testable import PixelPetCafe

/// Pure trigger/formatting logic only — UNUserNotificationCenter itself is
/// deliberately untested (it crashes in unbundled test runners and is Apple's
/// code anyway).
final class NotificationTriggerTests: XCTestCase {
    private let cal = Calendar.current

    /// Today at a given hour, built through the same calendar the logic uses.
    private func todayAt(_ hour: Int, base: Date = Date()) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    // MARK: shouldSendStreakReminder

    func testFiresAfter7pmWhenNotPlayedTodayAndStreakWorthSaving() {
        let now = todayAt(19)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: yesterday, streak: 2, calendar: cal))
    }

    func testDoesNotFireBefore7pm() {
        let now = todayAt(18)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertFalse(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: yesterday, streak: 5, calendar: cal))
    }

    func testDoesNotFireWhenAlreadyPlayedToday() {
        let now = todayAt(21)
        let earlierToday = todayAt(9, base: now)
        XCTAssertFalse(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: earlierToday, streak: 5, calendar: cal))
    }

    func testDoesNotFireForShortStreak() {
        let now = todayAt(20)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertFalse(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: yesterday, streak: 1, calendar: cal))
        XCTAssertFalse(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: yesterday, streak: 0, calendar: cal))
    }

    func testDoesNotFireWithNoPlayHistory() {
        // streak >= 2 with nil lastPlayedRealDate can't happen in practice
        // (updateDailyStreak always sets it) — but the guard must not crash
        // or fire on the impossible combination.
        XCTAssertFalse(NotificationTriggers.shouldSendStreakReminder(
            now: todayAt(20), lastPlayed: nil, streak: 3, calendar: cal))
    }

    func testFiresLateAtNightNotJustAt7pm() {
        let now = todayAt(23)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(NotificationTriggers.shouldSendStreakReminder(
            now: now, lastPlayed: yesterday, streak: 10, calendar: cal))
    }

    // MARK: streakBonusPercent (mirrors EconomyEngine.dailyStreakMultiplier)

    func testStreakBonusPercentMatchesEconomyEngine() {
        for streak in [2, 5, 10, 25, 100] {
            var s = GameState.newGame()
            s.dailyStreak = streak
            let expected = Int(((EconomyEngine.dailyStreakMultiplier(s) - 1) * 100).rounded())
            XCTAssertEqual(NotificationTriggers.streakBonusPercent(streak: streak), expected,
                           "streak \(streak)")
        }
    }

    func testStreakBonusPercentCaps() {
        XCTAssertEqual(NotificationTriggers.streakBonusPercent(streak: 1000),
                       Int((EconomyEngine.dailyStreakBonusCap * 100).rounded()))
    }

    // MARK: holidayBody

    func testHolidayBodyMentionsOnlyActiveBoosts() {
        // customer-only boost (Bloom Festival shape)
        let customerOnly = Holiday(dayOfSeason: 1, season: .spring, name: "T", emoji: "x",
                                   priceBoost: 1.0, customerBoost: 1.4)
        let body1 = NotificationTriggers.holidayBody(customerOnly)
        XCTAssertTrue(body1.contains("+40% customers"))
        XCTAssertFalse(body1.contains("prices"))

        // price-only boost
        let priceOnly = Holiday(dayOfSeason: 1, season: .spring, name: "T", emoji: "x",
                                priceBoost: 1.15, customerBoost: 1.0)
        let body2 = NotificationTriggers.holidayBody(priceOnly)
        XCTAssertTrue(body2.contains("+15% prices"))
        XCTAssertFalse(body2.contains("customers"))
    }

    func testHolidayBodyMentionsBothBoosts() {
        let both = Holiday(dayOfSeason: 24, season: .winter, name: "New Year's Eve", emoji: "🎉",
                           priceBoost: 1.5, customerBoost: 1.5)
        let body = NotificationTriggers.holidayBody(both)
        XCTAssertTrue(body.contains("+50% prices"))
        XCTAssertTrue(body.contains("+50% customers"))
    }

    func testHolidayBodyFallbackWhenNoBoosts() {
        let dud = Holiday(dayOfSeason: 1, season: .spring, name: "T", emoji: "x",
                          priceBoost: 1.0, customerBoost: 1.0)
        XCTAssertFalse(NotificationTriggers.holidayBody(dud).isEmpty)
    }

    // MARK: every real holiday produces a sensible body

    func testAllDefinedHolidaysProduceNonEmptyBodies() {
        for h in Holidays.all {
            XCTAssertFalse(NotificationTriggers.holidayBody(h).isEmpty, h.name)
        }
    }
}
