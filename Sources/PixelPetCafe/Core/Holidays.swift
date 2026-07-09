import Foundation

/// A fixed one-day-a-season event, keyed by day-of-season (1...
/// GameCalendar.daysPerSeason) so it recurs predictably every time that
/// season comes back around — unlike Events.swift's random rush/rain,
/// these are calendar-driven and can be planned around, which is what
/// makes them worth showing on a calendar grid at all.
struct Holiday: Equatable {
    let dayOfSeason: Int
    let season: Season
    let name: String
    let emoji: String
    let priceBoost: Double     // multiplies priceMultiplier while active
    let customerBoost: Double  // multiplies customerRate while active
}

enum Holidays {
    /// Two per season, plus one big one closing out the year on winter's
    /// last day — the same day rotating goals refresh
    /// (GameCalendar.daysPerSeason), so the year always ends on a real
    /// beat rather than just quietly rolling over to spring.
    static let all: [Holiday] = [
        Holiday(dayOfSeason: 1, season: .spring, name: "Bloom Festival", emoji: "🌸",
                priceBoost: 1.0, customerBoost: 1.4),
        Holiday(dayOfSeason: 12, season: .spring, name: "Spring Fair", emoji: "🥚",
                priceBoost: 1.15, customerBoost: 1.0),
        Holiday(dayOfSeason: 1, season: .summer, name: "Summer Kickoff", emoji: "🎆",
                priceBoost: 1.0, customerBoost: 1.5),
        Holiday(dayOfSeason: 12, season: .summer, name: "Heatwave Rush", emoji: "🍦",
                priceBoost: 1.2, customerBoost: 1.1),
        Holiday(dayOfSeason: 1, season: .autumn, name: "Harvest Day", emoji: "🍁",
                priceBoost: 1.15, customerBoost: 1.1),
        Holiday(dayOfSeason: 12, season: .autumn, name: "Autumn Market", emoji: "🎃",
                priceBoost: 1.0, customerBoost: 1.3),
        Holiday(dayOfSeason: 1, season: .winter, name: "First Snow", emoji: "❄️",
                priceBoost: 1.0, customerBoost: 1.3),
        Holiday(dayOfSeason: 12, season: .winter, name: "Winter Gala", emoji: "🎄",
                priceBoost: 1.3, customerBoost: 1.2),
        Holiday(dayOfSeason: 24, season: .winter, name: "New Year's Eve", emoji: "🎉",
                priceBoost: 1.5, customerBoost: 1.5),
    ]

    static func on(dayOfSeason: Int, season: Season) -> Holiday? {
        all.first { $0.dayOfSeason == dayOfSeason && $0.season == season }
    }

    static func today(_ s: GameState) -> Holiday? {
        on(dayOfSeason: GameCalendar.dayOfSeason(s), season: s.season)
    }

    /// This season's holidays, in day order — for the calendar grid.
    static func forSeason(_ season: Season) -> [Holiday] {
        all.filter { $0.season == season }.sorted { $0.dayOfSeason < $1.dayOfSeason }
    }
}
