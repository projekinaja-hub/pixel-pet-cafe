import Foundation

/// Typing pays you directly, not just faster.
///
/// Energy already makes the café QUICKER — more customers, served sooner. This
/// makes typing worth MONEY on top, which is the thing the game is nominally
/// about and previously only rewarded second-hand.
///
/// It is a combo you keep alive, not a counter that only climbs. That
/// distinction is the whole design: a bonus that only accumulates is, at
/// ordinary typing speeds, a runaway. 1% per 10 keystrokes sounds modest until
/// you notice 48 WPM is 240 keystrokes a minute — +24%/min, +1,440%/hour,
/// +30,000% over a working day. Every upgrade, hire, city and prestige in the
/// game would be irrelevant inside a day, because none of them can compete
/// with a free number growing that fast.
///
/// Capped and decaying, the same 1%/10 keys instead becomes: type steadily and
/// climb to double money in about four minutes; stop and lose it over the next
/// hundred seconds. Stopping now costs something, which is the point of a
/// game about typing.
enum TypingCombo {
    /// Keystrokes per step of bonus.
    static let perKeystrokes = 10.0
    /// Percent added per step.
    static let percentPerStep = 1.0
    /// Hard ceiling, in percent. +100% = double money.
    static let maxPercent = 100.0
    /// Percent lost per second while not typing.
    static let decayPerSec = 1.0

    /// Advances the combo one tick.
    ///
    /// Keystrokes are credited even on a tick where typing has just stopped —
    /// they were genuinely typed — so gaining and decaying can both happen in
    /// the same step rather than one silently cancelling the other.
    static func next(current: Double, keystrokes: Int, dt: TimeInterval, typing: Bool) -> Double {
        guard dt > 0 else { return clamp(current) }
        var value = current + Double(max(0, keystrokes)) / perKeystrokes * percentPerStep
        if !typing {
            value -= decayPerSec * dt
        }
        return clamp(value)
    }

    private static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(maxPercent, max(0, v))
    }

    /// What every sale is multiplied by. 1.0 at rest, 2.0 at full combo.
    static func multiplier(percent: Double) -> Double {
        1.0 + clamp(percent) / 100.0
    }

    /// Keystrokes of sustained typing needed to reach the cap from nothing —
    /// used by the UI to explain the mechanic rather than leave it a mystery.
    static var keystrokesToCap: Int {
        Int((maxPercent / percentPerStep * perKeystrokes).rounded())
    }
}
