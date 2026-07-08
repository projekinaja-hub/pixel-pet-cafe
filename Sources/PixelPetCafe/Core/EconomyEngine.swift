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

    @discardableResult
    static func buyStaff(_ id: String, _ s: inout GameState) -> Bool {
        let c = staffCost(id, s)
        guard s.coins >= c else { return false }
        s.coins -= c
        s.staffLevels[id, default: 0] += 1
        return true
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

    // MARK: golden tip

    static func goldenTipValue(_ s: GameState) -> Double {
        max(600 * SalesEngine.incomeEstimate(s), 25)
    }
}
