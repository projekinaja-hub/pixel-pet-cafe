import Foundation

/// All game rules as pure functions over `GameState`. No UI, no timers, no IO.
enum EconomyEngine {
    static let prestigeThreshold: Double = 1_000_000
    static let costGrowth: Double = 1.15
    static let baseOfflineCap: TimeInterval = 8 * 3600
    static let earlOfflineBonusPerLevel: TimeInterval = 3600

    // MARK: rates

    static func coinsPerSecond(_ s: GameState) -> Double {
        var base = 0.0
        for def in Catalog.staff {
            let level = s.staffLevels[def.id] ?? 0
            base += Double(level) * def.baseRate
        }
        var mult = 1.0
        for def in Catalog.equipment {
            let level = s.equipmentLevels[def.id] ?? 0
            if level > 0 { mult *= pow(def.multPerLevel, Double(level)) }
        }
        for id in s.unlockedRecipes {
            if let r = Catalog.recipeDef(id) { mult *= r.multiplier }
        }
        mult *= 1 + 0.10 * Double(s.stars)
        return base * mult
    }

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

    // MARK: mutations

    static func tick(_ s: inout GameState, dt: TimeInterval) {
        let earned = coinsPerSecond(s) * max(0, dt)
        s.coins += earned
        s.lifetimeCoins += earned
        s.lifetimeCoinsThisRun += earned
        for r in Catalog.recipes where s.lifetimeCoins >= r.unlockAtLifetime && !s.unlockedRecipes.contains(r.id) {
            s.unlockedRecipes.append(r.id)
        }
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

    // MARK: offline

    static func offlineCap(_ s: GameState) -> TimeInterval {
        baseOfflineCap + Double(s.staffLevels["earl"] ?? 0) * earlOfflineBonusPerLevel
    }

    static func offlineEarnings(_ s: GameState, elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return coinsPerSecond(s) * min(elapsed, offlineCap(s))
    }

    // MARK: prestige

    static func prestigeStars(_ s: GameState) -> Int {
        guard s.lifetimeCoinsThisRun >= prestigeThreshold else { return 0 }
        return Int(floor(sqrt(s.lifetimeCoinsThisRun / prestigeThreshold)))
    }

    static func canRenovate(_ s: GameState) -> Bool { prestigeStars(s) >= 1 }

    static func renovate(_ s: inout GameState) {
        guard canRenovate(s) else { return }
        s.stars += prestigeStars(s)
        s.coins = 0
        s.lifetimeCoinsThisRun = 0
        s.staffLevels = ["mocha": 1]
        s.equipmentLevels = [:]
        s.unlockedRecipes = []
    }

    // MARK: golden tip

    static func goldenTipValue(_ s: GameState) -> Double {
        max(600 * coinsPerSecond(s), 25)
    }
}
