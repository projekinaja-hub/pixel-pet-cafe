import Foundation

/// In-game calendar: derives the day count and current `Season` from real
/// elapsed wall-clock time since `GameState.calendarStartedAt` — the same
/// pattern `SalesEngine.offlineSim` already uses for its away-window catch-up
/// (elapsed real time, not accumulated tick counts), so the calendar is
/// always correct even after the app was closed for days.
enum GameCalendar {
    /// 1 real hour ≈ 1 in-game day.
    static let dayLength: TimeInterval = 3600
    /// Length of a season in in-game days. At `dayLength` above, a season is
    /// 24 real hours and a full 4-season year is 4 real days — enough to give
    /// a daily player a season change every day or so, while a full year
    /// still reads as a real milestone within a week rather than a month.
    static let daysPerSeason = 24

    static func currentDay(startedAt: Date, now: Date = Date()) -> Int {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return Int(elapsed / dayLength)
    }

    static func season(forDay day: Int) -> Season {
        let cycle = Season.allCases  // declared order: spring, summer, autumn, winter
        let index = (day / daysPerSeason) % cycle.count
        return cycle[index]
    }

    /// Refreshes `GameState.season` from the current wall-clock time. Called
    /// once per tick (SalesEngine.tick) and once at the top of offlineSim, so
    /// the calendar advances correctly across an offline gap too.
    static func advance(_ s: inout GameState, now: Date = Date()) {
        s.season = season(forDay: currentDay(startedAt: s.calendarStartedAt, now: now))
    }

    /// 1-indexed day within the current season, for display ("Day 14, Spring").
    static func dayOfSeason(_ s: GameState, now: Date = Date()) -> Int {
        (currentDay(startedAt: s.calendarStartedAt, now: now) % daysPerSeason) + 1
    }
}

/// Seasonal ingredient pricing, layered on top of `MarketEngine`'s random
/// walk rather than folded into it: the multiplier here is applied when
/// *reading* the live unit price (`MenuCatalog.currentUnitCost`), so
/// `MarketEngine`'s own 0.5x-2x clamp — which is checked against the flat
/// base `unitCost` — is completely untouched by the calendar. The two
/// effects simply multiply together into the price the player actually pays.
/// Spring is the neutral baseline (multiplier 1.0 for every ingredient), so a
/// fresh game's prices are unaffected until the calendar actually moves.
enum SeasonalPricing {
    /// ingredient id -> season -> multiplier. Ingredients not listed here
    /// (milk, flour, sugar, matcha) are season-neutral (always 1.0) — pantry
    /// staples nobody thinks of as "in season."
    private static let table: [String: [Season: Double]] = [
        "beans": [.autumn: 1.05, .winter: 1.20],                  // imported bean, colder-season demand spike
        "cocoa": [.autumn: 1.05, .winter: 1.25],                  // hot cocoa season
        "berry": [.summer: 0.75, .autumn: 1.15, .winter: 1.30],   // cheap in season, pricier out of season
        "honey": [.autumn: 0.85, .winter: 1.15],                  // autumn harvest glut, thin in winter
    ]

    static func multiplier(_ ingredientId: String, _ season: Season) -> Double {
        table[ingredientId]?[season] ?? 1.0
    }
}
