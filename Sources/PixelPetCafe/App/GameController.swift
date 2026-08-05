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
    let casinoJackpotWon = PassthroughSubject<Double, Never>()
    let casinoGameChanged = PassthroughSubject<CasinoGame, Never>()
    let blackjackDisplay = PassthroughSubject<(player: [(String, Bool)], dealer: [(String, Bool)], hole: Bool), Never>()
    let rouletteResult = PassthroughSubject<Int, Never>()
    let mahjongDiscards = PassthroughSubject<Int, Never>()
    let casinoFocus = PassthroughSubject<Bool, Never>()
    let mapOpen = PassthroughSubject<Bool, Never>()
    /// Big happy moments — the scene answers with a confetti burst.
    let celebrate = PassthroughSubject<Void, Never>()

    private let persistence: Persistence
    private var timer: Timer?
    private var lastTick = Date()
    private var lastAutosave = Date()
    private var rng = SystemRandomNumberGenerator()
    // Not persisted: only used to notice a holiday *starting* while running.
    private var lastHolidayName: String?

    // TYPING ENERGY: we read the OS-wide key-down COUNTER — a running total of
    // how many keys have been pressed anywhere on the Mac. No event stream, no
    // key contents, nothing that can silently go stale.
    //
    // This replaced a pair of NSEvent monitors, which had an unfixable flaw:
    // a global monitor installed before macOS trusted the app stays alive but
    // DEAD — it delivers nothing forever, and `monitor != nil` still reports
    // healthy, so the app couldn't even tell. Granting Accessibility later
    // didn't revive it. That's the "I already gave permission and it still
    // does nothing" bug. A counter can't have that failure: every sample is a
    // fresh question to the OS.
    private var keySampler: Timer?
    /// Diagnostic only (PPC_KEYTEST): proves the poll loop is alive.
    private(set) var keySamplesTaken = 0
    private var lastKeyCount: UInt32?
    /// Trailing per-sample key counts, used to measure speed over a real
    /// window instead of a single 0.2s sample.
    private var recentKeys: [(at: Date, keys: Double)] = []
    private var lastSampleAt = Date()
    private var keystrokesSinceLastTick = 0
    /// How often we ask the OS for the counter. Fast enough that the menu bar
    /// reacts within a keystroke or two.
    private static let keySampleInterval: TimeInterval = 0.2
    @Published private(set) var workBoost: Double = 1
    @Published private(set) var lastKeystrokeAt: Date?
    @Published private(set) var keystrokesPerSec: Double = 0
    /// Standard typing speed: words-per-minute at 5 chars/word.
    var wpm: Double { keystrokesPerSec * 12 }
    /// "Are they typing right now?" — answered by recency, so the café can
    /// react instantly without the speed number having to be twitchy.
    var isActivelyTyping: Bool {
        EnergyEngine.isActivelyTyping(lastKeystrokeAt: lastKeystrokeAt, now: Date())
    }
    // in-memory "keys typed today" stat for the EnergyCard; resets on real
    // (wall-clock) day change, never persisted.
    @Published private(set) var keystrokesToday: Double = 0
    private var keystrokesTodayDate = Calendar.current.startOfDay(for: Date())
    @Published var banner: (emoji: String, text: String)?
    let soundRequest = PassthroughSubject<String, Never>()
    private var bannerClearAt = Date.distantPast

    var incomeEstimate: Double { SalesEngine.incomeEstimate(state) }
    // Rolling per-second income samples (in-memory only): drives the header
    // trend arrow and the Café tab momentum sparkline. ~2 minutes of data.
    @Published private(set) var incomeHistory: [Double] = []
    /// Bumped on every popover open: GameSpriteView re-presents the scene on
    /// change, restarting SKView's display link (the long-idle freeze cure).
    @Published private(set) var viewReloadToken = 0
    func bumpViewReload() { viewReloadToken += 1 }

    // MARK: runtime health (see RuntimeHealth)

    /// Faults detected on the last tick. Published so the panel can SAY the
    /// app broke instead of silently looking fine — the failure mode that has
    /// cost this project more time than any logic bug.
    @Published private(set) var runtimeFaults: [RuntimeHealth.Fault] = []
    /// Set by StatusItemController, which owns the scene: reports seconds since
    /// the last drawn frame, or nil when the scene isn't meant to be drawing.
    var renderAgeProvider: (() -> TimeInterval?)?
    /// Count of self-heals performed, for diagnostics (PPC_KEYTEST).
    private(set) var selfHealCount = 0

    /// Compare every heartbeat against its deadline, then repair whatever died.
    /// Runs from the tick — and because a dead tick can't check itself, the
    /// menu-bar click path (`ensureRunning`) remains the outer backstop.
    private func checkRuntimeHealth(now: Date) {
        let probe = RuntimeHealth.Probe(
            tickAge: now.timeIntervalSince(lastTick),
            keySampleAge: state.workMode ? now.timeIntervalSince(lastSampleAt) : nil,
            renderAge: renderAgeProvider?())
        let faults = RuntimeHealth.faults(probe)
        if faults != runtimeFaults { runtimeFaults = faults }
        guard !faults.isEmpty else { return }
        selfHealCount += 1
        for fault in faults {
            switch fault {
            case .simStalled: installTickTimer()
            case .typingNotCounting: startKeyTracking()
            case .renderStalled: bumpViewReload()
            }
            showBanner("🛠", RuntimeHealth.message(for: fault))
        }
    }
    /// Fractional change vs ~60s ago: +0.10 = income up 10% in the last minute.
    var incomeTrend: Double {
        guard incomeHistory.count >= 30, let past = incomeHistory.first, past > 0 else { return 0 }
        let recent = incomeHistory.suffix(5).reduce(0, +) / 5
        let baseline = incomeHistory.prefix(5).reduce(0, +) / 5
        guard baseline > 0 else { return 0 }
        return recent / baseline - 1
    }
    var isClosed: Bool { SalesEngine.isClosed(state) }
    var hasStockOut: Bool { SalesEngine.hasStockOut(state) }

    // come-back-and-check notification trackers (in-memory only, never persisted)
    private var notifiedHolidayName: String?
    private var notifiedGoalsDay: Int = .min
    private var lastStreakReminderDay: Date?

    init(persistence: Persistence) {
        self.persistence = persistence
        // migrated() first (one-time repairs, version-gated), then normalized()
        // (idempotent structural fills). Order matters: repairs assume the
        // fields they touch, fills assume the repairs already ran.
        var loaded = persistence.load().migrated().normalized()
        if let last = loaded.lastSaved {
            let elapsed = Date().timeIntervalSince(last)
            let haul = SalesEngine.offlineSim(&loaded, elapsed: elapsed)
            if haul > 0, elapsed > 60 { awayReport = haul }
        }
        EconomyEngine.updateDailyStreak(&loaded)
        self.state = loaded
        // Don't announce the goal set that's already up when the app launches —
        // only a rollover observed while running is news.
        notifiedGoalsDay = loaded.goalsDay
    }

    func start() {
        lastTick = Date()
        installTickTimer()
        if state.workMode { startKeyTracking() }

        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func installTickTimer() {
        timer?.invalidate()
        // The inner Task re-declares [weak self] rather than reaching for the
        // outer closure's capture. Swift 6 tolerates the latter; the Swift
        // shipped on macOS 14 rejects it outright ("reference to captured var
        // 'self' in concurrently-executing code"), so the package built only
        // on the machine it was written on. Same fix at every timer below.
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Watchdog recovery. Timers on RunLoop.main can silently stop firing
    /// after long uptime or sleep/wake, freezing both the sim and the
    /// display with no self-recovery. This runs from paths that ALWAYS work
    /// regardless of our timers (the menu-bar click via AppKit, and the
    /// sleep/wake notification): if the tick has gone stale, it catches the
    /// café up on the missed time and reinstalls a live timer.
    func ensureRunning() {
        let gap = Date().timeIntervalSince(lastTick)
        guard gap > 5 || timer == nil || timer?.isValid != true else { return }
        if gap > 60, let last = state.lastSaved {
            let haul = SalesEngine.offlineSim(&state, elapsed: Date().timeIntervalSince(last))
            if haul > 0 { awayReport = haul }
        }
        lastTick = Date()
        installTickTimer()
        if state.workMode { startKeyTracking() }
    }

    private func tick() {
        let now = Date()
        let dt = min(max(0, now.timeIntervalSince(lastTick)), 5)
        // Health is judged BEFORE lastTick moves, so tickAge still reflects the
        // real gap since the previous tick rather than being reset to zero.
        checkRuntimeHealth(now: now)
        lastTick = now
        updateWorkBoost(now: now, dt: dt)
        if let event = Events.maybeSpawn(&state, dt: dt, now: now, rng: &rng) {
            var text = "\(event.name) — \(event.desc)"
            if event.id == "critic", let verdict = state.lastCriticVerdict {
                text = verdict ? "Food Critic loved it! 💖 +8" : "Food Critic was unimpressed… 💖 −8"
            }
            showBanner(event.emoji, text)
            soundRequest.send("event")
            if event.id == "lucky_hour" { celebrate.send() }
        }
        for def in Achievements.checkAll(&state) {
            showBanner(def.emoji, "Achievement: \(def.name)!")
            soundRequest.send("achieve")
        }
        if state.cleanliness >= 80 { Goals.recordProgress(&state, .cleanlinessStreak, amount: dt) }
        if Goals.refreshIfNeeded(&state, now: now, rng: &rng) > 0 {
            showBanner("🎯", "New goals for the day! Unclaimed rewards were paid out.")
        }
        if let clear = banner, bannerClearAt < now, clear.text.isEmpty == false, now > bannerClearAt {
            banner = nil
        }
        let events = SalesEngine.tick(&state, dt: dt, now: now, boost: workBoost, rng: &rng)
        for e in events { saleEvents.send(e) }
        // holiday jingle + banner when a calendar holiday begins while we're
        // running (in-app feedback); checkNotifications below handles the
        // system notification for when the popover is closed.
        let holiday = Holidays.today(state)
        if holiday?.name != lastHolidayName {
            lastHolidayName = holiday?.name
            if let h = holiday {
                var boosts: [String] = []
                if h.customerBoost > 1 { boosts.append("customers ×\(String(format: "%.1f", h.customerBoost))") }
                if h.priceBoost > 1 { boosts.append("prices ×\(String(format: "%.2f", h.priceBoost))") }
                let suffix = boosts.isEmpty ? "" : " \(boosts.joined(separator: ", "))!"
                showBanner(h.emoji, "\(h.name) today!\(suffix)")
                soundRequest.send("holiday")
                celebrate.send()
            }
        }
        checkNotifications(now: now)
        incomeHistory.append(SalesEngine.incomeEstimate(state))
        if incomeHistory.count > 120 { incomeHistory.removeFirst(incomeHistory.count - 120) }
        if now.timeIntervalSince(lastAutosave) >= 30 {
            saveNow()
            lastAutosave = now
        }
    }

    // MARK: come-back-and-check notifications

    /// Fires system notifications for moments worth returning for: a holiday
    /// starting, the daily goal set rolling over, and an evening reminder
    /// before a daily streak lapses. NotificationManager itself no-ops while
    /// the popover is open (the user is already looking) and when running
    /// unbundled (bare debug binary).
    private func checkNotifications(now: Date) {
        if let holiday = Holidays.today(state) {
            if holiday.name != notifiedHolidayName {
                notifiedHolidayName = holiday.name
                NotificationManager.shared.requestPermissionIfNeeded()
                NotificationManager.shared.notify(
                    id: "holiday",
                    title: "\(holiday.emoji) \(holiday.name) today!",
                    body: NotificationTriggers.holidayBody(holiday))
            }
        } else {
            notifiedHolidayName = nil
        }

        if state.goalsDay != notifiedGoalsDay, !state.activeGoals.isEmpty {
            notifiedGoalsDay = state.goalsDay
            NotificationManager.shared.requestPermissionIfNeeded()
            NotificationManager.shared.notify(
                id: "goals",
                title: "📋 Fresh goals are up",
                body: "\(state.activeGoals.count) new goals are waiting at the café.")
        }

        let today = Calendar.current.startOfDay(for: now)
        if lastStreakReminderDay != today,
           NotificationTriggers.shouldSendStreakReminder(
               now: now, lastPlayed: state.lastPlayedRealDate, streak: state.dailyStreak) {
            lastStreakReminderDay = today
            let pct = NotificationTriggers.streakBonusPercent(streak: state.dailyStreak)
            NotificationManager.shared.requestPermissionIfNeeded()
            NotificationManager.shared.notify(
                id: "streak",
                title: "🔥 Your \(state.dailyStreak)-day streak ends at midnight",
                body: "Open the café to keep your +\(pct)% price bonus")
        }
    }

    /// Opening the popover counts as playing today. `updateDailyStreak` runs
    /// at launch, so an app left running across midnight would otherwise have
    /// a stale `lastPlayedRealDate` even while the user actively checks in —
    /// re-running it here keeps the streak honest (same-day calls are a safe
    /// no-op) and stops the 19:00 reminder from firing at engaged players.
    func refreshStreakOnInteraction(now: Date = Date()) {
        EconomyEngine.updateDailyStreak(&state, now: now)
        grantDailyCheckInIfNeeded(now: now)
    }

    /// Daily check-in reward: the first popover open of each REAL calendar
    /// day (not the compressed in-game calendar) grants ~15 minutes of
    /// current income, floored at 500 coins so a fresh café still feels it.
    static let checkInMinCoins = 500.0
    static let checkInIncomeSeconds = 900.0
    private func grantDailyCheckInIfNeeded(now: Date) {
        if let last = state.lastCheckInDate, Calendar.current.isDate(last, inSameDayAs: now) { return }
        state.lastCheckInDate = now
        let amount = max(Self.checkInMinCoins, Self.checkInIncomeSeconds * SalesEngine.incomeEstimate(state))
        state.coins += amount
        state.lifetimeCoins += amount
        state.lifetimeCoinsThisRun += amount
        showBanner("🎁", "Daily check-in! +🪙 \(formatNumber(amount))")
        soundRequest.send("goal_done")
        celebrate.send()
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
            installTickTimer()
            saveNow()
        }
    }

    // MARK: work mode (typing boost)

    /// Starts (or revives) the counter sampler. Safe to call repeatedly — it
    /// always replaces the old timer, so a dead one can never linger.
    func startKeyTracking() {
        keySampler?.invalidate()
        lastSampleAt = Date()
        // Re-baseline so the first sample after a restart measures from NOW
        // instead of crediting every key typed while we weren't looking.
        lastKeyCount = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        let t = Timer(timeInterval: Self.keySampleInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.sampleKeystrokes() }
        }
        RunLoop.main.add(t, forMode: .common)
        keySampler = t
    }

    /// Asks the OS how many keys have been pressed since the last look and
    /// turns that delta into a live typing speed.
    private func sampleKeystrokes() {
        let now = Date()
        let dt = max(0.01, now.timeIntervalSince(lastSampleAt))
        lastSampleAt = now
        keySamplesTaken += 1
        let count = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        defer { lastKeyCount = count }
        guard let previous = lastKeyCount else { return }  // first look: baseline only
        guard count >= previous else { return }            // counter reset (new login session)
        let typed = EnergyEngine.creditedKeys(delta: Double(count - previous), dt: dt)
        if typed > 0 {
            keystrokesSinceLastTick += Int(typed.rounded())
            lastKeystrokeAt = now
        }
        // Speed is measured over a trailing window, not off a single sample:
        // one keystroke landing in one 0.2s sample used to read as 60 WPM.
        recentKeys.append((now, typed))
        recentKeys.removeAll { now.timeIntervalSince($0.at) > EnergyEngine.rateWindow }
        let measured = EnergyEngine.windowedKps(keysInWindow: recentKeys.reduce(0) { $0 + $1.keys })
        let next = EnergyEngine.nextKps(current: keystrokesPerSec, measured: measured, dt: dt)
        if abs(next - keystrokesPerSec) > 0.005 { keystrokesPerSec = next }
    }

    private func stopKeyTracking() {
        keySampler?.invalidate()
        keySampler = nil
        lastKeyCount = nil
        keystrokesSinceLastTick = 0
        recentKeys = []
        // the tank keeps ruling the café even with the monitor off
        workBoost = EnergyEngine.speedFactor(energy: state.energy, kps: 0)
        keystrokesPerSec = 0
    }

    /// TYPING ENERGY tick: bank the keystrokes typed since the last tick into
    /// the tank, burn the constant running cost, and derive the café-wide
    /// speed factor (still published as `workBoost` — header/scene/status-item
    /// wiring all read that name). With the monitor off or no Accessibility
    /// trust there's no gain, but the burn and the empty-tank crawl still apply.
    private func updateWorkBoost(now: Date, dt: TimeInterval) {
        // The sampler is the only thing that must stay alive; if anything ever
        // knocks it out, the next tick puts it back.
        if state.workMode, keySampler?.isValid != true { startKeyTracking() }

        // real-day rollover for the in-memory "today" stat
        let today = Calendar.current.startOfDay(for: now)
        if today != keystrokesTodayDate {
            keystrokesTodayDate = today
            keystrokesToday = 0
        }

        let typed = Double(keystrokesSinceLastTick)
        keystrokesSinceLastTick = 0
        // Every key counted anywhere on the Mac fills the tank.
        if state.workMode, typed > 0 {
            state.energy = min(EnergyEngine.energyCap,
                               state.energy + typed * EnergyEngine.energyPerKeystroke)
            state.lifetimeKeystrokes += typed
            keystrokesToday += typed
        }
        state.energy = max(0, state.energy - EnergyEngine.burnPerSec * dt)

        // keystrokesPerSec is maintained live by the sampler (5×/sec); the tick
        // only has to zero it when typing isn't fuelling anything.
        if !state.workMode, keystrokesPerSec != 0 { keystrokesPerSec = 0 }
        let factor = EnergyEngine.speedFactor(energy: state.energy, kps: keystrokesPerSec)
        if abs(factor - workBoost) > 0.001 { workBoost = factor }
    }

    // MARK: energy spend actions (pure logic lives in EnergyEngine)

    func spendEnergyOnRush() {
        guard EnergyEngine.applyRush(&state, now: Date()) else { return }
        showBanner("⚡", "Typing Rush! ×2 customers for 5 min")
        soundRequest.send("event")
        celebrate.send()
    }

    func spendEnergyOnRestock() {
        guard EnergyEngine.applyRestock(&state) else { return }
        showBanner("⚡", "Instant restock!")
        soundRequest.send("buy")
    }

    func toggleWorkMode() {
        state.workMode.toggle()
        if state.workMode { startKeyTracking() } else { stopKeyTracking() }
    }

    /// Map pin tapped: travel to owned cafés, buy new ones on the spot.
    func mapSelect(_ cityId: String) {
        let def = Cities.def(cityId)
        if let index = state.cafes.firstIndex(where: { $0.city == cityId }) {
            switchCafe(index)
            banner = ("🧭", "Welcome back to \(def.name)!")
            mapOpen.send(false)
        } else if state.coins >= def.cost {
            buyCity(cityId)
            banner = ("🎉", "\(def.name) café opened!")
            soundRequest.send("achieve")
            mapOpen.send(false)
        } else {
            banner = ("🔒", "\(def.name) needs 🪙 \(formatNumber(def.cost))")
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
        state.casinoWagered += amount
        if let pot = CasinoEngine.growJackpot(&state.casinoJackpotPot, wager: amount, rng: &rng) {
            casinoAward(pot)
            casinoJackpotWon.send(pot)
            showBanner("🎰", "PROGRESSIVE JACKPOT! +🪙 \(formatNumber(pot))")
            soundRequest.send("fanfare")
        }
        return true
    }

    func casinoAward(_ amount: Double) {
        guard amount > 0 else { return }
        state.coins += amount
        state.casinoWon += amount
        state.casinoBiggestWin = max(state.casinoBiggestWin, amount)
        Goals.recordProgress(&state, .casinoWin)
        casinoWin.send(amount)
    }

    private func showBanner(_ emoji: String, _ text: String) {
        banner = (emoji, text)
        bannerClearAt = Date().addingTimeInterval(6)
    }

    /// Casino games report their special feats directly.
    func unlockAchievement(_ id: String) {
        guard !state.achievements.contains(id) else { return }
        state.achievements.append(id)
        if let def = Achievements.all.first(where: { $0.id == id }) {
            showBanner(def.emoji, "Achievement: \(def.name)!")
            soundRequest.send("achieve")
        }
    }

    // MARK: actions

    func buyStaff(_ id: String) {
        if EconomyEngine.buyStaff(id, &state) { soundRequest.send("buy") }
    }
    /// Dev-only: seeds a demo staff roster for PPC_STAFF=1 offscreen
    /// snapshotting — panels like Style's staff-colors section have nothing
    /// to screenshot on an otherwise-empty fresh save.
    func debugSeedStaff() {
        // The whole roster, Jeki included — a demo that omits the newest hire
        // can't show whether it stands in the right place or clips a neighbour.
        state.staffLevels = ["mocha": 3, "biscuit": 2, "poppy": 1, "chip": 1,
                             "juno": 1, "bo": 1, "earl": 1, "marble": 1, "jeki": 1]
        state.lifetimeCoins = max(state.lifetimeCoins, 5000)
    }
    /// Dev-only: PPC_STAFF_MAXED=1 verification hook — puts Chip at this
    /// café's level cap so the Staff tab's "MAX" state can be screenshotted.
    func debugMaxChip() {
        state.staffLevels["chip"] = EconomyEngine.staffLevelCap(state)
    }
    /// Dev-only: PPC_STAFF_COLOR=1 verification hook — tints Mocha bright
    /// teal/magenta so screenshots can confirm custom tinting actually
    /// applies (vs. silently no-oping and just showing the default palette).
    func debugTintMocha() {
        EconomyEngine.setStaffColor("mocha", body: StaffColor(r: 40, g: 200, b: 210),
                                     clothes: StaffColor(r: 230, g: 40, b: 190), &state)
    }
    /// Dev-only: PPC_STAFF_PAINT_DEMO=1 verification hook — paints a
    /// simple smiley on Poppy so screenshots can confirm custom pixel art
    /// actually replaces the generated sprite in both the scene and UI.
    func debugPaintPoppy() {
        var art = PixelArt.blank()
        for y in 2..<18 {
            for x in 2..<14 { art.set(x: x, y: y, color: .packRGBA(r: 233, g: 158, b: 160)) }
        }
        for (x, y) in [(5, 8), (10, 8)] { art.set(x: x, y: y, color: .packRGBA(r: 52, g: 34, b: 41)) }
        for x in 5...10 { art.set(x: x, y: 13, color: .packRGBA(r: 52, g: 34, b: 41)) }
        EconomyEngine.setStaffPaint("poppy", art, &state)
    }
    func setStaffColor(_ id: String, body: StaffColor, clothes: StaffColor) {
        EconomyEngine.setStaffColor(id, body: body, clothes: clothes, &state)
        saveNow()
    }
    func resetStaffColor(_ id: String) {
        EconomyEngine.resetStaffColor(id, &state)
        saveNow()
    }
    func setStaffPaint(_ id: String, _ art: PixelArt) {
        EconomyEngine.setStaffPaint(id, art, &state)
        saveNow()
    }
    func resetStaffPaint(_ id: String) {
        EconomyEngine.resetStaffPaint(id, &state)
        saveNow()
    }
    func buyEquipment(_ id: String) {
        if EconomyEngine.buyEquipment(id, &state) {
            soundRequest.send("buy")
            Goals.recordProgress(&state, .upgradeEquipment)
        }
    }
    func buyPack(_ ingredient: String, units: Int) {
        if SalesEngine.buyPack(ingredient, units: units, &state) { soundRequest.send("buy") }
    }
    func renovate() { EconomyEngine.renovate(&state); saveNow() }
    func moveToNewCountry() {
        EconomyEngine.moveToNewCountry(&state)
        saveNow()
        soundRequest.send("fanfare")
        celebrate.send()
    }
    func toggleMuted() { state.muted.toggle() }
    func cleanSpot() { SalesEngine.cleanSpot(&state) }
    func sweepAll() {
        if SalesEngine.sweepAll(&state) { soundRequest.send("sweep") }
    }

    func buyTable() {
        if EconomyEngine.buyTable(&state) { soundRequest.send("buy") }
    }

    func buyStorage() {
        if EconomyEngine.buyStorage(&state) { soundRequest.send("buy") }
    }

    func setRefillThreshold(_ value: Double) {
        state.refillThreshold = min(1, max(0, value))
    }

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

    func upgradeTaste(_ id: String) {
        if SalesEngine.upgradeTaste(id, &state) { soundRequest.send("buy") }
    }
    func researchTaste() { SalesEngine.researchTaste(&state) }

    func setOwner(_ owner: OwnerConfig) { state.owner = owner }
    func setBarCharacter(_ id: String) { state.barCharacter = id }

    // MARK: rotating short-term goals (Goals.swift)

    /// Claims a completed goal's reward. Safe to call repeatedly — `Goals.claim`
    /// only pays out once per goal (guards on `claimed`).
    /// Test-only seam: lets tests pin a known goal set without threading RNG
    /// through `Goals.refreshIfNeeded` just to exercise a single call site.
    func setGoalsForTesting(_ goals: [ActiveGoal]) {
        state.activeGoals = goals
    }

    func claimGoal(_ kind: GoalKind) {
        let reward = Goals.claim(&state, kind)
        guard reward > 0 else { return }
        showBanner(Goals.def(kind).emoji, "Goal complete: \(Goals.def(kind).name)! +🪙 \(formatNumber(reward))")
        soundRequest.send("goal_done")
        celebrate.send()
    }

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
