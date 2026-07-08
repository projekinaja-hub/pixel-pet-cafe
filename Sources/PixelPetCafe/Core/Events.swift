import Foundation

struct EventDef {
    let id: String
    let emoji: String
    let name: String
    let desc: String
    let duration: TimeInterval   // 0 = instant
}

/// Random café happenings. One at a time; timed effects live in GameState.
enum Events {
    static let all: [EventDef] = [
        EventDef(id: "rush", emoji: "🏃", name: "Morning Rush",
                 desc: "A crowd pours in — ×2 customers!", duration: 120),
        EventDef(id: "rain", emoji: "🌧", name: "Rainy Day",
                 desc: "Fewer walk-ins, but everyone wants a hot drink", duration: 150),
        EventDef(id: "supplier", emoji: "🚚", name: "Supplier Deal",
                 desc: "Ingredient packs half price — stock up now!", duration: 90),
        EventDef(id: "critic", emoji: "🧐", name: "Food Critic",
                 desc: "A critic just reviewed your café…", duration: 0),
        EventDef(id: "lucky_hour", emoji: "🍀", name: "Lucky Hour",
                 desc: "Casino payouts are running hot — press your luck!", duration: 120),
    ]

    static func def(_ id: String) -> EventDef? { all.first { $0.id == id } }

    static let spawnChancePerSecond = 1.0 / 420   // roughly one every ~7 minutes

    /// Rolls for a new event; applies instant effects. Returns the started event.
    static func maybeSpawn<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, now: Date, rng: inout R
    ) -> EventDef? {
        if let ends = s.eventEndsAt, now > ends {          // expire old
            s.activeEvent = nil
            s.eventEndsAt = nil
        }
        guard s.activeEvent == nil,
              Double.random(in: 0..<1, using: &rng) < spawnChancePerSecond * dt,
              SalesEngine.incomeEstimate(s) > 0 else { return nil }
        let event = all[Int.random(in: 0..<all.count, using: &rng)]
        // Lucky Hour is casino-only content — don't spawn it (and burn the
        // roll) for players who haven't unlocked the casino yet.
        if event.id == "lucky_hour", !s.casinoUnlocked { return nil }
        if event.duration > 0 {
            s.activeEvent = event.id
            s.eventEndsAt = now.addingTimeInterval(event.duration)
        } else if event.id == "critic" {
            // verdict: cleanliness + how refined the enabled menu is
            let tastes = s.menuEnabled.map { Double(s.menuTaste[$0] ?? 0) }
            let avgTaste = tastes.isEmpty ? 0 : tastes.reduce(0, +) / Double(tastes.count)
            let impressed = s.cleanliness >= 70 && avgTaste >= 1.5
            s.reputation = min(100, max(0, s.reputation + (impressed ? 8 : -8)))
            s.lastCriticVerdict = impressed
        }
        return event
    }

    static func isActive(_ id: String, _ s: GameState, now: Date = Date()) -> Bool {
        s.activeEvent == id && (s.eventEndsAt.map { now <= $0 } ?? false)
    }
}

// MARK: - Achievements

struct AchievementDef {
    let id: String
    let emoji: String
    let name: String
    let desc: String
    let check: (GameState) -> Bool
}

enum Achievements {
    static let all: [AchievementDef] = [
        AchievementDef(id: "first_100", emoji: "☕", name: "Regulars",
                       desc: "Serve 100 customers") { total($0) >= 100 },
        AchievementDef(id: "serve_1k", emoji: "🍽", name: "Neighborhood Favorite",
                       desc: "Serve 1,000 customers") { total($0) >= 1_000 },
        AchievementDef(id: "serve_10k", emoji: "🏆", name: "Café Legend",
                       desc: "Serve 10,000 customers") { total($0) >= 10_000 },
        AchievementDef(id: "coins_1m", emoji: "💰", name: "First Million",
                       desc: "Earn 1M lifetime coins") { $0.lifetimeCoins >= 1e6 },
        AchievementDef(id: "coins_1b", emoji: "🤑", name: "Billionaire Barista",
                       desc: "Earn 1B lifetime coins") { $0.lifetimeCoins >= 1e9 },
        AchievementDef(id: "coins_1t", emoji: "👑", name: "Coffee Tycoon",
                       desc: "Earn 1T lifetime coins") { $0.lifetimeCoins >= 1e12 },
        AchievementDef(id: "cities_3", emoji: "🗺", name: "Chain Reaction",
                       desc: "Own cafés in 3 cities") { $0.cafes.count >= 3 },
        AchievementDef(id: "cities_all", emoji: "🌍", name: "World Tour",
                       desc: "Own all 12 cafés") { $0.cafes.count >= Cities.all.count },
        AchievementDef(id: "stars_10", emoji: "⭐", name: "Serial Renovator",
                       desc: "Collect 10 prestige stars") { $0.stars >= 10 },
        AchievementDef(id: "rep_100", emoji: "💖", name: "Beloved",
                       desc: "Reach 100 reputation") { $0.reputation >= 100 },
        AchievementDef(id: "taste_max", emoji: "🌟", name: "Perfected Recipe",
                       desc: "Max out a recipe's taste") { $0.menuTaste.values.contains(10) },
        AchievementDef(id: "full_crew", emoji: "🐾", name: "Full House",
                       desc: "Hire all 7 staff in one café") { s in
            Catalog.staff.allSatisfy { (s.staffLevels[$0.id] ?? 0) > 0 } },
        // casino ones unlocked directly from gameplay:
        AchievementDef(id: "mahjong_win", emoji: "🀄", name: "Mahjong!",
                       desc: "Win a mahjong hand") { $0.achievements.contains("mahjong_win") },
        AchievementDef(id: "blackjack_natural", emoji: "🃏", name: "Natural 21",
                       desc: "Deal yourself a blackjack") { $0.achievements.contains("blackjack_natural") },
        AchievementDef(id: "slots_jackpot", emoji: "🎰", name: "Triple Star",
                       desc: "Hit the slots jackpot") { $0.achievements.contains("slots_jackpot") },
    ]

    private static func total(_ s: GameState) -> Int {
        s.salesCount.values.reduce(0, +)
    }

    /// 0…1 progress toward an unearned achievement (nil = not measurable).
    static func progress(_ id: String, _ s: GameState) -> Double? {
        let served = Double(total(s))
        switch id {
        case "first_100": return served / 100
        case "serve_1k": return served / 1_000
        case "serve_10k": return served / 10_000
        case "coins_1m": return s.lifetimeCoins / 1e6
        case "coins_1b": return s.lifetimeCoins / 1e9
        case "coins_1t": return s.lifetimeCoins / 1e12
        case "cities_3": return Double(s.cafes.count) / 3
        case "cities_all": return Double(s.cafes.count) / Double(Cities.all.count)
        case "stars_10": return Double(s.stars) / 10
        case "rep_100": return s.reputation / 100
        case "taste_max": return Double(s.menuTaste.values.max() ?? 0) / 10
        case "full_crew": return Double(Catalog.staff.filter { (s.staffLevels[$0.id] ?? 0) > 0 }.count) / 7
        default: return nil
        }
    }

    /// The unearned goal you're closest to — fuel for the header progress bar.
    static func nextGoal(_ s: GameState) -> (def: AchievementDef, progress: Double)? {
        all.compactMap { def -> (AchievementDef, Double)? in
            guard !s.achievements.contains(def.id),
                  let p = progress(def.id, s), p < 1 else { return nil }
            return (def, p)
        }
        .max { $0.1 < $1.1 }
    }

    /// Returns newly earned achievement ids and records them.
    static func checkAll(_ s: inout GameState) -> [AchievementDef] {
        var fresh: [AchievementDef] = []
        for def in all where !s.achievements.contains(def.id) && def.check(s) {
            s.achievements.append(def.id)
            fresh.append(def)
        }
        return fresh
    }
}
