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
    let casinoWin = PassthroughSubject<Double, Never>()
    let casinoGameChanged = PassthroughSubject<CasinoGame, Never>()
    let blackjackDisplay = PassthroughSubject<(player: [(String, Bool)], dealer: [(String, Bool)], hole: Bool), Never>()
    let rouletteResult = PassthroughSubject<Int, Never>()
    let mahjongDiscards = PassthroughSubject<Int, Never>()
    let casinoFocus = PassthroughSubject<Bool, Never>()

    private let persistence: Persistence
    private var timer: Timer?
    private var lastTick = Date()
    private var lastAutosave = Date()
    private var rng = SystemRandomNumberGenerator()

    // work mode: count (never read) keystrokes to measure typing activity
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var keystrokes: [Date] = []
    @Published private(set) var workBoost: Double = 1

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
        if state.workMode { startKeyMonitor() }

        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func tick() {
        let now = Date()
        let dt = min(max(0, now.timeIntervalSince(lastTick)), 5)
        lastTick = now
        updateWorkBoost(now: now)
        let events = SalesEngine.tick(&state, dt: dt, now: now, boost: workBoost, rng: &rng)
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

    // MARK: work mode (typing boost)

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        // Global monitors only deliver events with Accessibility permission.
        // We count key-down events; key content is never inspected or stored.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor in self?.keystrokes.append(Date()) }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.keystrokes.append(Date()) }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        keystrokes = []
        workBoost = 1
    }

    private func updateWorkBoost(now: Date) {
        guard state.workMode, keyMonitor != nil else {
            if workBoost != 1 { workBoost = 1 }
            return
        }
        keystrokes.removeAll { now.timeIntervalSince($0) > 10 }
        let kps = Double(keystrokes.count) / 10
        let boost = 1 + 1.5 * min(1, kps / 6)     // 6 keys/sec sustained = ×2.5
        if abs(boost - workBoost) > 0.01 { workBoost = boost }
    }

    func toggleWorkMode() {
        state.workMode.toggle()
        if state.workMode {
            if !AXIsProcessTrusted() {
                let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)   // asks once for Accessibility
            }
            startKeyMonitor()
        } else {
            stopKeyMonitor()
        }
    }

    // MARK: cities

    func buyCity(_ id: String) {
        let def = Cities.def(id)
        guard !state.ownsCity(id), state.coins >= def.cost else { return }
        state.coins -= def.cost
        var fresh = CafeState.fresh(city: id)
        fresh.menuEnabled = state.menuEnabled     // carry the menu layout over
        state.cafes.append(fresh)
        state.activeCafe = state.cafes.count - 1
        saveNow()
    }

    func switchCafe(_ index: Int) {
        guard state.cafes.indices.contains(index) else { return }
        state.activeCafe = index
        state.customerProgress = 0
    }

    func toggleAds() {
        state.adsActive.toggle()
    }

    // MARK: casino (moves coins only — never lifetime/prestige)

    func casinoTrySpend(_ amount: Double) -> Bool {
        guard amount > 0, state.coins >= amount else { return false }
        state.coins -= amount
        return true
    }

    func casinoAward(_ amount: Double) {
        guard amount > 0 else { return }
        state.coins += amount
        casinoWin.send(amount)
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

    func upgradeTaste(_ id: String) { SalesEngine.upgradeTaste(id, &state) }
    func researchTaste() { SalesEngine.researchTaste(&state) }

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
