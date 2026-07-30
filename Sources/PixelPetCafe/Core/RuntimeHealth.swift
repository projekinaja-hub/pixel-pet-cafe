import Foundation

/// RUNTIME liveness — "are the moving parts still moving?"
///
/// Distinct from `HealthCheck`, which grades the *café* (reputation,
/// cleanliness, throughput). This grades the *app*.
///
/// It exists because of a pattern that cost this project days: every hard bug
/// so far was the app being broken while believing it was fine.
///   • the global key monitor sat "installed" and dead, delivering nothing,
///     forever — and `monitor != nil` still reported healthy
///   • SpriteKit's display link died after long idle, freezing the picture
///     while the simulation ran on
///   • RunLoop timers silently stopped firing, freezing the simulation
///   • the energy bar rendered perfectly while showing a quantity that
///     physically could not move
///
/// Each got its own patch. None of them could be *detected*. Every moving part
/// now publishes a heartbeat, this compares the heartbeats against deadlines,
/// and the app can both self-heal and — crucially — SAY something is wrong
/// instead of quietly looking fine.
enum RuntimeHealth {

    enum Fault: String, CaseIterable {
        /// The 1s simulation tick has stopped arriving.
        case simStalled
        /// The keystroke sampler has stopped polling the OS counter.
        case typingNotCounting
        /// The scene is on screen but its render loop isn't advancing.
        case renderStalled
    }

    /// A snapshot of every heartbeat, gathered by GameController.
    struct Probe {
        /// Seconds since the last simulation tick.
        var tickAge: TimeInterval
        /// Seconds since the keystroke sampler last polled. Nil when typing
        /// is switched off, in which case silence is correct, not a fault.
        var keySampleAge: TimeInterval?
        /// Seconds since the scene last drew a frame. Nil when the scene isn't
        /// on screen — an idle scene is *supposed* to stop drawing.
        var renderAge: TimeInterval?
    }

    // Deadlines are generous multiples of each part's real period (1s tick,
    // 0.2s key sampler, 60fps render) so ordinary scheduling jitter, a busy
    // machine, or a debugger pause can never raise a false alarm.
    static let tickStaleAfter: TimeInterval = 6
    static let keySampleStaleAfter: TimeInterval = 3
    static let renderStaleAfter: TimeInterval = 2.5

    static func faults(_ p: Probe) -> [Fault] {
        var out: [Fault] = []
        if p.tickAge > tickStaleAfter { out.append(.simStalled) }
        if let age = p.keySampleAge, age > keySampleStaleAfter { out.append(.typingNotCounting) }
        if let age = p.renderAge, age > renderStaleAfter { out.append(.renderStalled) }
        return out
    }

    static func isHealthy(_ p: Probe) -> Bool { faults(p).isEmpty }

    /// Player-facing text. Plain language, and it always names the recovery,
    /// because the point is that the player is never left guessing whether the
    /// game is broken or they are.
    static func message(for fault: Fault) -> String {
        switch fault {
        case .simStalled:
            return "The café had stopped ticking — restarting it now."
        case .typingNotCounting:
            return "Typing wasn't being counted — restarting the counter."
        case .renderStalled:
            return "The picture had frozen — restarting the view."
        }
    }
}
