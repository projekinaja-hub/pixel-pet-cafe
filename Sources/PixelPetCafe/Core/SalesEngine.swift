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
    static let baseRate = 0.08                 // customers/sec floor
    static let dirtPerSale = 0.4
    static let closedAfter: TimeInterval = 300 // unservable this long => closed
    /// Fame floor while closed — a shuttered café is forgotten, not hated.
    static let closedReputationFloor = 25.0
    /// customer species index -> preferred category (2x pick weight)
    static let preferences: [ItemCategory] = [.drink, .special, .pastry]

    // MARK: rates

    /// ECONOMY V2: strictly LINEAR equipment benefit — +6% to prices and
    /// customer flow per equipment level, summed across every piece of gear
    /// in the café. Bounded by the per-city level caps (25 at home up to 135
    /// on the Moon per item), so at the home cap (125 total levels) this is
    /// ×8.5 and at the moon cap (675 levels) ×41.5. Progression between
    /// scales comes from unlocking CITIES, not from any one stat compounding.
    static let equipBenefitPerLevel = 0.06
    static func equipMultiplier(_ s: GameState) -> Double {
        let totalLevels = Catalog.equipment.reduce(0) { $0 + (s.equipmentLevels[$1.id] ?? 0) }
        return 1 + equipBenefitPerLevel * Double(totalLevels)
    }

    /// Fast growth for the first `softCap` levels, then much slower (but
    /// never zero) growth beyond it — same principle as Chip's burst-past-
    /// cooldown-floor fix: a role should never go fully dead partway through
    /// the level range a fancier café's higher per-café cap (EconomyEngine.
    /// staffLevelCap) now lets you reach. Levels used to hard min()-cap at
    /// exactly 25 with nothing beyond, so leveling Juno/Mocha/Poppy/Bo past
    /// 25 (routine once caps started going up to 135) did literally nothing.
    static let tieredBonusSoftCap = 25
    static let tieredBonusPerLevelAfterCap = 0.004
    static func tieredBonus(level: Int, perLevel: Double) -> Double {
        let capped = min(level, tieredBonusSoftCap)
        let extra = max(0, level - tieredBonusSoftCap)
        return perLevel * Double(capped) + tieredBonusPerLevelAfterCap * Double(extra)
    }

    /// ECONOMY V2: flat +5% per star on both prices and customer rate. Stars
    /// are already bounded (~200 for even absurd runs) by the LOGARITHMIC
    /// prestige formula (EconomyEngine.prestigeStars), so this tops out
    /// around ×11 with no taper needed — linear benefit on a log-bounded
    /// input can't snowball.
    static let starBonusPerLevel = 0.05
    static func starBonus(_ s: GameState) -> Double {
        starBonusPerLevel * Double(s.stars)
    }

    static func priceMultiplier(_ s: GameState) -> Double {
        equipMultiplier(s) * (1 + starBonus(s)) * s.city.priceBonus
            * (1 + tieredBonus(level: s.staffLevels["juno"] ?? 0, perLevel: 0.02))
            // permanent world-prestige bonus — see EconomyEngine.moveToNewCountry.
            // Survives every reset (renovate and world moves alike), unlike stars.
            * (1 + EconomyEngine.worldPermanentBonusPerVisit * Double(s.worldsVisited))
            * EconomyEngine.dailyStreakMultiplier(s)
            * (Holidays.today(s)?.priceBoost ?? 1.0)
    }

    /// Role bonuses: Mocha boosts drinks, Poppy boosts pastries (+4%/level,
    /// slower but ongoing growth past level 25 — see tieredBonus).
    static func categoryBonus(_ category: ItemCategory, _ s: GameState) -> Double {
        let rainBoost = category == .drink && Events.isActive("rain", s) ? 1.3 : 1.0
        switch category {
        case .drink:  return rainBoost * (1 + tieredBonus(level: s.staffLevels["mocha"] ?? 0, perLevel: 0.04))
        case .pastry: return 1 + tieredBonus(level: s.staffLevels["poppy"] ?? 0, perLevel: 0.04)
        case .special: return 1
        }
    }

    /// Bo the roaster: chance a sale consumes no ingredients (2%/level,
    /// slower but ongoing growth past level 25 — see tieredBonus — hard
    /// capped at 85% so ingredients never become fully pointless).
    static let freeSaleChanceCap = 0.85
    static func freeSaleChance(_ s: GameState) -> Double {
        min(freeSaleChanceCap, tieredBonus(level: s.staffLevels["bo"] ?? 0, perLevel: 0.02))
    }

    /// A more upgraded café burns through ingredients faster per sale, not just
    /// more often — busier equipment, bigger portions. +2% ingredients per
    /// average equipment level, so spending keeps pace with the earnings those
    /// same upgrades unlock (a fresh café — avg level 0 — is unaffected).
    static func consumptionMultiplier(_ s: GameState) -> Double {
        let ids = Catalog.equipment.map(\.id)
        let avgLevel = Double(ids.reduce(0) { $0 + (s.equipmentLevels[$1] ?? 0) }) / Double(ids.count)
        return 1 + 0.02 * avgLevel
    }

    /// Consumes `qty * consumptionMultiplier` per ingredient, rounding
    /// probabilistically (rather than always ceiling) so low-quantity recipes
    /// don't jump straight to double consumption the moment the multiplier
    /// ticks above 1 — the fractional part is the *chance* of the extra unit.
    private static func consume<R: RandomNumberGenerator>(
        _ ingredients: [String: Int], _ s: inout GameState, rng: inout R
    ) {
        let mult = consumptionMultiplier(s)
        for (ing, qty) in ingredients {
            let exact = Double(qty) * mult
            var amount = Int(exact)
            let frac = exact - Double(amount)
            // Skip the RNG draw entirely when there's no fractional part (mult == 1,
            // i.e. a fresh café with no equipment) so unrelated seeded tests that
            // don't care about consumption scaling see byte-identical RNG streams.
            if frac > 0, Double.random(in: 0..<1, using: &rng) < frac { amount += 1 }
            s.stock[ing, default: 0] -= amount
        }
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
            * (1 + starBonus(s))
            * s.city.rateBonus
            * realismFactor(s.reputation, floor: 0.05, power: 1.3)
            * (s.adsActive ? 1.8 : 1.0)
            * (Events.isActive("rush", s) ? 2.0 : 1.0)
            * (Events.isActive("rain", s) ? 0.7 : 1.0)
            * (Holidays.today(s)?.customerBoost ?? 1.0)
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
        Goals.recordProgress(&s, .researchTaste)
        return true
    }

    static func servable(_ s: GameState) -> [ResolvedItem] {
        MenuCatalog.resolve(s).filter { item in
            item.ingredients.allSatisfy { (s.stock[$0.key] ?? 0) >= $0.value }
        }
    }

    /// Display/tip estimate: expected coins/sec right now — honest about the
    /// throughput cap. Pure customerRate × avgPrice ignored that the capacity
    /// system (added this session) can bottleneck actual serving far below
    /// the arrival rate — the display could show trillions/sec while a
    /// chronically under-capacity café actually earned a small fraction of
    /// that. Now capped at whatever the kitchen can actually serve.
    static func incomeEstimate(_ s: GameState) -> Double {
        let items = servable(s)
        guard !items.isEmpty else { return 0 }
        let avg = items.reduce(0) { $0 + price($1, s) } / Double(items.count)
        let cap = capacityPerSec(s)
        // Net of staff wages — the header number must match what actually
        // lands in the wallet (same honesty rule as the capacity cap above).
        return min(customerRate(s), cap.isFinite ? cap : .infinity) * avg
            * (1 - EconomyEngine.wageShare(s))
    }

    // MARK: throughput / prep-time capacity

    /// One item's prep time right now: base seconds ÷ every relevant
    /// equipment's speed bonus, floored so nothing ever becomes ~instant.
    static func prepTime(_ item: ResolvedItem, _ s: GameState) -> Double {
        var t = PrepTime.base(item)
        for def in Catalog.equipment where def.speedCategories.contains(item.category) {
            let level = s.equipmentLevels[def.id] ?? 0
            if level > 0 { t /= pow(def.speedMultPerLevel, Double(level)) }
        }
        return max(1.5, t)
    }

    /// Hands-on serving staff — Mocha (barista), Poppy (pâtissier), Biscuit
    /// (waiter) — plus the Owner (baseline 2.0) always manning the counter.
    /// Also credits overall equipment investment (log-dampened, so it never
    /// runs away): a café that's poured everything into gear rather than
    /// those three specific hires shouldn't have throughput collapse to
    /// almost nothing — better tools let the same hands move faster too, not
    /// only cut prep time per item. Fresh café: 2.0 + 0.5(mocha) + 0.3·log2(2)
    /// ≈ 2.8, comfortably above baseline demand (unchanged from before this
    /// broadening — verified by testFreshCafeCapacityComfortablyExceedsBaselineDemand).
    static func serviceWorkers(_ s: GameState) -> Double {
        2.0
            + 0.5 * Double(s.staffLevels["mocha"] ?? 0)
            + 0.5 * Double(s.staffLevels["poppy"] ?? 0)
            + 0.5 * Double(s.staffLevels["biscuit"] ?? 0)
            + 0.3 * log2(1 + equipMultiplier(s))
    }

    /// Simple (unweighted) average prep time across the currently servable
    /// menu. `.infinity` when nothing is servable — a total stock-out is
    /// already handled by the existing "angry" mood, so it must not also
    /// register as a capacity bottleneck.
    static func avgPrepTime(_ s: GameState) -> Double {
        let items = servable(s)
        guard !items.isEmpty else { return .infinity }
        return items.reduce(0) { $0 + prepTime($1, s) } / Double(items.count)
    }

    /// Customers/sec the café can actually prep and serve right now, given
    /// its staff and the speed of its current menu. `.infinity` when nothing
    /// is servable (see `avgPrepTime`) — the cap simply doesn't apply then.
    static func capacityPerSec(_ s: GameState) -> Double {
        let t = avgPrepTime(s)
        guard t.isFinite else { return .infinity }
        return serviceWorkers(s) / t
    }

    // MARK: Delivery (late-game channel, unlocked at 10/12 cities)

    /// Flat multiplier on `customerRate` — composes with every existing rate
    /// multiplier (stars, rush, ads, city) rather than a parallel formula.
    static let deliveryDemandMultiplier = 400.0

    static func deliveryDemand(_ s: GameState) -> Double {
        guard s.deliveryUnlocked else { return 0 }
        return customerRate(s) * deliveryDemandMultiplier
    }

    /// Delivery platform fee — a distinct, slightly-discounted revenue line.
    static let deliveryFeeRetained = 0.85

    /// ECONOMY V2: delivery gets its OWN capacity slice — 35% of the tick's
    /// kitchen capacity, computed independently rather than from walk-ins'
    /// leftover slots. Under the old leftover rule, any café whose walk-in
    /// demand exceeded capacity had literally zero slots left over, so
    /// delivery never filled a single order — precisely the late-game state
    /// delivery is meant for. Walk-ins still get the FULL original capacity
    /// (an intentional kitchen overcommit).
    static let deliveryCapacityShare = 0.35

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
        // Calendar and market prices are both chain-wide (not per café), so
        // advance/drift once per tick rather than once per owned café.
        GameCalendar.advance(&s, now: now)
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
        let repBefore = s.reputation
        for i in s.cafes.indices {
            s.activeCafe = i
            let events = tickOneCafe(&s, dt: dt, now: now, boost: i == viewedCafe ? boost : 1, rng: &rng)
            if i == viewedCafe { viewedEvents = events }
        }
        s.activeCafe = viewedCafe
        applyReputationPhysics(&s, before: repBefore, dt: dt)
        return viewedEvents
    }

    // MARK: reputation physics

    /// Reputation used to pin at 100 within seconds: every happy sale added
    /// up to +0.3, up to 20 sales/tick/café across 6 cafés (~+10/sec) with
    /// nothing pulling it back down — a dead mechanic. Now it behaves like
    /// FAME: (a) per-sale gains still accrue, but the total upward movement
    /// per real second is capped, so raw sales volume can't brute-force it;
    /// (b) above the baseline it decays back toward it — standing still
    /// means fading. Perfect, continuous service equilibrates around ~95
    /// (gainCap / decayRate + baseline); reaching a true 100 takes the
    /// extra pushes (critic raves, ads, events). Drops (angry customers,
    /// stock-outs) remain instant and uncapped, so bad service still bites.
    static let reputationGainCapPerSec = 0.05
    static let reputationDecayPerSec = 0.0011
    static let reputationBaseline = 50.0

    private static func applyReputationPhysics(_ s: inout GameState, before: Double, dt: TimeInterval) {
        let gained = s.reputation - before
        if gained > 0 {
            s.reputation = before + min(gained, reputationGainCapPerSec * dt)
        }
        if s.reputation > reputationBaseline {
            let decay = (s.reputation - reputationBaseline) * reputationDecayPerSec * dt
            s.reputation = max(reputationBaseline, s.reputation - decay)
        }
    }

    private static func tickOneCafe<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, now: Date, boost: Double, rng: inout R
    ) -> [SaleEvent] {
        managerRestock(&s)
        janitorClean(&s, dt: dt)
        if isClosed(s, now: now) {
            // A closed café loses fame slowly — but floored, and nobody
            // walks into a closed café, so no arrivals and no angry dings.
            // Previously customers kept "arriving" at an unservable café and
            // each one dinged reputation −2, grinding a new player's rep to
            // 0 within an unattended hour of starter stock running out — a
            // trap: with rep 0, recovery after restocking was glacial. The
            // floor (25) keeps a comeback story: restock and rebuild.
            s.reputation = max(closedReputationFloor, s.reputation - 0.01 * dt)
            s.customerProgress = 0
            return []
        }
        s.customerProgress += customerRate(s) * boost * dt
        var events: [SaleEvent] = []
        let stockBeforeServing = s.stock
        let coinsBeforeServing = s.coins

        // Throughput cap: how many customers this café's staff can actually
        // prep/serve this tick. `max(1.0, ...)` floors it at one guaranteed
        // serve-slot per tick — the single-arrival-per-tick idiom used
        // throughout the test suite (fresh copy, customerProgress = 1,
        // dt ≈ 0.001) always clears this floor untouched, so the cap only
        // ever binds when MORE than one customer's worth of progress
        // accumulates within a single tick: large dt (offline-style catch
        // up), rush/ads stacking pushing customerRate*dt > 1, or a Delivery
        // burst below — precisely the "kitchen can't keep up" moment.
        // `boost` (Work Mode's typing-speed multiplier) speeds up service
        // throughput the same way it speeds up customer arrivals — you
        // typing faster reads as you actively working the counter faster,
        // not just more people walking in the door.
        let capacityThisTick = capacityPerSec(s).isFinite
            ? max(1.0, capacityPerSec(s) * boost * dt + s.cafe.serviceBuffer)
            : Double.infinity
        var slotsLeft = capacityThisTick
        let hardStop = 2000.0   // bulk past this instead of looping per-customer
        var loops = 0.0
        var capacityBlocked = 0.0

        while s.customerProgress >= 1, loops < hardStop {
            s.customerProgress -= 1
            loops += 1
            if slotsLeft < 1 {
                // Capacity exhausted this tick — the kitchen genuinely can't
                // keep up, so the customer walks rather than waits. Distinct
                // from the existing stock-out sadLeave: servable(s) is
                // non-empty here, it's just too slow. The reputation ding for
                // this is applied ONCE, capped, after the loop (see below) —
                // not per-iteration, which could otherwise ding reputation
                // hundreds of times in one tick for a chronically
                // under-capacity café and pin it at 0 permanently.
                if events.count < 20 {
                    events.append(SaleEvent(itemIcon: "", itemName: "", price: 0, mood: .sadLeave,
                                             customerSpecies: Int.random(in: 0...2, using: &rng), dineIn: false))
                }
                capacityBlocked += 1
                continue
            }
            slotsLeft -= 1
            events.append(serveCustomer(&s, now: now, rng: &rng))
            if events.count >= 20 { s.customerProgress = 0; break }  // sanity cap per tick
        }
        // No reputation ding for capacity-blocking (tried -5/tick, then
        // -0.3/tick — both still pinned reputation at 0 forever for a café
        // whose demand chronically outpaces capacity by a large factor,
        // since this fires every single tick and even a small per-tick cap
        // beats out happy-sale recovery at extreme mismatches). Being
        // capacity-blocked already has a real, sufficient economic cost:
        // zero revenue on every blocked customer. Reputation now responds
        // only to service quality (happy/settled/sadLeave/angry), not to
        // how fast the kitchen physically is — table seating (noTable) is
        // the same kind of hard-capped resource, so it's excluded too.
        if s.customerProgress >= 1 {
            // Extreme burst (e.g. Delivery-scale under-capacity): resolve the
            // remainder in bulk rather than looping further.
            s.customerProgress = 0
        }
        s.cafe.serviceBuffer = slotsLeft.isFinite ? max(0.0, min(1.0, slotsLeft)) : 0

        // Delivery: fills against its own dedicated capacity slice (35% of
        // this tick's kitchen capacity) — NOT walk-ins' leftovers, which are
        // zero exactly when delivery matters most. See deliveryCapacityShare.
        if s.deliveryUnlocked {
            let deliveryCapacity = capacityThisTick.isFinite
                ? deliveryCapacityShare * capacityThisTick
                : 0
            let demandThisTick = deliveryDemand(s) * dt
            let filled = min(demandThisTick, deliveryCapacity)
            let missed = max(0, demandThisTick - filled)
            if filled > 0 {
                let items = servable(s)
                if !items.isEmpty {
                    let avgPrice = items.reduce(0) { $0 + price($1, s) } / Double(items.count)
                    let earned = filled * avgPrice * deliveryFeeRetained
                    s.coins += earned
                    s.lifetimeCoins += earned
                    s.lifetimeCoinsThisRun += earned
                    s.cafe.deliveryOrdersServed += filled
                }
            }
            s.cafe.deliveryOrdersMissed += missed
        }

        // Staff wages: the roster takes its cut of everything this café just
        // earned (walk-ins and delivery alike). Staff were previously pure
        // upside — a one-time hire cost, then permanent free bonuses — which
        // is a big part of why the economy snowballed. Now a big roster is a
        // real tradeoff: more levels, bigger cut (see EconomyEngine.wageShare,
        // capped so it never exceeds a quarter of gross).
        let earnedThisTick = s.coins - coinsBeforeServing
        if earnedThisTick > 0 {
            s.coins -= earnedThisTick * EconomyEngine.wageShare(s)
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
        // Shares managerRestock's own target so the buffer floor and the
        // manager's actual restock goal can never fight each other into a
        // buy/spoil loop.
        let managerFloor = Double(managerTarget(s))
        for ing in MenuCatalog.ingredients {
            let before = stockBeforeServing[ing.id] ?? 0
            let after = s.stock[ing.id] ?? 0
            let consumed = max(0, before - after)
            let rate = Double(consumed) / dt
            var ema = s.cafe.consumptionEMA[ing.id] ?? 0
            ema = ema * (1 - alpha) + rate * alpha
            s.cafe.consumptionEMA[ing.id] = ema

            let buffer = max(spoilageMinBuffer, max(managerFloor, ema * spoilageBufferSeconds))
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
            // No reputation ding here — same reasoning as the kitchen
            // throughput cap below: table count is a hard-capped resource
            // (maxTables tops out at 6) while customerRate scales with
            // staff levels, so at high levels dine-in demand permanently
            // and unavoidably outstrips seating. A per-event ding here
            // reproduces the exact "reputation pinned at 0 forever" bug
            // already fixed for kitchen capacity, just via table seating
            // instead — a customer who can't get a table already generates
            // zero revenue, which is already the real cost.
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
            consume(chosen.ingredients, &s, rng: &rng)
        }
        // 2% of customers are big spenders paying 10× — the core-loop jackpot
        let whale = Double.random(in: 0..<1, using: &rng) < 0.02
        let earned = price(chosen, s) * (whale ? 10 : 1)
        s.coins += earned
        s.lifetimeCoins += earned
        s.lifetimeCoinsThisRun += earned
        s.cleanliness = max(0, s.cleanliness - dirtPerSale)
        s.salesCount[chosen.id, default: 0] += 1
        if let goalKind = Goals.kindForCategory(chosen.category) { Goals.recordProgress(&s, goalKind) }
        if whale { Goals.recordProgress(&s, .bigSpender) }
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
        // Calendar tracks real wall-clock time regardless of the offline
        // earnings cap below, so a multi-day gap still lands on the right
        // season even though the earnings catch-up window is bounded.
        GameCalendar.advance(&s)
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
        janitorClean(&s, dt: window)
        let cap = capacityPerSec(s)
        let demanded = Int(customerRate(s) * window)
        var customers = cap.isFinite ? min(demanded, Int(cap * window)) : demanded
        var haul = 0.0
        var safety = 250_000
        while customers > 0, safety > 0 {
            let options = servable(s)
            if options.isEmpty {
                managerRestock(&s)
                if servable(s).isEmpty { break }
                continue
            }
            let mult = consumptionMultiplier(s)
            for item in options {
                guard customers > 0 else { break }
                for (ing, qty) in item.ingredients {
                    s.stock[ing, default: 0] -= Int((Double(qty) * mult).rounded())
                }
                haul += price(item, s)
                customers -= 1
                safety -= 1
            }
        }
        // Wages come out of offline earnings the same as live ones — the
        // roster doesn't work the away shift for free.
        haul *= (1 - EconomyEngine.wageShare(s))
        s.coins += haul
        s.lifetimeCoins += haul
        s.lifetimeCoinsThisRun += haul
        s.cleanliness = max(0, s.cleanliness - 0.05 * Double(Int(customerRate(s) * window)))
        if haul > 0 { s.lastSaleAt = Date() }
        unlockNewMenuItems(&s)
        return haul
    }

    // MARK: manager (Marble) auto-restock

    /// Marble's restock target: `refillThreshold` (0...1, player-configurable,
    /// default 1.0) of the café's storage cap — never above the cap, so the
    /// cap is a hard upper bound on what the manager will ever hold. Requires
    /// at least one level of Marble hired (level only gates whether the
    /// manager acts at all; the target itself no longer scales with level).
    static func managerTarget(_ s: GameState) -> Int {
        guard (s.staffLevels["marble"] ?? 0) > 0 else { return 0 }
        let cap = EconomyEngine.storageCap(s)
        return min(cap, Int((Double(cap) * s.cafe.refillThreshold).rounded()))
    }

    /// Keeps every ingredient stocked up to `managerTarget`, buying up to
    /// 25-unit packs at a time with the player's coins, never past the target
    /// (which itself never exceeds the storage cap).
    static func managerRestock(_ s: inout GameState) {
        let target = managerTarget(s)
        guard target > 0 else { return }
        for ing in MenuCatalog.ingredients {
            var safety = 40
            while (s.stock[ing.id] ?? 0) < target, safety > 0 {
                let units = min(25, target - (s.stock[ing.id] ?? 0))
                guard units > 0 else { break }
                let cost = MenuCatalog.livePackCost(ing.id, units: units, s)
                guard s.coins >= cost else { return }
                s.coins -= cost
                s.stock[ing.id, default: 0] += units
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

    /// Buys a pack of 25 or 100 units. Returns false if unaffordable, or if
    /// the pack wouldn't fit under the café's storage cap — no partial fills,
    /// the whole pack must fit (buy storage first).
    @discardableResult
    static func buyPack(_ ingredient: String, units: Int, _ s: inout GameState) -> Bool {
        let cap = EconomyEngine.storageCap(s)
        guard (s.stock[ingredient] ?? 0) + units <= cap else { return false }
        let cost = packPrice(ingredient, units: units, s)
        guard s.coins >= cost, cost > 0 else { return false }
        s.coins -= cost
        s.stock[ingredient, default: 0] += units
        return true
    }

    /// Cleaning one dirt spot restores 15 cleanliness.
    static func cleanSpot(_ s: inout GameState) {
        s.cleanliness = min(100, s.cleanliness + 15)
        Goals.recordProgress(&s, .cleanCafe)
    }

    /// Uncapped, this scaled directly with income estimate, which itself
    /// compounds per equipment level — at deep late-game equipment (e.g. an
    /// espresso machine past level 40+) that made a single sweep cost tens of
    /// millions of coins, wildly disproportionate to what "sweeping the
    /// floor" should cost. Capped at a modest slice of your current balance
    /// so it always feels proportionate, at any stage of the game.
    static let sweepCostMaxShareOfCoins = 0.03
    static func sweepCost(_ s: GameState) -> Double {
        let raw = max(20, (incomeEstimate(s) * 60).rounded())
        return max(20, min(raw, (s.coins * sweepCostMaxShareOfCoins).rounded()))
    }

    /// Chip the cleaner: once hired, auto-cleans in discrete bursts on a
    /// cooldown — not a smooth continuous drip. The cooldown gets shorter
    /// every level, down to a hard floor (a cleaner literally cannot clean
    /// faster than once every 3s and still read as "a cleaner" rather than
    /// a cheat). Burst size keeps growing every level, floor or not, so
    /// leveling him past the cooldown floor still visibly does something
    /// instead of going dead — it used to just silently stop mattering once
    /// the cooldown bottomed out around level 13, which read as a bug
    /// ("upgrading Chip has no effect"). Free once hired — you already paid
    /// to hire and level him up, and an ongoing per-burst coin cost (even
    /// capped as a small % of your balance) kept reading as "cleaning is
    /// eating my money" at late-game scale. Manual Sweep All still costs
    /// coins (sweepCost) for players who haven't hired him.
    static let janitorBaseBurstAmount = 15.0
    static let janitorBurstAmountPerLevel = 0.4
    static let janitorBaseCooldown: TimeInterval = 20
    static let janitorCooldownPerLevel: TimeInterval = 1.5
    static let janitorMinCooldown: TimeInterval = 3

    static func janitorBurstAmount(level: Int) -> Double {
        janitorBaseBurstAmount + janitorBurstAmountPerLevel * Double(level - 1)
    }

    static func janitorCooldown(level: Int) -> TimeInterval {
        max(janitorMinCooldown, janitorBaseCooldown - janitorCooldownPerLevel * Double(level - 1))
    }

    private static func janitorClean(_ s: inout GameState, dt: TimeInterval) {
        let level = s.staffLevels["chip"] ?? 0
        guard level > 0, dt > 0, s.cleanliness < 100 else { return }
        s.chipCooldown -= dt
        guard s.chipCooldown <= 0 else { return }
        let amount = min(janitorBurstAmount(level: level), 100 - s.cleanliness)
        s.cleanliness += amount
        s.chipCooldown = janitorCooldown(level: level)
        Goals.recordProgress(&s, .cleanCafe)
    }

    @discardableResult
    static func sweepAll(_ s: inout GameState) -> Bool {
        let cost = sweepCost(s)
        guard s.coins >= cost, s.cleanliness < 100 else { return false }
        s.coins -= cost
        s.cleanliness = 100
        Goals.recordProgress(&s, .cleanCafe)
        return true
    }
}
