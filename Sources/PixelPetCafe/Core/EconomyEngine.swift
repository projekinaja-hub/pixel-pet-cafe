import Foundation

/// Purchases, prestige and offline caps as pure functions. Income itself is
/// customer-driven — see SalesEngine.
enum EconomyEngine {
    static let prestigeThreshold: Double = 1_000_000
    static let costGrowth: Double = 1.15
    static let baseOfflineCap: TimeInterval = 8 * 3600
    static let earlOfflineBonusPerLevel: TimeInterval = 3600

    // MARK: costs

    static func cost(base: Double, level: Int) -> Double {
        base * pow(costGrowth, Double(level))
    }

    static func staffCost(_ id: String, _ s: GameState) -> Double {
        guard let def = Catalog.staffDef(id) else { return .infinity }
        return cost(base: def.baseCost, level: s.staffLevels[id] ?? 0)
    }

    static func equipmentCost(_ id: String, _ s: GameState) -> Double {
        guard let def = Catalog.equipmentDef(id) else { return .infinity }
        return cost(base: def.baseCost, level: s.equipmentLevels[id] ?? 0)
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

    /// Resets the run (coins, staff, equipment, stock, cleanliness) for stars.
    /// Keeps: lifetime total, custom items, owner style, bar character, settings.
    static func renovate(_ s: inout GameState) {
        guard canRenovate(s) else { return }
        s.stars += prestigeStars(s)
        s.coins = 0
        s.lifetimeCoinsThisRun = 0
        s.staffLevels = ["mocha": 1]
        s.equipmentLevels = [:]
        s.stock = GameState.starterStock
        s.cleanliness = 100
        s.customerProgress = 0
        s.menuEnabled = MenuCatalog.items
            .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
            .map(\.id) + s.customItems.map(\.id)
    }

    // MARK: golden tip

    static func goldenTipValue(_ s: GameState) -> Double {
        max(600 * SalesEngine.incomeEstimate(s), 25)
    }
}
