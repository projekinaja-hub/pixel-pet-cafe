import Foundation

struct OwnerConfig: Codable, Equatable {
    var species: String = "cat"      // cat, corgi, bunny, fox, bear, owl
    var palette: String = "brown"    // brown, cream, orange, gray
    var accessory: String = "none"   // none, bow, cap, glasses, scarf
    var cafeName: String = "Pixel Pet Café"

    static let speciesOptions = ["cat", "corgi", "bunny", "fox", "bear", "owl", "raccoon", "panda", "deer"]
    static let paletteOptions = ["brown", "cream", "orange", "gray"]
    static let accessoryOptions = ["none", "bow", "cap", "glasses", "scarf"]
}

/// Entire savable game state. v3: multiple cafés (one per city); every owned
/// café earns simultaneously (SalesEngine.tick/offlineSim loop over all of
/// them) — `activeCafe` only selects which one is on screen right now.
/// Passthrough accessors keep the engines café-agnostic.
/// Decoding is backward compatible with v1/v2 saves (root café fields).
struct GameState: Codable {
    var coins: Double = 0
    var lifetimeCoins: Double = 0
    var lifetimeCoinsThisRun: Double = 0
    var stars: Int = 0
    var lastSaved: Date?
    var muted: Bool = false
    var customItems: [CustomMenuItem] = []
    var owner: OwnerConfig = OwnerConfig()
    var barCharacter: String = "owner"   // "owner" or a staff id
    // v3
    var cafes: [CafeState] = []
    var activeCafe: Int = 0
    var reputation: Double = 50          // 0-100
    var adsActive: Bool = false
    var workMode: Bool = false
    var menuTaste: [String: Int] = [:]   // item id -> taste level (0-10)
    var salesCount: [String: Int] = [:]  // item id -> lifetime sales
    var tasteKnown: [String] = []        // city ids with researched preferences
    var activeEvent: String?
    var eventEndsAt: Date?
    var lastCriticVerdict: Bool?
    var achievements: [String] = []
    var casinoWagered: Double = 0
    var casinoWon: Double = 0
    var casinoBiggestWin: Double = 0
    // v6: chain-wide progressive jackpot pot — grows with every casino wager.
    var casinoJackpotPot: Double = CasinoEngine.jackpotSeed
    // v4: fluctuating ingredient market (global, not per-café)
    var marketPrices: [String: Double] = [:]     // ingredient id -> live unit price
    var priceHistory: [String: [Double]] = [:]   // ingredient id -> recent price samples (sparkline)
    // v5: shared contract for the calendar/seasons system — see Season.swift.
    // Real value now: GameCalendar.advance derives it every tick from
    // `calendarStartedAt`. Default stays .spring so a value read before the
    // first tick (or an old save) is still sane.
    var season: Season = .spring
    /// Anchor for the in-game calendar (see Calendar.swift): the current day
    /// is elapsed-real-time-since-this-date / GameCalendar.dayLength, mirroring
    /// how offlineSim already derives its catch-up window from elapsed time
    /// rather than accumulated ticks. Set once, implicitly, the moment a
    /// GameState value is first constructed (newGame() included) and never
    /// touched again — old saves missing it default to "now" on load.
    var calendarStartedAt: Date = Date()
    // v7: "Move to a New Country" — the big, whole-game prestige on top of
    // renovate(). Counts completed world resets; never itself reset by a
    // world reset (or by renovate) — see EconomyEngine.moveToNewCountry.
    // Grants a small permanent global bonus per world via SalesEngine.
    var worldsVisited: Int = 0
    // v8: rotating short-term goals (Goals.swift) — distinct from the
    // permanent `achievements` above. `goalsDay` is the in-game calendar day
    // (GameCalendar.currentDay) the current set was rolled for; refreshed
    // roughly once per in-game day. Empty on a fresh/old save — normalized()
    // populates the first set.
    var activeGoals: [ActiveGoal] = []
    var goalsDay: Int = -1
    // v9: real-world daily login streak (actual calendar days, NOT the
    // compressed in-game calendar) — see GameController.updateDailyStreak.
    var dailyStreak: Int = 0
    var lastPlayedRealDate: Date?
    // v10: cosmetic, free, global (not per-café) staff recoloring — id ->
    // chosen body/clothes tint. Missing entries render with StaffPalette's
    // original defaults, so this is purely additive over existing art.
    var staffColors: [String: StaffColorPair] = [:]
    // v11: cosmetic, free, global freehand staff portraits — id -> a full
    // custom 16x20 canvas that replaces the generated sprite (and staffColors
    // tint) entirely for that staff member. Missing entries fall back to
    // staffColors/StaffPalette exactly as before this existed.
    var staffPaint: [String: PixelArt] = [:]

    static let starterStock: [String: Int] = ["beans": 40, "milk": 25, "flour": 20, "sugar": 20]

    // MARK: active-café passthroughs (engines stay café-agnostic)

    var cafe: CafeState {
        get { cafes.indices.contains(activeCafe) ? cafes[activeCafe] : CafeState.fresh(city: "home") }
        set { if cafes.indices.contains(activeCafe) { cafes[activeCafe] = newValue } }
    }
    var city: CityDef { Cities.def(cafe.city) }
    var staffLevels: [String: Int] {
        get { cafe.staffLevels } set { cafe.staffLevels = newValue }
    }
    var equipmentLevels: [String: Int] {
        get { cafe.equipmentLevels } set { cafe.equipmentLevels = newValue }
    }
    var stock: [String: Int] {
        get { cafe.stock } set { cafe.stock = newValue }
    }
    var menuEnabled: [String] {
        get { cafe.menuEnabled } set { cafe.menuEnabled = newValue }
    }
    var cleanliness: Double {
        get { cafe.cleanliness } set { cafe.cleanliness = newValue }
    }
    var customerProgress: Double {
        get { cafe.customerProgress } set { cafe.customerProgress = newValue }
    }
    var lastSaleAt: Date? {
        get { cafe.lastSaleAt } set { cafe.lastSaleAt = newValue }
    }
    var tables: Int {
        get { cafe.tables } set { cafe.tables = newValue }
    }
    var storageLevel: Int {
        get { cafe.storageLevel } set { cafe.storageLevel = newValue }
    }
    /// Fraction (0...1) of the storage cap Marble tries to keep every
    /// ingredient topped up to.
    var refillThreshold: Double {
        get { cafe.refillThreshold } set { cafe.refillThreshold = newValue }
    }
    var chipCooldown: Double {
        get { cafe.chipCooldown } set { cafe.chipCooldown = newValue }
    }

    var casinoUnlocked: Bool { lifetimeCoins >= CasinoEngine.unlockAtLifetime }
    /// Late-game Delivery channel: unlocks chain-wide once the player owns 10
    /// of the 12 cities. Derived, not persisted — same pattern as
    /// `casinoUnlocked`.
    var deliveryUnlocked: Bool { cafes.count >= 10 }
    func ownsCity(_ id: String) -> Bool { cafes.contains { $0.city == id } }

    static func newGame() -> GameState {
        var s = GameState()
        s.cafes = [CafeState.fresh(city: "home")]
        return s.normalized()
    }

    /// Fills empty café list / stock / menus (new games and migrated saves).
    func normalized() -> GameState {
        var s = self
        // repair star counts minted by the old unbounded sqrt prestige formula
        s.stars = EconomyEngine.normalizedStars(s.stars)
        if s.cafes.isEmpty { s.cafes = [CafeState.fresh(city: "home")] }
        s.activeCafe = min(max(0, s.activeCafe), s.cafes.count - 1)
        for i in s.cafes.indices {
            if s.cafes[i].stock.isEmpty { s.cafes[i].stock = Self.starterStock }
            if s.cafes[i].staffLevels.isEmpty { s.cafes[i].staffLevels = ["mocha": 1] }
            if s.cafes[i].menuEnabled.isEmpty {
                s.cafes[i].menuEnabled = MenuCatalog.items
                    .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
                    .map(\.id) + s.customItems.map(\.id)
            }
            s.cafes[i].cleanliness = min(100, max(0, s.cafes[i].cleanliness))
            s.cafes[i].refillThreshold = min(1, max(0, s.cafes[i].refillThreshold))
        }
        s.reputation = min(100, max(0, s.reputation))
        for ing in MenuCatalog.ingredients {
            if s.marketPrices[ing.id] == nil { s.marketPrices[ing.id] = ing.unitCost }
            if s.priceHistory[ing.id]?.isEmpty ?? true { s.priceHistory[ing.id] = [ing.unitCost] }
        }
        Goals.seedInitialSet(&s)
        return s
    }

    init() {}

    // MARK: codable (v1/v2 saves migrate root café fields into cafes[0])

    enum CodingKeys: String, CodingKey {
        case coins, lifetimeCoins, lifetimeCoinsThisRun, stars, lastSaved, muted
        case customItems, owner, barCharacter
        case cafes, activeCafe, reputation, adsActive, workMode
        case menuTaste, salesCount, tasteKnown
        case activeEvent, eventEndsAt, lastCriticVerdict, achievements
        case casinoWagered, casinoWon, casinoBiggestWin, casinoJackpotPot
        case marketPrices, priceHistory, season, calendarStartedAt
        case worldsVisited
        case activeGoals, goalsDay, dailyStreak, lastPlayedRealDate
        case staffColors, staffPaint
        // legacy root café fields (decode only)
        case staffLevels, equipmentLevels, stock, menuEnabled
        case cleanliness, customerProgress, lastSaleAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Double.self, forKey: .coins) ?? 0
        lifetimeCoins = try c.decodeIfPresent(Double.self, forKey: .lifetimeCoins) ?? 0
        lifetimeCoinsThisRun = try c.decodeIfPresent(Double.self, forKey: .lifetimeCoinsThisRun) ?? 0
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        lastSaved = try c.decodeIfPresent(Date.self, forKey: .lastSaved)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        customItems = try c.decodeIfPresent([CustomMenuItem].self, forKey: .customItems) ?? []
        owner = try c.decodeIfPresent(OwnerConfig.self, forKey: .owner) ?? OwnerConfig()
        barCharacter = try c.decodeIfPresent(String.self, forKey: .barCharacter) ?? "owner"
        reputation = try c.decodeIfPresent(Double.self, forKey: .reputation) ?? 50
        adsActive = try c.decodeIfPresent(Bool.self, forKey: .adsActive) ?? false
        workMode = try c.decodeIfPresent(Bool.self, forKey: .workMode) ?? false
        menuTaste = try c.decodeIfPresent([String: Int].self, forKey: .menuTaste) ?? [:]
        salesCount = try c.decodeIfPresent([String: Int].self, forKey: .salesCount) ?? [:]
        tasteKnown = try c.decodeIfPresent([String].self, forKey: .tasteKnown) ?? []
        activeEvent = try c.decodeIfPresent(String.self, forKey: .activeEvent)
        eventEndsAt = try c.decodeIfPresent(Date.self, forKey: .eventEndsAt)
        lastCriticVerdict = try c.decodeIfPresent(Bool.self, forKey: .lastCriticVerdict)
        achievements = try c.decodeIfPresent([String].self, forKey: .achievements) ?? []
        casinoWagered = try c.decodeIfPresent(Double.self, forKey: .casinoWagered) ?? 0
        casinoWon = try c.decodeIfPresent(Double.self, forKey: .casinoWon) ?? 0
        casinoBiggestWin = try c.decodeIfPresent(Double.self, forKey: .casinoBiggestWin) ?? 0
        casinoJackpotPot = try c.decodeIfPresent(Double.self, forKey: .casinoJackpotPot) ?? CasinoEngine.jackpotSeed
        marketPrices = try c.decodeIfPresent([String: Double].self, forKey: .marketPrices) ?? [:]
        priceHistory = try c.decodeIfPresent([String: [Double]].self, forKey: .priceHistory) ?? [:]
        season = try c.decodeIfPresent(Season.self, forKey: .season) ?? .spring
        calendarStartedAt = try c.decodeIfPresent(Date.self, forKey: .calendarStartedAt) ?? Date()
        worldsVisited = try c.decodeIfPresent(Int.self, forKey: .worldsVisited) ?? 0
        activeGoals = try c.decodeIfPresent([ActiveGoal].self, forKey: .activeGoals) ?? []
        goalsDay = try c.decodeIfPresent(Int.self, forKey: .goalsDay) ?? -1
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        lastPlayedRealDate = try c.decodeIfPresent(Date.self, forKey: .lastPlayedRealDate)
        staffColors = try c.decodeIfPresent([String: StaffColorPair].self, forKey: .staffColors) ?? [:]
        let decodedPaint = try c.decodeIfPresent([String: PixelArt].self, forKey: .staffPaint) ?? [:]
        staffPaint = decodedPaint.mapValues { $0.normalized }
        activeCafe = try c.decodeIfPresent(Int.self, forKey: .activeCafe) ?? 0
        if let decoded = try c.decodeIfPresent([CafeState].self, forKey: .cafes), !decoded.isEmpty {
            cafes = decoded
        } else {
            // v1/v2 migration: wrap legacy root fields into the home café
            var home = CafeState()
            home.city = "home"
            home.staffLevels = try c.decodeIfPresent([String: Int].self, forKey: .staffLevels) ?? [:]
            home.equipmentLevels = try c.decodeIfPresent([String: Int].self, forKey: .equipmentLevels) ?? [:]
            home.stock = try c.decodeIfPresent([String: Int].self, forKey: .stock) ?? [:]
            home.menuEnabled = try c.decodeIfPresent([String].self, forKey: .menuEnabled) ?? []
            home.cleanliness = try c.decodeIfPresent(Double.self, forKey: .cleanliness) ?? 100
            home.customerProgress = try c.decodeIfPresent(Double.self, forKey: .customerProgress) ?? 0
            home.lastSaleAt = try c.decodeIfPresent(Date.self, forKey: .lastSaleAt)
            cafes = [home]
            activeCafe = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(coins, forKey: .coins)
        try c.encode(lifetimeCoins, forKey: .lifetimeCoins)
        try c.encode(lifetimeCoinsThisRun, forKey: .lifetimeCoinsThisRun)
        try c.encode(stars, forKey: .stars)
        try c.encodeIfPresent(lastSaved, forKey: .lastSaved)
        try c.encode(muted, forKey: .muted)
        try c.encode(customItems, forKey: .customItems)
        try c.encode(owner, forKey: .owner)
        try c.encode(barCharacter, forKey: .barCharacter)
        try c.encode(cafes, forKey: .cafes)
        try c.encode(activeCafe, forKey: .activeCafe)
        try c.encode(reputation, forKey: .reputation)
        try c.encode(adsActive, forKey: .adsActive)
        try c.encode(workMode, forKey: .workMode)
        try c.encode(menuTaste, forKey: .menuTaste)
        try c.encode(salesCount, forKey: .salesCount)
        try c.encode(tasteKnown, forKey: .tasteKnown)
        try c.encodeIfPresent(activeEvent, forKey: .activeEvent)
        try c.encodeIfPresent(eventEndsAt, forKey: .eventEndsAt)
        try c.encodeIfPresent(lastCriticVerdict, forKey: .lastCriticVerdict)
        try c.encode(achievements, forKey: .achievements)
        try c.encode(casinoWagered, forKey: .casinoWagered)
        try c.encode(casinoWon, forKey: .casinoWon)
        try c.encode(casinoBiggestWin, forKey: .casinoBiggestWin)
        try c.encode(casinoJackpotPot, forKey: .casinoJackpotPot)
        try c.encode(marketPrices, forKey: .marketPrices)
        try c.encode(priceHistory, forKey: .priceHistory)
        try c.encode(season, forKey: .season)
        try c.encode(calendarStartedAt, forKey: .calendarStartedAt)
        try c.encode(worldsVisited, forKey: .worldsVisited)
        try c.encode(activeGoals, forKey: .activeGoals)
        try c.encode(goalsDay, forKey: .goalsDay)
        try c.encode(dailyStreak, forKey: .dailyStreak)
        try c.encodeIfPresent(lastPlayedRealDate, forKey: .lastPlayedRealDate)
        try c.encode(staffColors, forKey: .staffColors)
        try c.encode(staffPaint, forKey: .staffPaint)
    }
}

extension GameState: Equatable {
    /// Excludes `calendarStartedAt` from equality — like `lastSaved`, it's a
    /// wall-clock construction-time anchor, not gameplay state. Two
    /// otherwise-identical states built moments apart (e.g. two separate
    /// `GameState.newGame()` calls in a test) shouldn't compare unequal just
    /// because their anchors differ by a few milliseconds.
    static func == (lhs: GameState, rhs: GameState) -> Bool {
        lhs.coins == rhs.coins
            && lhs.lifetimeCoins == rhs.lifetimeCoins
            && lhs.lifetimeCoinsThisRun == rhs.lifetimeCoinsThisRun
            && lhs.stars == rhs.stars
            && lhs.lastSaved == rhs.lastSaved
            && lhs.muted == rhs.muted
            && lhs.customItems == rhs.customItems
            && lhs.owner == rhs.owner
            && lhs.barCharacter == rhs.barCharacter
            && lhs.cafes == rhs.cafes
            && lhs.activeCafe == rhs.activeCafe
            && lhs.reputation == rhs.reputation
            && lhs.adsActive == rhs.adsActive
            && lhs.workMode == rhs.workMode
            && lhs.menuTaste == rhs.menuTaste
            && lhs.salesCount == rhs.salesCount
            && lhs.tasteKnown == rhs.tasteKnown
            && lhs.activeEvent == rhs.activeEvent
            && lhs.eventEndsAt == rhs.eventEndsAt
            && lhs.lastCriticVerdict == rhs.lastCriticVerdict
            && lhs.achievements == rhs.achievements
            && lhs.casinoWagered == rhs.casinoWagered
            && lhs.casinoWon == rhs.casinoWon
            && lhs.casinoBiggestWin == rhs.casinoBiggestWin
            && lhs.casinoJackpotPot == rhs.casinoJackpotPot
            && lhs.marketPrices == rhs.marketPrices
            && lhs.priceHistory == rhs.priceHistory
            && lhs.season == rhs.season
            && lhs.worldsVisited == rhs.worldsVisited
            && lhs.activeGoals == rhs.activeGoals
            && lhs.goalsDay == rhs.goalsDay
            && lhs.dailyStreak == rhs.dailyStreak
            && lhs.staffColors == rhs.staffColors
            && lhs.staffPaint == rhs.staffPaint
    }
}
