import AppKit
import Combine
import Foundation

/// Owns the live GameState: 1s sim tick, autosave, offline sim on launch/wake.
/// Publishes sale events so the scene can animate customers.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var state: GameState
    @Published var awayReport: Double?

    let saleEvents = PassthroughSubject<SaleEvent, Never>()
    let tipCollected = PassthroughSubject<Void, Never>()

    private let persistence: Persistence
    private var timer: Timer?
    private var lastTick = Date()
    private var lastAutosave = Date()
    private var rng = SystemRandomNumberGenerator()

    var incomeEstimate: Double { SalesEngine.incomeEstimate(state) }
    var isClosed: Bool { SalesEngine.isClosed(state) }
    var hasStockOut: Bool { SalesEngine.hasStockOut(state) }

    init(persistence: Persistence) {
        self.persistence = persistence
        var loaded = persistence.load().normalized()
        if let last = loaded.lastSaved {
            let elapsed = Date().timeIntervalSince(last)
            let haul = SalesEngine.offlineSim(&loaded, elapsed: elapsed)
            if haul > 0, elapsed > 60 { awayReport = haul }
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
        let dt = min(max(0, now.timeIntervalSince(lastTick)), 5)
        lastTick = now
        let events = SalesEngine.tick(&state, dt: dt, now: now, rng: &rng)
        for e in events { saleEvents.send(e) }
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
                let haul = SalesEngine.offlineSim(&state, elapsed: elapsed)
                if haul > 0, elapsed > 60 { awayReport = haul }
            }
            lastTick = Date()
            saveNow()
        }
    }

    // MARK: actions

    func buyStaff(_ id: String) { EconomyEngine.buyStaff(id, &state) }
    func buyEquipment(_ id: String) { EconomyEngine.buyEquipment(id, &state) }
    func buyPack(_ ingredient: String, units: Int) { SalesEngine.buyPack(ingredient, units: units, &state) }
    func renovate() { EconomyEngine.renovate(&state); saveNow() }
    func toggleMuted() { state.muted.toggle() }
    func cleanSpot() { SalesEngine.cleanSpot(&state) }
    func sweepAll() { SalesEngine.sweepAll(&state) }

    func toggleMenuItem(_ id: String) {
        if let i = state.menuEnabled.firstIndex(of: id) {
            if state.menuEnabled.count > 1 { state.menuEnabled.remove(at: i) }  // never empty menu
        } else {
            state.menuEnabled.append(id)
        }
    }

    func addCustomItem(name: String, icon: String, category: ItemCategory, ingredients: [String: Int]) {
        guard !ingredients.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CustomMenuItem(id: "custom-\(UUID().uuidString.prefix(8))",
                                  name: trimmed.isEmpty ? "House Special" : String(trimmed.prefix(24)),
                                  icon: icon, category: category, ingredients: ingredients)
        state.customItems.append(item)
        state.menuEnabled.append(item.id)
        saveNow()
    }

    func deleteCustomItem(_ id: String) {
        state.customItems.removeAll { $0.id == id }
        state.menuEnabled.removeAll { $0 == id }
    }

    func setOwner(_ owner: OwnerConfig) { state.owner = owner }
    func setBarCharacter(_ id: String) { state.barCharacter = id }

    func collectGoldenTip() {
        let v = EconomyEngine.goldenTipValue(state)
        state.coins += v
        state.lifetimeCoins += v
        state.lifetimeCoinsThisRun += v
        tipCollected.send()
    }

    func saveNow() {
        try? persistence.save(state)
        state.lastSaved = Date()
    }
}
