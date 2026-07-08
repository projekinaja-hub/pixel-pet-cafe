import Foundation

/// Rotating short-term goals: unlike `Achievements` (Events.swift, one-time
/// lifetime milestones), these are a small chase set that refreshes roughly
/// once per in-game day (see `GameCalendar`) — something to actively pursue
/// this session, not a permanent unlock.
enum GoalKind: String, Codable, CaseIterable {
    case serveDrinks, servePastries, serveSpecials
    case bigSpender
    case casinoWin
    case cleanCafe
    case cleanlinessStreak
    case researchTaste
    case upgradeEquipment
}

struct GoalDef {
    let kind: GoalKind
    let emoji: String
    let name: String
    let desc: String
    let target: Double
    /// Reward sized as roughly this many seconds of the café's current
    /// income estimate (locked in at spawn time — see `ActiveGoal.rewardCoins`).
    let rewardSeconds: Double
    let unlocked: (GameState) -> Bool

    func progressText(_ value: Double) -> String {
        switch kind {
        case .cleanlinessStreak:
            return "\(Int(min(value, target)))s / \(Int(target))s"
        default:
            return "\(Int(min(value, target)))/\(Int(target))"
        }
    }
}

/// A goal currently in rotation. `rewardCoins` is fixed the moment the goal
/// spawns so the payout doesn't drift as the café's income estimate changes
/// over the course of the day.
struct ActiveGoal: Codable, Equatable {
    var kind: GoalKind
    var progress: Double = 0
    var claimed: Bool = false
    var rewardCoins: Double = 0
}

enum Goals {
    /// 2-3 concurrent goals at any time, per design.
    static let activeCount = 3

    static let all: [GoalDef] = [
        GoalDef(kind: .serveDrinks, emoji: "☕", name: "Coffee Rush",
                desc: "Serve 15 drink orders", target: 15, rewardSeconds: 90,
                unlocked: { _ in true }),
        GoalDef(kind: .servePastries, emoji: "🥐", name: "Bakery Run",
                desc: "Serve 15 pastry orders", target: 15, rewardSeconds: 90,
                unlocked: { _ in true }),
        GoalDef(kind: .serveSpecials, emoji: "🍽", name: "Chef's Special",
                desc: "Serve 8 special orders", target: 8, rewardSeconds: 90,
                unlocked: { _ in true }),
        GoalDef(kind: .bigSpender, emoji: "💸", name: "Big Spender",
                desc: "Serve 1 big-spending customer (10× sale)", target: 1, rewardSeconds: 60,
                unlocked: { _ in true }),
        GoalDef(kind: .casinoWin, emoji: "🎰", name: "Lucky Streak",
                desc: "Win 3 casino games", target: 3, rewardSeconds: 120,
                unlocked: { $0.casinoUnlocked }),
        GoalDef(kind: .cleanCafe, emoji: "🧹", name: "Spring Cleaning",
                desc: "Clean the café 5 times", target: 5, rewardSeconds: 60,
                unlocked: { _ in true }),
        GoalDef(kind: .cleanlinessStreak, emoji: "✨", name: "Spotless",
                desc: "Keep cleanliness at 80+ for 5 minutes", target: 300, rewardSeconds: 90,
                unlocked: { _ in true }),
        GoalDef(kind: .researchTaste, emoji: "🔎", name: "Local Flavor",
                desc: "Research a city's tastes", target: 1, rewardSeconds: 150,
                unlocked: { s in !s.tasteKnown.contains(s.cafe.city) }),
        GoalDef(kind: .upgradeEquipment, emoji: "🧰", name: "Upgrade Day",
                desc: "Upgrade any piece of equipment", target: 1, rewardSeconds: 90,
                unlocked: { _ in true }),
    ]

    static func def(_ kind: GoalKind) -> GoalDef {
        // Safe force-unwrap: `all` is a static, exhaustive table covering
        // every GoalKind case — a lookup miss would be a programmer error.
        all.first { $0.kind == kind }!
    }

    /// item category -> matching goal kind, used at serve sites.
    static func kindForCategory(_ category: ItemCategory) -> GoalKind? {
        switch category {
        case .drink: return .serveDrinks
        case .pastry: return .servePastries
        case .special: return .serveSpecials
        }
    }

    /// Adds progress to every active, unclaimed goal of this kind, clamped to
    /// its target. Call sites are the natural spots where the underlying
    /// action already happens (a sale, a casino win, a clean, etc.) — this
    /// never drives behavior on its own.
    static func recordProgress(_ s: inout GameState, _ kind: GoalKind, amount: Double = 1) {
        for i in s.activeGoals.indices where s.activeGoals[i].kind == kind && !s.activeGoals[i].claimed {
            let target = def(s.activeGoals[i].kind).target
            s.activeGoals[i].progress = min(target, s.activeGoals[i].progress + amount)
        }
    }

    static func isComplete(_ goal: ActiveGoal) -> Bool {
        goal.progress >= def(goal.kind).target
    }

    /// Claims a completed goal's reward exactly once. Returns the coin
    /// amount granted (0 if the goal isn't found, isn't complete, or was
    /// already claimed).
    @discardableResult
    static func claim(_ s: inout GameState, _ kind: GoalKind) -> Double {
        guard let i = s.activeGoals.firstIndex(where: { $0.kind == kind }) else { return 0 }
        guard !s.activeGoals[i].claimed, isComplete(s.activeGoals[i]) else { return 0 }
        s.activeGoals[i].claimed = true
        let reward = s.activeGoals[i].rewardCoins
        s.coins += reward
        s.lifetimeCoins += reward
        s.lifetimeCoinsThisRun += reward
        return reward
    }

    private static func pick<R: RandomNumberGenerator>(_ n: Int, from defs: [GoalDef], rng: inout R) -> [GoalDef] {
        var pool = defs
        var result: [GoalDef] = []
        for _ in 0..<min(n, pool.count) {
            let idx = Int.random(in: 0..<pool.count, using: &rng)
            result.append(pool.remove(at: idx))
        }
        return result
    }

    /// Refreshes the rotating goal set once per in-game day (`GameCalendar`).
    /// A goal that was completed but never manually claimed is auto-awarded
    /// here rather than lost — the reward is small, and silently discarding
    /// progress a player already earned would feel punishing for missing a
    /// tap before the daily rollover. Returns the coin total auto-awarded
    /// (0 if nothing was pending, including the common case where the set
    /// doesn't need refreshing yet).
    @discardableResult
    static func refreshIfNeeded<R: RandomNumberGenerator>(
        _ s: inout GameState, now: Date = Date(), rng: inout R
    ) -> Double {
        let day = GameCalendar.currentDay(startedAt: s.calendarStartedAt, now: now)
        guard s.activeGoals.isEmpty || s.goalsDay != day else { return 0 }

        var autoAwarded = 0.0
        for goal in s.activeGoals where !goal.claimed && isComplete(goal) {
            autoAwarded += goal.rewardCoins
        }
        if autoAwarded > 0 {
            s.coins += autoAwarded
            s.lifetimeCoins += autoAwarded
            s.lifetimeCoinsThisRun += autoAwarded
        }

        let eligible = all.filter { $0.unlocked(s) }
        let picked = pick(activeCount, from: eligible, rng: &rng)
        let income = SalesEngine.incomeEstimate(s)
        s.activeGoals = picked.map { def in
            ActiveGoal(kind: def.kind, progress: 0, claimed: false,
                       rewardCoins: max(60, (income * def.rewardSeconds).rounded()))
        }
        s.goalsDay = day
        return autoAwarded
    }

    /// Convenience overload for normal (non-deterministic) gameplay call
    /// sites that don't need a seeded RNG.
    @discardableResult
    static func refreshIfNeeded(_ s: inout GameState, now: Date = Date()) -> Double {
        var rng = SystemRandomNumberGenerator()
        return refreshIfNeeded(&s, now: now, rng: &rng)
    }

    /// Deterministic initial population for brand-new games and legacy saves
    /// migrating in for the first time (called from `GameState.normalized()`).
    /// Unlike `refreshIfNeeded`, this doesn't roll randomly — it always takes
    /// the first `activeCount` eligible goals in table order — so two fresh
    /// `GameState.newGame()` calls stay equal (no hidden RNG divergence,
    /// mirroring how `calendarStartedAt` is the only other "constructed now"
    /// field, and it's excluded from equality instead). Day-to-day rotation
    /// once the game is actually running (`refreshIfNeeded`, driven from
    /// `GameController.tick`) is still fully randomized.
    static func seedInitialSet(_ s: inout GameState, now: Date = Date()) {
        guard s.activeGoals.isEmpty else { return }
        let eligible = all.filter { $0.unlocked(s) }
        let income = SalesEngine.incomeEstimate(s)
        s.activeGoals = eligible.prefix(activeCount).map { def in
            ActiveGoal(kind: def.kind, progress: 0, claimed: false,
                       rewardCoins: max(60, (income * def.rewardSeconds).rounded()))
        }
        s.goalsDay = GameCalendar.currentDay(startedAt: s.calendarStartedAt, now: now)
    }
}
