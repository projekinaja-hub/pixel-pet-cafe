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

    // MARK: live typing speed

    /// Ceiling on keys credited per second. Caps the catch-up after a stalled
    /// timer or a sleep so a long gap can't dump an hour of typing in at once.
    static let maxKeysPerSecond = 20.0
    /// How fast the speed reading climbs while typing (seconds to ~63%)…
    static let riseTau = 0.45
    /// …and how gently it falls, so the meter doesn't strobe between words.
    static let fallTau = 1.8

    /// Keys we're willing to credit for a counter jump of `delta` over `dt`.
    static func creditedKeys(delta: Double, dt: Double) -> Double {
        guard delta > 0, dt > 0 else { return 0 }
        return min(delta, maxKeysPerSecond * dt)
    }

    /// One step of the live typing-speed filter, in keys/sec.
    ///
    /// Asymmetric on purpose: springs UP fast so the café reacts within a
    /// keystroke or two, eases DOWN slowly so brief pauses between words don't
    /// make the meter flicker. The previous approach averaged a flat 10-second
    /// window, which meant real typing at 50 WPM read as ~5 WPM for the first
    /// second and took ~3 seconds just to cross the lowest animation threshold.
    static func nextKps(current: Double, creditedKeys: Double, dt: Double) -> Double {
        guard dt > 0 else { return current }
        let instant = creditedKeys / dt
        let tau = instant > current ? riseTau : fallTau
        return max(0, current + (instant - current) * (1 - exp(-dt / tau)))
    }

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
