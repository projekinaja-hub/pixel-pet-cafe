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
    /// timer or a sleep so a long gap can't dump an hour of typing in at once,
    /// and blunts key auto-repeat (holding backspace fires ~15 keys/sec, which
    /// is not typing). 12 keys/sec is ~144 WPM — above any sustained human
    /// prose speed, so real typing is never clipped.
    static let maxKeysPerSecond = 12.0

    /// Trailing window the speed is measured over.
    ///
    /// This is what makes the number HONEST. The speed was once derived from a
    /// single 0.2s sample, so one keystroke read as 5 keys/sec — 60 WPM off
    /// one key, which is why a few casual taps looked like a sprint.
    ///
    /// The window also has to be long enough to average out BURSTS. People
    /// don't type at a steady rate: they fire 8–10 keys/sec inside a familiar
    /// word, then pause to think. A short window reports those bursts as your
    /// speed, so the meter reads far higher than the pace you feel yourself
    /// working at. Several seconds smooths a burst-and-pause rhythm into the
    /// sustained speed a typing test would report, while still being short
    /// enough to react while you're typing.
    static let rateWindow = 3.5
    /// How fast the displayed speed climbs toward the measured rate…
    static let riseTau = 0.5
    /// …and how gently it falls, so pauses between words don't make it strobe.
    static let fallTau = 1.5

    /// Keys we're willing to credit for a counter jump of `delta` over `dt`.
    static func creditedKeys(delta: Double, dt: Double) -> Double {
        guard delta > 0, dt > 0 else { return 0 }
        return min(delta, maxKeysPerSecond * dt)
    }

    /// How recently a key must have been pressed to count as "still typing".
    ///
    /// The café reacts to this, NOT to a WPM threshold. Those are two
    /// different questions — "are they typing right now?" (instant) and "how
    /// fast are they going?" (needs a few seconds of evidence). Gating the
    /// animation on a WPM number forced the speed measurement to be twitchy
    /// enough to trip a threshold in under a second, which is exactly what
    /// made the reported speed read far too high.
    static let typingRecency = 1.5

    static func isActivelyTyping(lastKeystrokeAt: Date?, now: Date) -> Bool {
        guard let last = lastKeystrokeAt else { return false }
        return now.timeIntervalSince(last) <= typingRecency
    }

    /// The measured typing rate: keys seen across the trailing window.
    static func windowedKps(keysInWindow: Double) -> Double {
        max(0, keysInWindow / rateWindow)
    }

    /// One step of the display filter, easing the shown speed toward the
    /// measured rate. Asymmetric on purpose: climbs quickly so the café reacts
    /// while you type, eases down slowly so brief pauses don't make it flicker.
    static func nextKps(current: Double, measured: Double, dt: Double) -> Double {
        guard dt > 0 else { return current }
        let tau = measured > current ? riseTau : fallTau
        return max(0, current + (measured - current) * (1 - exp(-dt / tau)))
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
