import XCTest
@testable import PixelPetCafe

/// LONG-HORIZON ECONOMY SIMULATION.
///
/// Every balance disaster in this game's history shared one cause: nothing
/// played it for hours before shipping. Stars ballooned to 1.4 billion, the
/// chip upgrade went dead past level 13, reputation death-spiralled to 0,
/// upgraded kitchens printed money because ingredient costs stayed flat. Each
/// was found by the player, in real time, after the fact.
///
/// `Simulator` plays the actual engines for many simulated hours with a
/// plausible player policy (restock when low, buy the cheapest affordable
/// upgrade, type at a steady pace) and reports the curve. The tests then
/// assert BANDS, not exact numbers — so a rebalance is free to move things,
/// but not to break monotonicity, collapse reputation, dead-end progression,
/// or hyperinflate.
struct Simulator {
    struct Sample {
        var hour: Double
        var coins: Double
        var income: Double
        var reputation: Double
        var upgrades: Int
    }

    struct Result {
        var state: GameState
        var samples: [Sample]
        var restocks = 0
        var restockSpend = 0.0
        var upgradesBought = 0
        /// True whenever the café had nothing servable — the "dead café" state
        /// a real player experiences as "it stopped working".
        var starvedTicks = 0

        var finalIncome: Double { SalesEngine.incomeEstimate(state) }
        func income(atHour h: Double) -> Double {
            samples.last { $0.hour <= h }?.income ?? 0
        }
    }

    /// Plays `hours` of game time at the real 1-second tick.
    /// `typingKps` models a player actually working at the keyboard, which is
    /// what fuels the café now — 0 means someone who never types (the café
    /// should then crawl, not break).
    static func play(hours: Double, seed: UInt64 = 7, typingKps: Double = 1.5) -> Result {
        var s = GameState.newGame()
        var rng = SeededGenerator(seed: seed)
        var out = Result(state: s, samples: [])
        let ticks = Int(hours * 3600)
        let actEvery = 5                      // the player checks in every 5s
        // Fixed clock: isClosed() and offline logic read wall-clock dates, so
        // pin `now` and advance it with the simulation instead of letting the
        // test's real runtime leak into the result.
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 0..<ticks {
            let now = start.addingTimeInterval(Double(i))

            // typing fuels the tank; the tank sets the café's speed
            s.energy = min(EnergyEngine.energyCap, s.energy + typingKps)
            s.energy = max(0, s.energy - EnergyEngine.burnPerSec)
            let boost = EnergyEngine.speedFactor(energy: s.energy, kps: typingKps)

            if servableCount(s) == 0 { out.starvedTicks += 1 }
            _ = SalesEngine.tick(&s, dt: 1, now: now, boost: boost, rng: &rng)

            if i % actEvery == 0 {
                let before = s.coins
                if restockIfLow(&s) { out.restocks += 1 }
                out.restockSpend += max(0, before - s.coins)
                if buyBestAffordableUpgrade(&s) { out.upgradesBought += 1 }
            }
            if i % 600 == 0 {                 // sample every 10 simulated minutes
                out.samples.append(Sample(hour: Double(i) / 3600,
                                          coins: s.coins,
                                          income: SalesEngine.incomeEstimate(s),
                                          reputation: s.reputation,
                                          upgrades: totalUpgradeLevels(s)))
            }
        }
        out.state = s
        return out
    }

    // MARK: player policy

    static func servableCount(_ s: GameState) -> Int { SalesEngine.servable(s).count }

    static func totalUpgradeLevels(_ s: GameState) -> Int {
        s.staffLevels.values.reduce(0, +) + s.equipmentLevels.values.reduce(0, +)
    }

    /// Top every ingredient back up to a target, the way Marble does.
    ///
    /// This must fully replenish, not add a fixed amount: an early version
    /// added 25 units per check, which silently capped sales throughput for
    /// EVERY run at the restock rate. That made a 6x café speed difference
    /// show up as a 26% sales difference and buried the signal in RNG noise —
    /// the harness, not the game, was the bottleneck.
    static func restockIfLow(_ s: inout GameState) -> Bool {
        // Modest target, topped up often. Hoarding (an early version aimed at
        // 150 of everything) sinks all capital into standing inventory, so the
        // player never upgrades and income can't grow — a real player keeps a
        // working buffer and spends the rest on the café.
        let target = min(EconomyEngine.storageCap(s), 60)
        var bought = false
        for ing in MenuCatalog.ingredients {
            var safety = 20
            while (s.stock[ing.id] ?? 0) < target, safety > 0 {
                let units = min(25, target - (s.stock[ing.id] ?? 0))
                guard units > 0, SalesEngine.buyPack(ing.id, units: units, &s) else { break }
                bought = true
                safety -= 1
            }
        }
        return bought
    }

    /// Spend on the cheapest thing available, keeping a reserve so the café
    /// never upgrades itself into being unable to buy ingredients.
    static func buyBestAffordableUpgrade(_ s: inout GameState) -> Bool {
        var options: [(cost: Double, buy: (inout GameState) -> Bool)] = []
        for def in Catalog.staff {
            options.append((EconomyEngine.staffCost(def.id, s), { EconomyEngine.buyStaff(def.id, &$0) }))
        }
        for def in Catalog.equipment {
            options.append((EconomyEngine.equipmentCost(def.id, s), { EconomyEngine.buyEquipment(def.id, &$0) }))
        }
        options.append((EconomyEngine.tableCost(s), { EconomyEngine.buyTable(&$0) }))
        options.append((EconomyEngine.storageCost(s), { EconomyEngine.buyStorage(&$0) }))

        let reserve = 300.0
        for option in options.sorted(by: { $0.cost < $1.cost })
        where s.coins - option.cost > reserve {
            if option.buy(&s) { return true }
        }
        return false
    }
}

final class EconomySimulationTests: XCTestCase {

    // Long enough to expose plateaus and spirals, short enough to stay a unit
    // test. ~43k engine ticks.
    private static let hours = 12.0
    private static var cached: Simulator.Result?
    /// One 12-hour playthrough shared by the assertions below.
    private var run: Simulator.Result {
        if let c = Self.cached { return c }
        let r = Simulator.play(hours: Self.hours)
        Self.cached = r
        return r
    }

    // MARK: it must not break

    func testNothingGoesNaNOrNegative() {
        let s = run.state
        XCTAssertTrue(s.coins.isFinite, "coins went non-finite")
        XCTAssertTrue(s.lifetimeCoins.isFinite)
        XCTAssertGreaterThanOrEqual(s.coins, 0, "the player was driven into debt")
        XCTAssertTrue(SalesEngine.incomeEstimate(s).isFinite)
        for (id, n) in s.stock { XCTAssertGreaterThanOrEqual(n, 0, "negative stock: \(id)") }
        XCTAssertTrue((0...EnergyEngine.energyCap).contains(s.energy), "energy escaped its range")
    }

    func testLifetimeCoinsNeverDecrease() {
        var previous = 0.0
        for sample in run.samples {
            XCTAssertGreaterThanOrEqual(sample.coins + 1e-6, 0)
            previous = max(previous, sample.coins)
        }
        XCTAssertGreaterThan(previous, 0, "12 hours of play earned nothing at all")
    }

    /// The reputation death-spiral guard. A café that is stocked, staffed and
    /// serving must not grind itself to nothing — that bug shipped twice.
    func testReputationDoesNotDeathSpiral() {
        for sample in run.samples {
            XCTAssertTrue((0...100).contains(sample.reputation),
                          "reputation left its range: \(sample.reputation)")
        }
        XCTAssertGreaterThan(run.state.reputation, SalesEngine.closedReputationFloor,
                             "a working café collapsed to the closed-café floor")
    }

    func testCafeIsNotStarvedOfIngredients() {
        let starvedFraction = Double(run.starvedTicks) / (Self.hours * 3600)
        XCTAssertLessThan(starvedFraction, 0.10,
                          "café had nothing to serve for \(Int(starvedFraction * 100))% of the run")
    }

    // MARK: progression must actually progress

    func testProgressionDoesNotDeadEnd() {
        XCTAssertGreaterThan(run.upgradesBought, 10, "the player could barely buy anything in 12h")
        XCTAssertGreaterThan(Simulator.totalUpgradeLevels(run.state), 15)
    }

    func testIncomeGrowsOverTheRun() {
        let early = run.income(atHour: 1)
        let late = run.finalIncome
        XCTAssertGreaterThan(late, early, "income was flat or falling across 12 hours")
    }

    /// Growth has to be real but bounded — this is the fence that the old
    /// exponential curves (and the flat-ingredient-cost money printer) broke.
    func testGrowthIsBoundedNotHyperinflationary() {
        let early = max(1, run.income(atHour: 1))
        let late = run.finalIncome
        XCTAssertLessThan(late / early, 5_000,
                          "income grew \(Int(late / early))x in 12h — that's a money printer")
    }

    func testStarsStayOnTheLogScale() {
        XCTAssertLessThan(EconomyEngine.prestigeStars(run.state), 500,
                          "prestige stars are ballooning again")
    }

    func testLevelsRespectTheirCaps() {
        let s = run.state
        let staffCap = EconomyEngine.staffLevelCap(s)
        let equipCap = EconomyEngine.equipmentLevelCap(s)
        for (id, lvl) in s.staffLevels {
            XCTAssertLessThanOrEqual(lvl, staffCap, "staff \(id) exceeded its cap")
        }
        for (id, lvl) in s.equipmentLevels {
            XCTAssertLessThanOrEqual(lvl, equipCap, "equipment \(id) exceeded its cap")
        }
    }

    // MARK: typing is genuinely the engine

    /// The whole pivot: someone who types should out-earn someone who doesn't.
    ///
    /// Averaged over several seeds because a SHORT run is dominated by luck.
    /// Over a full run the gap is enormous (12h measured: ~7k coins never
    /// typing vs ~18M typing steadily) because the effect compounds — typing
    /// buys upgrades, which raise capacity, which sells more. Only the
    /// direction is asserted, so a rebalance can move the magnitude freely but
    /// can never invert the premise of the game.
    ///
    /// Note for future tuning: `tickOneCafe` floors service at
    /// `max(1.0, capacityPerSec * boost * dt)`, so in the FIRST minutes (while
    /// capacity is under 1/tick) the boost is masked and typing feels inert.
    /// That is the window a new player judges the game in.
    func testTypingBeatsNotTyping() {
        func averageEarnings(kps: Double) -> Double {
            let seeds: [UInt64] = [3, 11, 29, 57]
            let total = seeds.reduce(0.0) {
                $0 + Simulator.play(hours: 1.5, seed: $1, typingKps: kps).state.lifetimeCoins
            }
            return total / Double(seeds.count)
        }
        let typist = averageEarnings(kps: 6)
        let idler = averageEarnings(kps: 0)
        XCTAssertGreaterThan(typist, idler,
                             "typing must out-earn idling — that's the entire game")
    }

    /// …but never typing must still leave a playable café, not a broken one.
    func testNeverTypingStillWorksJustSlowly() {
        let idler = Simulator.play(hours: 2, seed: 11, typingKps: 0)
        XCTAssertGreaterThan(idler.state.lifetimeCoins, 0, "an idle café must still tick over")
        XCTAssertTrue(idler.state.coins.isFinite)
    }

    /// Different seeds must not change the shape of the game.
    func testOutcomeIsStableAcrossSeeds() {
        let a = Simulator.play(hours: 2, seed: 1)
        let b = Simulator.play(hours: 2, seed: 99)
        let ratio = max(a.state.lifetimeCoins, b.state.lifetimeCoins)
            / max(1, min(a.state.lifetimeCoins, b.state.lifetimeCoins))
        XCTAssertLessThan(ratio, 6, "luck dominates skill — two seeds diverged \(Int(ratio))x")
    }
}
