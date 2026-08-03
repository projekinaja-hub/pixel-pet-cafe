import Foundation

/// How fast the café animation must run for the picture to be an honest
/// account of what the café is actually selling.
///
/// The scene used to animate at ONE fixed pace: a full dine-in visit took
/// ~11.9s and at most 4 customers could be on screen, so it could depict at
/// most ~0.34 sales/sec — while a developed café sells many times that. Every
/// sale past the fourth was silently dropped, so a booming café and a barely
/// alive one looked exactly the same: four little animals ambling around.
///
/// Two dials fix that, in the order a real café would use them. First put more
/// bodies in the room (raise the on-screen cap), because a crowd is what
/// "busy" actually looks like. Only once the room is full, speed everyone up —
/// people genuinely do move faster during a rush, and walking pace is what
/// sells the difference.
///
/// Pure math, no SpriteKit, so the pacing curve is testable on its own.
enum CafePacing {
    /// One full dine-in visit at rest: fade in, walk to the counter, order,
    /// cross to a seat, sit, walk out, fade. Keep in step with the sequence in
    /// `CafeScene.playSale`.
    static let baseVisitDuration: TimeInterval = 11.9

    /// A quiet café still wants a few customers milling about.
    static let baseOnScreen = 4
    /// The room is 180pt wide; past this it reads as a mob, not a café.
    static let maxOnScreen = 10
    /// Beyond this the walk cycle turns into a scurry and stops reading as
    /// animals walking.
    static let maxSpeed = 4.0

    /// Trailing window the live sales rate is measured over. Long enough that
    /// the pace doesn't lurch between individual sales, short enough to react
    /// within a few seconds of a rush starting.
    static let rateWindow: TimeInterval = 8

    /// A walking animal at rest: ~4.5 leg swaps a second. The old value was
    /// 0.45s per frame — 2.2fps, about five swaps for the whole 90pt walk,
    /// which read as gliding rather than walking.
    static let baseLegFrame: TimeInterval = 0.22

    /// How many customers may be on screen at once at this sales rate.
    ///
    /// The saturation check happens in Double and BEFORE any conversion to
    /// Int: late-game income is unbounded, and `Int(someHugeDouble)` is a hard
    /// crash, not a clamp. Written the obvious way this trapped on the first
    /// absurd rate it saw.
    static func onScreenCap(salesPerSec rate: Double) -> Int {
        guard rate > 0 else { return baseOnScreen }        // also catches NaN
        // Bodies needed to keep up AT THE RESTING PACE. Sizing the room as if
        // everyone were already sprinting would mean a merely-decent café hit
        // full speed while the room still looked half empty — the crowd has to
        // come first, and only a full room justifies hurrying anyone.
        let needed = rate * baseVisitDuration
        guard needed.isFinite else { return maxOnScreen }
        guard needed < Double(maxOnScreen) else { return maxOnScreen }
        return max(baseOnScreen, Int(needed.rounded(.up)))
    }

    /// Multiplier applied to every duration in a visit. 1.0 = the original
    /// leisurely pace; never below it, so a quiet café never looks sluggish.
    static func speed(salesPerSec rate: Double) -> Double {
        guard rate > 0 else { return 1 }                   // also catches NaN
        let slots = Double(onScreenCap(salesPerSec: rate))
        let wanted = rate * baseVisitDuration / slots
        guard wanted.isFinite else { return maxSpeed }
        return min(maxSpeed, max(1, wanted))
    }

    /// Seconds per leg frame while walking. Cadence is tied to ground speed —
    /// a customer crossing the room twice as fast swings their legs twice as
    /// fast — which is the whole reason the faster pace reads as running
    /// rather than as the same glide on fast-forward.
    static func legFrame(speed: Double) -> TimeInterval {
        max(0.05, baseLegFrame / max(1, speed))
    }

    /// The most sales/sec the animation can depict at this rate. Above this
    /// the café is genuinely selling more than the room can show.
    static func shownPerSec(salesPerSec rate: Double) -> Double {
        Double(onScreenCap(salesPerSec: rate)) * speed(salesPerSec: rate) / baseVisitDuration
    }

    /// Ground speed of a walking customer at rest, in scene points per second
    /// (the original walk covered the 90pt door-to-counter run in 2.2s).
    /// Distances are converted to durations through this, so a customer
    /// joining the back of a long queue takes proportionally longer to get
    /// there instead of covering more ground in the same time.
    static let walkPointsPerSec: Double = 41

    /// The room is only 180pt wide, so the visible line can't grow forever;
    /// past this depth latecomers bunch up at the back rather than queueing
    /// out through the wall.
    static let maxQueueDepth = 5

    /// How far back from the counter the `index`-th customer in line stands.
    static func queueOffset(_ index: Int) -> CGFloat {
        CGFloat(min(index, maxQueueDepth)) * -16
    }
}
