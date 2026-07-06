import Foundation

struct SaleEvent: Equatable {
    let itemIcon: String
    let itemName: String
    let price: Double        // 0 when angry
    let angry: Bool
    let customerSpecies: Int // 0..2, picks the customer sprite
}

/// Deterministic RNG for testable simulation (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Customer-driven income simulation. Pure functions over GameState.
enum SalesEngine {
    static let baseRate = 0.05                 // customers/sec floor
    static let dirtPerSale = 0.4
    static let closedAfter: TimeInterval = 300 // unservable this long => closed
    /// customer species index -> preferred category (2x pick weight)
    static let preferences: [ItemCategory] = [.drink, .special, .pastry]

    // MARK: rates

    static func equipMultiplier(_ s: GameState) -> Double {
        var mult = 1.0
        for def in Catalog.equipment {
            let level = s.equipmentLevels[def.id] ?? 0
            if level > 0 { mult *= pow(def.multPerLevel, Double(level)) }
        }
        return mult
    }

    static func priceMultiplier(_ s: GameState) -> Double {
        equipMultiplier(s) * (1 + 0.10 * Double(s.stars)) * s.city.priceBonus
            * (1 + 0.02 * Double(s.staffLevels["juno"] ?? 0))
    }

    /// Role bonuses: Mocha boosts drinks, Poppy boosts pastries (+4%/level).
    static func categoryBonus(_ category: ItemCategory, _ s: GameState) -> Double {
        switch category {
        case .drink:  return 1 + 0.04 * Double(s.staffLevels["mocha"] ?? 0)
        case .pastry: return 1 + 0.04 * Double(s.staffLevels["poppy"] ?? 0)
        case .special: return 1
        }
    }

    /// Bo the roaster: chance a sale consumes no ingredients (2%/level, cap 50%).
    static func freeSaleChance(_ s: GameState) -> Double {
        min(0.5, 0.02 * Double(s.staffLevels["bo"] ?? 0))
    }

    static func customerRate(_ s: GameState) -> Double {
        let staffSum = Catalog.staff.reduce(0) { $0 + (s.staffLevels[$1.id] ?? 0) }
        return baseRate
            * (1 + 0.15 * Double(staffSum))
            * equipMultiplier(s)
            * (0.3 + 0.7 * s.cleanliness / 100)
            * (1 + 0.10 * Double(s.stars))
            * s.city.rateBonus
            * (0.5 + s.reputation / 100)
            * (s.adsActive ? 1.8 : 1.0)
    }

    static func price(_ item: ResolvedItem, _ s: GameState) -> Double {
        item.basePrice * priceMultiplier(s) * categoryBonus(item.category, s)
    }

    static func servable(_ s: GameState) -> [ResolvedItem] {
        MenuCatalog.resolve(s).filter { item in
            item.ingredients.allSatisfy { (s.stock[$0.key] ?? 0) >= $0.value }
        }
    }

    /// Display/tip estimate: expected coins/sec right now.
    static func incomeEstimate(_ s: GameState) -> Double {
        let items = servable(s)
        guard !items.isEmpty else { return 0 }
        let avg = items.reduce(0) { $0 + price($1, s) } / Double(items.count)
        return customerRate(s) * avg
    }

    static func hasStockOut(_ s: GameState) -> Bool {
        let all = MenuCatalog.resolve(s)
        guard !all.isEmpty else { return false }
        return servable(s).count < all.count
    }

    static func isClosed(_ s: GameState, now: Date = Date()) -> Bool {
        guard servable(s).isEmpty else { return false }
        guard let last = s.lastSaleAt else { return true }
        return now.timeIntervalSince(last) > closedAfter
    }

    static func dirtSpots(_ s: GameState) -> Int {
        min(5, Int((100 - s.cleanliness) / 20))
    }

    // MARK: live tick

    /// `boost` multiplies the customer flow (work-mode typing boost).
    static func tick<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, now: Date = Date(), boost: Double = 1,
        rng: inout R
    ) -> [SaleEvent] {
        guard dt > 0 else { return [] }
        managerRestock(&s)
        if s.adsActive {
            let cost = 0.25 * incomeEstimate(s) * dt
            if s.coins >= cost, cost > 0 {
                s.coins -= cost
                s.reputation = min(100, s.reputation + 0.005 * dt)
            } else {
                s.adsActive = false     // campaign ends when you can't pay
            }
        }
        if isClosed(s, now: now) {
            s.reputation = max(0, s.reputation - 0.01 * dt)
        }
        s.customerProgress += customerRate(s) * boost * dt
        var events: [SaleEvent] = []
        while s.customerProgress >= 1 {
            s.customerProgress -= 1
            events.append(serveCustomer(&s, now: now, rng: &rng))
            if events.count >= 20 { s.customerProgress = 0; break }  // sanity cap per tick
        }
        return events
    }

    private static func serveCustomer<R: RandomNumberGenerator>(
        _ s: inout GameState, now: Date, rng: inout R
    ) -> SaleEvent {
        let species = Int.random(in: 0...2, using: &rng)
        let options = servable(s)
        guard !options.isEmpty else {
            s.reputation = max(0, s.reputation - 2)   // word gets around
            return SaleEvent(itemIcon: "", itemName: "", price: 0, angry: true, customerSpecies: species)
        }
        // preference: preferred category counts double
        let preferred = preferences[species]
        var weighted: [(ResolvedItem, Double)] = options.map { ($0, $0.category == preferred ? 2.0 : 1.0) }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &rng)
        var chosen = weighted[0].0
        for (item, w) in weighted {
            if roll < w { chosen = item; break }
            roll -= w
        }
        weighted = []
        // serve: consume + earn + dirty up (Bo sometimes roasts for free)
        if Double.random(in: 0..<1, using: &rng) >= freeSaleChance(s) {
            for (ing, qty) in chosen.ingredients {
                s.stock[ing, default: 0] -= qty
            }
        }
        let earned = price(chosen, s)
        s.coins += earned
        s.lifetimeCoins += earned
        s.lifetimeCoinsThisRun += earned
        s.cleanliness = max(0, s.cleanliness - dirtPerSale)
        s.reputation = min(100, s.reputation + 0.05)
        s.lastSaleAt = now
        unlockNewMenuItems(&s)
        return SaleEvent(itemIcon: chosen.icon, itemName: chosen.name, price: earned,
                         angry: false, customerSpecies: species)
    }

    static func unlockNewMenuItems(_ s: inout GameState) {
        for def in MenuCatalog.items
        where s.lifetimeCoins >= def.unlockAtLifetime && !s.menuEnabled.contains(def.id) {
            s.menuEnabled.append(def.id)
        }
    }

    // MARK: offline bulk sim

    /// Simulates the away window: customers served round-robin across servable
    /// items until stock runs out or the time cap is reached. Mutates stock,
    /// coins, cleanliness. Returns the haul.
    static func offlineSim(_ s: inout GameState, elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        let window = min(elapsed, EconomyEngine.offlineCap(s))
        managerRestock(&s)
        var customers = Int(customerRate(s) * window)
        var haul = 0.0
        var safety = 250_000
        while customers > 0, safety > 0 {
            let options = servable(s)
            if options.isEmpty {
                managerRestock(&s)
                if servable(s).isEmpty { break }
                continue
            }
            for item in options {
                guard customers > 0 else { break }
                for (ing, qty) in item.ingredients { s.stock[ing, default: 0] -= qty }
                haul += price(item, s)
                customers -= 1
                safety -= 1
            }
        }
        s.coins += haul
        s.lifetimeCoins += haul
        s.lifetimeCoinsThisRun += haul
        s.cleanliness = max(0, s.cleanliness - 0.05 * Double(Int(customerRate(s) * window)))
        if haul > 0 { s.lastSaleAt = Date() }
        unlockNewMenuItems(&s)
        return haul
    }

    // MARK: manager (Marble) auto-restock

    /// Keeps every ingredient stocked at ≥ 10 × Marble's level, buying 25-packs
    /// with the player's coins.
    static func managerRestock(_ s: inout GameState) {
        let level = s.staffLevels["marble"] ?? 0
        guard level > 0 else { return }
        let target = 10 * level
        for ing in MenuCatalog.ingredients {
            var safety = 40
            while (s.stock[ing.id] ?? 0) < target, safety > 0 {
                let cost = MenuCatalog.packCost(ing.id, units: 25)
                guard s.coins >= cost else { return }
                s.coins -= cost
                s.stock[ing.id, default: 0] += 25
                safety -= 1
            }
        }
    }

    // MARK: player actions

    /// Buys a pack of 25 or 100 units. Returns false if unaffordable.
    @discardableResult
    static func buyPack(_ ingredient: String, units: Int, _ s: inout GameState) -> Bool {
        let cost = MenuCatalog.packCost(ingredient, units: units)
        guard s.coins >= cost, cost > 0 else { return false }
        s.coins -= cost
        s.stock[ingredient, default: 0] += units
        return true
    }

    /// Cleaning one dirt spot restores 15 cleanliness.
    static func cleanSpot(_ s: inout GameState) {
        s.cleanliness = min(100, s.cleanliness + 15)
    }

    static func sweepCost(_ s: GameState) -> Double {
        max(20, (incomeEstimate(s) * 60).rounded())
    }

    @discardableResult
    static func sweepAll(_ s: inout GameState) -> Bool {
        let cost = sweepCost(s)
        guard s.coins >= cost, s.cleanliness < 100 else { return false }
        s.coins -= cost
        s.cleanliness = 100
        return true
    }
}
