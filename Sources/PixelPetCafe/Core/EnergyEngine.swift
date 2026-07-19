import Foundation

/// TYPING ENERGY: real-world keystrokes (counted system-wide, never read)
/// are the fuel that powers the café. The tank fills as you type anywhere on
/// your Mac and burns constantly while the café runs; an empty tank drops the
/// whole café to a crawl. Pure functions/constants only — GameController owns
/// the key monitor, the tick timing, and all wiring.
enum EnergyEngine {
    static let energyCap = 6000.0
    static let energyPerKeystroke = 1.0
    static let burnPerSec = 0.5
    /// Empty tank: the café limps along at this fraction of normal speed.
    static let crawlFactor = 0.25
    /// Typing live on top of a non-empty tank adds up to this much bonus speed…
    static let liveBonusMax = 0.5
    /// …with the full bonus reached at this sustained keys/sec.
    static let liveBonusFullAtKps = 4.0

    static let rushCost = 1000.0
    static let restockCost = 2000.0

    /// The café-wide speed multiplier (customer arrivals AND service capacity,
    /// via SalesEngine.tick's `boost:`). Empty tank = crawl, no live bonus.
    static func speedFactor(energy: Double, kps: Double) -> Double {
        guard energy > 0 else { return crawlFactor }
        return 1.0 + min(liveBonusMax, liveBonusMax * kps / liveBonusFullAtKps)
    }

    /// Spend ⚡ to start a 5-minute "rush" event (×2 customers). Pure GameState
    /// mutation — GameController wraps it with banner/sound/celebrate.
    /// Refused (returns false, deducts nothing) when the tank can't afford it
    /// or another event is genuinely still running.
    static func applyRush(_ s: inout GameState, now: Date) -> Bool {
        if let ends = s.eventEndsAt, now > ends {          // expire stale event
            s.activeEvent = nil
            s.eventEndsAt = nil
        }
        guard s.energy >= rushCost, s.activeEvent == nil else { return false }
        s.energy -= rushCost
        s.activeEvent = "rush"
        s.eventEndsAt = now.addingTimeInterval(300)
        return true
    }

    /// Spend ⚡ to fill every ingredient in the active café straight to the
    /// storage cap. Refused (returns false, deducts nothing) when unaffordable.
    static func applyRestock(_ s: inout GameState) -> Bool {
        guard s.energy >= restockCost else { return false }
        s.energy -= restockCost
        let cap = EconomyEngine.storageCap(s)
        for ing in MenuCatalog.ingredients {
            s.stock[ing.id] = max(s.stock[ing.id] ?? 0, cap)
        }
        return true
    }
}
