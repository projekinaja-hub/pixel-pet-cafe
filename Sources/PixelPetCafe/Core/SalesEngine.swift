import Foundation

enum CustomerMood: Equatable {
    case happy       // got what they wanted
    case settled     // wanted item unavailable, took something else
    case sadLeave    // wanted item unavailable, walked out
    case angry       // nothing servable at all
    case noTable     // wanted to dine in, every table was taken
}

struct SaleEvent: Equatable {
    let itemIcon: String
    let itemName: String
    let price: Double        // 0 when no sale
    let mood: CustomerMood
    let customerSpecies: Int // 0..2, picks the customer sprite
    var bigSpender: Bool = false   // rare 10× whale
    var dineIn: Bool = false       // sits at a table vs. grabs and goes
    var angry: Bool { mood == .angry }
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
            * min(1.5, 1 + 0.02 * Double(s.staffLevels["juno"] ?? 0))
    }

    /// Role bonuses: Mocha boosts drinks, Poppy boosts pastries (+4%/level).
    static func categoryBonus(_ category: ItemCategory, _ s: GameState) -> Double {
        let rainBoost = category == .drink && Events.isActive("rain", s) ? 1.3 : 1.0
        switch category {
        case .drink:  return rainBoost * min(2, 1 + 0.04 * Double(s.staffLevels["mocha"] ?? 0))
        case .pastry: return min(2, 1 + 0.04 * Double(s.staffLevels["poppy"] ?? 0))
        case .special: return 1
        }
    }

    /// Bo the roaster: chance a sale consumes no ingredients (2%/level, cap 50%).
    static func freeSaleChance(_ s: GameState) -> Double {
        min(0.5, 0.02 * Double(s.staffLevels["bo"] ?? 0))
    }

    /// Convex floor curve: a neglected café shouldn't coast on "half customers
    /// no matter what" — reputation/cleanliness in the gutter should read as
    /// genuinely dead, not just quieter.
    private static func realismFactor(_ x: Double, floor: Double, power: Double) -> Double {
        let t = max(0, min(1, x / 100))
        return floor + (1 - floor) * pow(t, power)
    }

    static func customerRate(_ s: GameState) -> Double {
        let staffSum = Catalog.staff.reduce(0) { $0 + (s.staffLevels[$1.id] ?? 0) }
        return baseRate
            * (1 + 0.08 * Double(staffSum))
            * pow(equipMultiplier(s), 0.5)      // gear helps flow, but gently
            * realismFactor(s.cleanliness, floor: 0.08, power: 1.2)
            * (1 + 0.10 * Double(s.stars))
            * s.city.rateBonus
            * realismFactor(s.reputation, floor: 0.05, power: 1.3)
            * (s.adsActive ? 1.8 : 1.0)
            * (Events.isActive("rush", s) ? 2.0 : 1.0)
            * (Events.isActive("rain", s) ? 0.7 : 1.0)
    }

    static func price(_ item: ResolvedItem, _ s: GameState) -> Double {
        item.basePrice * priceMultiplier(s) * categoryBonus(item.category, s)
            * (1 + 0.06 * Double(s.menuTaste[item.id] ?? 0))
    }

    // MARK: menu taste upgrades

    static let maxTaste = 10

    static func tasteUpgradeCost(_ item: ResolvedItem, _ s: GameState) -> Double {
        let level = s.menuTaste[item.id] ?? 0
        return (item.basePrice * 60 * pow(1.9, Double(level))).rounded()
    }

    @discardableResult
    static func upgradeTaste(_ itemId: String, _ s: inout GameState) -> Bool {
        guard let item = MenuCatalog.resolve(s).first(where: { $0.id == itemId })
                ?? allItems(s).first(where: { $0.id == itemId }),
              (s.menuTaste[itemId] ?? 0) < maxTaste else { return false }
        let cost = tasteUpgradeCost(item, s)
        guard s.coins >= cost else { return false }
        s.coins -= cost
        s.menuTaste[itemId, default: 0] += 1
        return true
    }

    static func allItems(_ s: GameState) -> [ResolvedItem] {
        MenuCatalog.items
            .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
            .map { ResolvedItem(id: $0.id, name: $0.name, icon: $0.icon, category: $0.category,
                                ingredients: $0.ingredients, basePrice: $0.basePrice, isCustom: false) }
        + s.customItems.map { ResolvedItem(id: $0.id, name: $0.name, icon: $0.icon, category: $0.category,
                                           ingredients: $0.ingredients, basePrice: MenuCatalog.customPrice($0), isCustom: true) }
    }

    // MARK: taste research (reveal a city's cravings)

    static func researchCost(_ s: GameState) -> Double {
        max(100, (incomeEstimate(s) * 1800).rounded())   // ~30 min of income
    }

    @discardableResult
    static func researchTaste(_ s: inout GameState) -> Bool {
        let city = s.cafe.city
        guard !s.tasteKnown.contains(city) else { return false }
        let cost = researchCost(s)
        guard s.coins >= cost else { return false }
        s.coins -= cost
        s.tasteKnown.append(city)
        return true
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
    ///
    /// Every owned café earns every tick, not just the one on screen —
    /// only the café you're currently viewing gets its events returned for
    /// animation; the rest sell quietly in the background. Ads are a single
    /// chain-wide campaign, so their cost/effect is computed once against
    /// the whole chain's income rather than per café.
    static func tick<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, now: Date = Date(), boost: Double = 1,
        rng: inout R
    ) -> [SaleEvent] {
        guard dt > 0 else { return [] }
        // Market prices are chain-wide (not per café), so drift once per tick
        // rather than once per owned café.
        MarketEngine.drift(&s, dt: dt, rng: &rng)
        let viewedCafe = s.activeCafe
        if s.adsActive {
            var totalIncome = 0.0
            for i in s.cafes.indices {
                s.activeCafe = i
                totalIncome += incomeEstimate(s)
            }
            let cost = 0.25 * totalIncome * dt
            if s.coins >= cost, cost > 0 {
                s.coins -= cost
                s.reputation = min(100, s.reputation + 0.005 * dt)
            } else {
                s.adsActive = false     // campaign ends when you can't pay
            }
        }
        var viewedEvents: [SaleEvent] = []
        for i in s.cafes.indices {
            s.activeCafe = i
            let events = tickOneCafe(&s, dt: dt, now: now, boost: i == viewedCafe ? boost : 1, rng: &rng)
            if i == viewedCafe { viewedEvents = events }
        }
        s.activeCafe = viewedCafe
        return viewedEvents
    }

    private static func tickOneCafe<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, now: Date, boost: Double, rng: inout R
    ) -> [SaleEvent] {
        managerRestock(&s)
        if isClosed(s, now: now) {
            s.reputation = max(0, s.reputation - 0.01 * dt)
        }
        s.customerProgress += customerRate(s) * boost * dt
        var events: [SaleEvent] = []
        let stockBeforeServing = s.stock
        while s.customerProgress >= 1 {
            s.customerProgress -= 1
            events.append(serveCustomer(&s, now: now, rng: &rng))
            if events.count >= 20 { s.customerProgress = 0; break }  // sanity cap per tick
        }
        updateConsumptionAndSpoilage(&s, stockBeforeServing: stockBeforeServing, dt: dt)
        return events
    }

    // MARK: spoilage

    /// How quickly the per-ingredient consumption estimate reacts to new
    /// data — a ~60s time constant so a single busy or quiet tick doesn't
    /// swing the buffer around.
    static let consumptionTimeConstant: TimeInterval = 60
    /// Stock below this is never spoiled, no matter how idle the café is —
    /// keeps early-game starter stock and casual buffer-stocking safe.
    static let spoilageMinBuffer = 150.0
    /// Buffer sized as this many seconds' worth of recent consumption (15
    /// minutes) — generous enough that normal restocking habits never trip it.
    static let spoilageBufferSeconds = 900.0
    /// Fraction of the excess (stock above the buffer) that spoils per
    /// second — slow enough to feel like "forgotten stock going stale," not
    /// a punishing drain.
    static let spoilageFraction = 0.01

    /// Spoils a small share of genuinely excess stock (well beyond what the
    /// café is actually using lately) and updates the rolling consumption
    /// estimate used to size that buffer. The buffer also never dips below
    /// what Marble's auto-restock is targeting, so the manager and spoilage
    /// can't fight each other into a buy/spoil loop.
    private static func updateConsumptionAndSpoilage(
        _ s: inout GameState, stockBeforeServing: [String: Int], dt: TimeInterval
    ) {
        guard dt > 0 else { return }
        let alpha = min(1, dt / consumptionTimeConstant)
        let managerTarget = Double(10 * (s.staffLevels["marble"] ?? 0))
        for ing in MenuCatalog.ingredients {
            let before = stockBeforeServing[ing.id] ?? 0
            let after = s.stock[ing.id] ?? 0
            let consumed = max(0, before - after)
            let rate = Double(consumed) / dt
            var ema = s.cafe.consumptionEMA[ing.id] ?? 0
            ema = ema * (1 - alpha) + rate * alpha
            s.cafe.consumptionEMA[ing.id] = ema

            let buffer = max(spoilageMinBuffer, max(managerTarget, ema * spoilageBufferSeconds))
            let current = Double(s.stock[ing.id] ?? 0)
            guard current > buffer else { continue }
            let excess = current - buffer
            let spoil = min(excess, excess * spoilageFraction * dt)
            let spoilUnits = Int(spoil.rounded(.down))
            if spoilUnits > 0 {
                s.stock[ing.id] = (s.stock[ing.id] ?? 0) - spoilUnits
            }
        }
    }

    /// Weight for how much this customer craves an item: city taste × species
    /// preference × how refined the recipe is.
    static func desireWeight(_ item: ResolvedItem, species: Int, _ s: GameState) -> Double {
        s.city.tasteWeight(item.category)
            * (item.category == preferences[species] ? 2.0 : 1.0)
            * (1 + 0.10 * Double(s.menuTaste[item.id] ?? 0))
    }

    private static func pickWeighted<R: RandomNumberGenerator>(
        _ options: [(ResolvedItem, Double)], rng: inout R
    ) -> ResolvedItem {
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (item, w) in options {
            if roll < w { return item }
            roll -= w
        }
        return options[0].0
    }

    /// Share of customers who want to sit rather than grab and go.
    static let dineInShare = 0.45
    /// Minutes a dine-in party occupies a table before it turns over.
    static let tableDwellMinutes = 0.75

    /// Chance a dine-in customer finds a free table right now, given how many
    /// tables the café has versus how much dine-in demand is arriving.
    static func tableAvailability(_ s: GameState) -> Double {
        let capacityPerMinute = Double(s.tables) / tableDwellMinutes
        let demandPerMinute = customerRate(s) * 60 * dineInShare
        guard demandPerMinute > 0 else { return 1 }
        return min(1, capacityPerMinute / demandPerMinute)
    }

    private static func serveCustomer<R: RandomNumberGenerator>(
        _ s: inout GameState, now: Date, rng: inout R
    ) -> SaleEvent {
        let species = Int.random(in: 0...2, using: &rng)
        let wantsDineIn = Double.random(in: 0..<1, using: &rng) < dineInShare
        if wantsDineIn, Double.random(in: 0..<1, using: &rng) >= tableAvailability(s) {
            s.reputation = max(0, s.reputation - 0.4)   // fixable by buying tables, so a lighter hit
            return SaleEvent(itemIcon: "", itemName: "", price: 0, mood: .noTable,
                             customerSpecies: species, dineIn: true)
        }
        let inStock = servable(s)
        guard !inStock.isEmpty else {
            s.reputation = max(0, s.reputation - 2)   // word gets around
            return SaleEvent(itemIcon: "", itemName: "", price: 0, mood: .angry,
                             customerSpecies: species, dineIn: wantsDineIn)
        }
        // the customer desires a specific item off the FULL menu
        let menu = MenuCatalog.resolve(s)
        let desired = pickWeighted(menu.map { ($0, desireWeight($0, species: species, s)) }, rng: &rng)
        let desiredAvailable = inStock.contains { $0.id == desired.id }

        var chosen = desired
        var mood = CustomerMood.happy
        if !desiredAvailable {
            // half settle for something else, half leave disappointed
            if Bool.random(using: &rng) {
                chosen = pickWeighted(inStock.map { ($0, desireWeight($0, species: species, s)) }, rng: &rng)
                mood = .settled
                s.reputation = max(0, s.reputation - 0.3)
            } else {
                s.reputation = max(0, s.reputation - 1)
                return SaleEvent(itemIcon: desired.icon, itemName: desired.name, price: 0,
                                 mood: .sadLeave, customerSpecies: species, dineIn: wantsDineIn)
            }
        }
        // serve: consume + earn + dirty up (Bo sometimes roasts for free)
        if Double.random(in: 0..<1, using: &rng) >= freeSaleChance(s) {
            for (ing, qty) in chosen.ingredients {
                s.stock[ing, default: 0] -= qty
            }
        }
        // 2% of customers are big spenders paying 10× — the core-loop jackpot
        let whale = Double.random(in: 0..<1, using: &rng) < 0.02
        let earned = price(chosen, s) * (whale ? 10 : 1)
        s.coins += earned
        s.lifetimeCoins += earned
        s.lifetimeCoinsThisRun += earned
        s.cleanliness = max(0, s.cleanliness - dirtPerSale)
        s.salesCount[chosen.id, default: 0] += 1
        if mood == .happy {
            // satisfaction: refined recipes and matching cravings build fame
            let sat = 60.0
                + 4 * Double(s.menuTaste[chosen.id] ?? 0)
                + 25 * (s.city.tasteWeight(chosen.category) - 1)
                + 0.15 * (s.cleanliness - 50)
            s.reputation = min(100, s.reputation + max(0.02, (sat - 55) / 250))
        }
        s.lastSaleAt = now
        unlockNewMenuItems(&s)
        return SaleEvent(itemIcon: chosen.icon, itemName: chosen.name, price: earned,
                         mood: mood, customerSpecies: species, bigSpender: whale, dineIn: wantsDineIn)
    }

    static func unlockNewMenuItems(_ s: inout GameState) {
        for def in MenuCatalog.items
        where s.lifetimeCoins >= def.unlockAtLifetime && !s.menuEnabled.contains(def.id) {
            s.menuEnabled.append(def.id)
        }
    }

    // MARK: offline bulk sim

    /// Simulates the away window across every owned café — customers served
    /// round-robin across servable items until stock runs out or the time cap
    /// is reached. Mutates stock, coins, cleanliness. Returns the total haul.
    static func offlineSim(_ s: inout GameState, elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        let viewedCafe = s.activeCafe
        var totalHaul = 0.0
        for i in s.cafes.indices {
            s.activeCafe = i
            totalHaul += offlineSimOneCafe(&s, elapsed: elapsed)
        }
        s.activeCafe = viewedCafe
        return totalHaul
    }

    private static func offlineSimOneCafe(_ s: inout GameState, elapsed: TimeInterval) -> Double {
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
                let cost = MenuCatalog.livePackCost(ing.id, units: 25, s)
                guard s.coins >= cost else { return }
                s.coins -= cost
                s.stock[ing.id, default: 0] += 25
                safety -= 1
            }
        }
    }

    // MARK: player actions

    /// Pack price off the live market price, with any live supplier deal
    /// applied on top.
    static func packPrice(_ ingredient: String, units: Int, _ s: GameState) -> Double {
        MenuCatalog.livePackCost(ingredient, units: units, s)
            * (Events.isActive("supplier", s) ? 0.5 : 1.0)
    }

    /// Buys a pack of 25 or 100 units. Returns false if unaffordable.
    @discardableResult
    static func buyPack(_ ingredient: String, units: Int, _ s: inout GameState) -> Bool {
        let cost = packPrice(ingredient, units: units, s)
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
