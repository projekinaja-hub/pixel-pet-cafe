import Foundation

/// Purchases, prestige and offline caps as pure functions. Income itself is
/// customer-driven — see SalesEngine.
enum EconomyEngine {
    static let prestigeThreshold: Double = 1_000_000
    static let staffCostGrowth: Double = 1.18
    static let equipmentCostGrowth: Double = 1.25
    static let baseOfflineCap: TimeInterval = 8 * 3600
    static let earlOfflineBonusPerLevel: TimeInterval = 3600

    // MARK: costs

    static func cost(base: Double, level: Int, growth: Double) -> Double {
        base * pow(growth, Double(level))
    }

    static func staffCost(_ id: String, _ s: GameState) -> Double {
        guard let def = Catalog.staffDef(id) else { return .infinity }
        return cost(base: def.baseCost, level: s.staffLevels[id] ?? 0, growth: staffCostGrowth)
    }

    /// Fancier cities cost more to build out, not just more to buy into: this
    /// scales by the same priceBonus a city already applies to sales, so a
    /// Moon café's espresso machine costs noticeably more per level than a
    /// Home café's at the same level (home's priceBonus is 1.0 — unaffected).
    static func equipmentCost(_ id: String, _ s: GameState) -> Double {
        guard let def = Catalog.equipmentDef(id) else { return .infinity }
        let base = cost(base: def.baseCost, level: s.equipmentLevels[id] ?? 0, growth: equipmentCostGrowth)
        return base * s.city.priceBonus
    }

    /// The café floor has room for 2 baked-in tables + 2 back-row tables (4).
    /// Owning several cities unlocks counter-side bar stools for 2 more seats
    /// (6) — a real "bigger business, bigger café" progression tied to
    /// expansion, not an invisible number with nothing to look at.
    static let citiesForBiggerCafe = 4
    static func maxTables(_ s: GameState) -> Int {
        s.cafes.count >= citiesForBiggerCafe ? 6 : 4
    }

    /// Extra seating: each table added lets one more dine-in guest be served
    /// at once instead of turned away.
    static func tableCost(_ s: GameState) -> Double {
        guard s.tables < maxTables(s) else { return .infinity }
        return cost(base: 500, level: s.tables - 2, growth: 1.6)
    }

    @discardableResult
    static func buyTable(_ s: inout GameState) -> Bool {
        guard s.tables < maxTables(s) else { return false }
        let c = tableCost(s)
        guard s.coins >= c else { return false }
        s.coins -= c
        s.tables += 1
        return true
    }

    /// Every staff role has a per-café level cap, so leveling can't run away
    /// forever chasing formulas that have long since maxed out or floored
    /// (e.g. Chip's cooldown bottoms out around level 13) — and, like
    /// equipmentCost, fancier cities raise the ceiling: each café further
    /// along the unlock order (Cities.all) gets a noticeably higher cap than
    /// the last, so expanding to a new city is real, visible headroom to
    /// keep growing staff in, not just another place to re-buy the same
    /// levels.
    static let staffLevelCapBase = 25
    static let staffLevelCapStepPerCity = 10
    static func staffLevelCap(_ s: GameState) -> Int {
        let cityIndex = Cities.all.firstIndex { $0.id == s.city.id } ?? 0
        return staffLevelCapBase + staffLevelCapStepPerCity * cityIndex
    }

    @discardableResult
    static func buyStaff(_ id: String, _ s: inout GameState) -> Bool {
        guard (s.staffLevels[id] ?? 0) < staffLevelCap(s) else { return false }
        let c = staffCost(id, s)
        guard s.coins >= c else { return false }
        s.coins -= c
        s.staffLevels[id, default: 0] += 1
        return true
    }

    /// Purely cosmetic, free, and global (persists across renovate/prestige,
    /// same as the custom menu/style) — self-expression, not a power upgrade.
    static func setStaffColor(_ id: String, body: StaffColor, clothes: StaffColor, _ s: inout GameState) {
        s.staffColors[id] = StaffColorPair(body: body, clothes: clothes)
    }

    static func resetStaffColor(_ id: String, _ s: inout GameState) {
        s.staffColors.removeValue(forKey: id)
    }

    @discardableResult
    static func buyEquipment(_ id: String, _ s: inout GameState) -> Bool {
        let c = equipmentCost(id, s)
        guard s.coins >= c else { return false }
        s.coins -= c
        s.equipmentLevels[id, default: 0] += 1
        return true
    }

    // MARK: storage capacity (per café, same cap applies to every ingredient)

    /// Starter pantry: 200 units of headroom per ingredient before a buy or
    /// an auto-restock is refused.
    static let baseStorageCap = 200
    static let storageCapPerLevel = 150
    static let maxStorageLevel = 12
    /// base 200 + 12 × 150 = 2,000 units/ingredient at max level — comfortably
    /// ahead of the spoilage buffer's 15-minute-of-consumption sizing at any
    /// realistic staffing, so a maxed-out pantry is a genuine "stop worrying
    /// about stock" milestone rather than a number nobody reaches.
    static func storageCap(_ s: GameState) -> Int {
        baseStorageCap + storageCapPerLevel * s.storageLevel
    }

    static func storageCost(_ s: GameState) -> Double {
        guard s.storageLevel < maxStorageLevel else { return .infinity }
        return cost(base: 800, level: s.storageLevel, growth: 1.55)
    }

    @discardableResult
    static func buyStorage(_ s: inout GameState) -> Bool {
        guard s.storageLevel < maxStorageLevel else { return false }
        let c = storageCost(s)
        guard s.coins >= c else { return false }
        s.coins -= c
        s.storageLevel += 1
        return true
    }

    // MARK: offline cap

    static func offlineCap(_ s: GameState) -> TimeInterval {
        baseOfflineCap + Double(s.staffLevels["earl"] ?? 0) * earlOfflineBonusPerLevel
    }

    // MARK: prestige

    static func prestigeStars(_ s: GameState) -> Int {
        guard s.lifetimeCoinsThisRun >= prestigeThreshold else { return 0 }
        return Int(floor(sqrt(s.lifetimeCoinsThisRun / prestigeThreshold)))
    }

    static func canRenovate(_ s: GameState) -> Bool { prestigeStars(s) >= 1 }

    /// Resets ONLY the café you're renovating (coins spent there, staff, gear,
    /// stock, cleanliness) for stars. Every other café you own is untouched —
    /// you keep building them up independently.
    /// Keeps globally: lifetime total, custom items, owner style, bar character,
    /// settings, and every other café's contents.
    static func renovate(_ s: inout GameState) {
        guard canRenovate(s) else { return }
        s.stars += prestigeStars(s)
        s.coins = 0
        s.lifetimeCoinsThisRun = 0
        s.reputation = 50
        s.adsActive = false
        let menu = MenuCatalog.items
            .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
            .map(\.id) + s.customItems.map(\.id)
        var fresh = CafeState.fresh(city: s.cafe.city)
        fresh.menuEnabled = menu
        s.cafe = fresh
    }

    // MARK: world prestige ("Move to a New Country")

    /// Gate is deliberately far past renovate's (100× the coin bar, plus
    /// owning half the map) — renovate is a "reset this café for a quick
    /// boost" action you can do every few minutes; this is a "you've mastered
    /// this run, start the whole game over for a permanent edge" milestone,
    /// so it should take real hours of play to reach, not be casually spammed.
    static let worldPrestigeCoinThreshold: Double = 100_000_000
    static let worldPrestigeCitiesRequired: Int = 6

    /// Permanent global price bonus per completed world reset — stacks with
    /// stars in priceMultiplier (see SalesEngine). Small per-reset (5%) since
    /// it's forever and compounds across many resets over a player's
    /// lifetime, unlike stars which reset to 0 with every world move.
    static let worldPermanentBonusPerVisit: Double = 0.05

    static func canMoveToNewCountry(_ s: GameState) -> Bool {
        s.lifetimeCoins >= worldPrestigeCoinThreshold && s.cafes.count >= worldPrestigeCitiesRequired
    }

    /// 10% of coins earned THIS RUN (since the last world move or renovate),
    /// not current wallet balance: current coins can be driven to ~0 just by
    /// buying upgrades in the run's final minutes (which is the natural,
    /// expected way to spend down before a reset anyway, since everything
    /// unspent is about to be wiped) — basing the jumpstart on current coins
    /// would punish that normal play pattern and perversely reward hoarding
    /// coins unspent instead of playing the café. lifetimeCoinsThisRun only
    /// ever goes up, so the jumpstart reflects genuine run performance and
    /// can't be tanked or gamed by spending timing.
    static func worldJumpstartCoins(_ s: GameState) -> Double {
        s.lifetimeCoinsThisRun * 0.10
    }

    /// The big reset: every café is gone but Home (fresh defaults), market
    /// resets to base, stars/reputation/taste/events reset — same convention
    /// as renovate, just chain-wide. In exchange: a 10% coin jumpstart (see
    /// worldJumpstartCoins) and +1 to `worldsVisited`, which grants a
    /// permanent +5% price bonus (stacking, forever) via SalesEngine — so
    /// every world move makes every future run measurably stronger.
    /// Survives untouched: achievements, owner/barCharacter, muted/workMode,
    /// all casino meta-progression, lifetimeCoins (the all-time total that
    /// gates menu unlocks and this very threshold), and worldsVisited itself.
    static func moveToNewCountry(_ s: inout GameState) {
        guard canMoveToNewCountry(s) else { return }
        let jumpstart = worldJumpstartCoins(s)
        s.worldsVisited += 1
        s.coins = jumpstart
        s.lifetimeCoinsThisRun = 0
        s.stars = 0
        s.reputation = 50
        s.adsActive = false
        s.menuTaste = [:]
        s.tasteKnown = []
        s.activeEvent = nil
        s.eventEndsAt = nil
        s.customItems = []
        for ing in MenuCatalog.ingredients {
            s.marketPrices[ing.id] = ing.unitCost
            s.priceHistory[ing.id] = [ing.unitCost]
        }
        var home = CafeState.fresh(city: "home")
        home.menuEnabled = MenuCatalog.items
            .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
            .map(\.id)
        s.cafes = [home]
        s.activeCafe = 0
    }

    // MARK: golden tip

    static func goldenTipValue(_ s: GameState) -> Double {
        max(600 * SalesEngine.incomeEstimate(s), 25)
    }

    // MARK: daily login streak (real calendar days, not the in-game calendar)

    /// +1%/day, capped at +25% — small enough not to dominate the economy,
    /// big enough to feel like a real reason to come back tomorrow.
    static let dailyStreakBonusPerDay = 0.01
    static let dailyStreakBonusCap = 0.25
    static func dailyStreakMultiplier(_ s: GameState) -> Double {
        1 + min(dailyStreakBonusCap, dailyStreakBonusPerDay * Double(s.dailyStreak))
    }

    /// Called once per app launch. Same real-world day as last time: no
    /// change. Exactly the next calendar day: streak continues. Any gap (or
    /// first-ever launch): streak resets to 1 — missing a day costs the
    /// streak, which is the whole point of a streak.
    static func updateDailyStreak(_ s: inout GameState, now: Date = Date()) {
        let cal = Calendar.current
        guard let last = s.lastPlayedRealDate else {
            s.dailyStreak = 1
            s.lastPlayedRealDate = now
            return
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day ?? 0
        if days == 0 {
            // already counted today
        } else if days == 1 {
            s.dailyStreak += 1
        } else {
            s.dailyStreak = 1
        }
        s.lastPlayedRealDate = now
    }
}
