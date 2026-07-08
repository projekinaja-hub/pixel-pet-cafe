import Foundation

/// Global ingredient market: prices drift over real time via a small bounded
/// random walk, independent of which café you're viewing (this is player-wide
/// state, not per-café — see `GameState.marketPrices`). The point is to give
/// the Stock tab a reason to be checked between upgrade purchases: buying a
/// pack now vs. waiting for a dip becomes a genuine (small) decision instead
/// of a formality.
enum MarketEngine {
    /// Max fractional change per second of simulated time — tuned gentle:
    /// at 1.5%/sec a price can only wander from base to its 2x ceiling in
    /// ~46 seconds of one-directional luck, which is rare given the walk is
    /// symmetric; day-to-day it reads as a slow wobble, not a swing.
    static let driftPerSecond = 0.015
    /// Prices are clamped to this band around each ingredient's base unitCost.
    static let minMultiplier = 0.5
    static let maxMultiplier = 2.0
    /// Rolling sparkline sample count kept per ingredient (small — this is a
    /// compact popover graph, not a trading chart).
    static let historyLimit = 24

    /// Advances every ingredient's live price by one random-walk step and
    /// records a sparkline sample. Called once per simulation tick (not once
    /// per café — the market is shared across the whole chain).
    static func drift<R: RandomNumberGenerator>(
        _ s: inout GameState, dt: TimeInterval, rng: inout R
    ) {
        // Matches the dt clamp GameController already applies per tick, so a
        // long gap between ticks (e.g. after a hitch) can't cause one huge jump.
        let elapsed = max(0, min(dt, 5))
        guard elapsed > 0 else { return }
        for ing in MenuCatalog.ingredients {
            let base = ing.unitCost
            var current = s.marketPrices[ing.id] ?? base
            let pct = Double.random(in: -driftPerSecond...driftPerSecond, using: &rng) * elapsed
            current *= (1 + pct)
            current = min(base * maxMultiplier, max(base * minMultiplier, current))
            s.marketPrices[ing.id] = current

            var hist = s.priceHistory[ing.id] ?? [base]
            hist.append(current)
            if hist.count > historyLimit { hist.removeFirst(hist.count - historyLimit) }
            s.priceHistory[ing.id] = hist
        }
    }
}
