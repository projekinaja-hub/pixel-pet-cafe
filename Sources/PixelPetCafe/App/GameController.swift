import AppKit
import Combine
import Foundation

/// Owns the live GameState: 1s economy tick, autosave, offline earnings on
/// launch/wake. All rules delegate to the pure EconomyEngine.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var state: GameState
    @Published var awayReport: Double?

    private let persistence: Persistence
    private var timer: Timer?
    private var lastTick = Date()
    private var lastAutosave = Date()

    var coinsPerSecond: Double { EconomyEngine.coinsPerSecond(state) }

    init(persistence: Persistence) {
        self.persistence = persistence
        var loaded = persistence.load()
        if let last = loaded.lastSaved {
            let elapsed = Date().timeIntervalSince(last)
            let haul = EconomyEngine.offlineEarnings(loaded, elapsed: elapsed)
            if haul > 0 {
                loaded.coins += haul
                loaded.lifetimeCoins += haul
                loaded.lifetimeCoinsThisRun += haul
                if elapsed > 60 { awayReport = haul }
            }
        }
        self.state = loaded
    }

    func start() {
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 5)  // long gaps handled by wake path
        lastTick = now
        EconomyEngine.tick(&state, dt: max(0, dt))
        if now.timeIntervalSince(lastAutosave) >= 30 {
            saveNow()
            lastAutosave = now
        }
    }

    @objc private func willSleep() { saveNow() }

    @objc private func didWake() {
        Task { @MainActor in
            if let last = state.lastSaved {
                let elapsed = Date().timeIntervalSince(last)
                let haul = EconomyEngine.offlineEarnings(state, elapsed: elapsed)
                if haul > 0 {
                    state.coins += haul
                    state.lifetimeCoins += haul
                    state.lifetimeCoinsThisRun += haul
                    if elapsed > 60 { awayReport = haul }
                }
            }
            lastTick = Date()
            saveNow()
        }
    }

    // MARK: actions

    func buyStaff(_ id: String) { EconomyEngine.buyStaff(id, &state) }
    func buyEquipment(_ id: String) { EconomyEngine.buyEquipment(id, &state) }
    func renovate() { EconomyEngine.renovate(&state); saveNow() }
    func toggleMuted() { state.muted.toggle() }

    func collectGoldenTip() {
        let v = EconomyEngine.goldenTipValue(state)
        state.coins += v
        state.lifetimeCoins += v
        state.lifetimeCoinsThisRun += v
    }

    func saveNow() {
        try? persistence.save(state)
        state.lastSaved = Date()
    }
}
