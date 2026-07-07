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
struct GameState: Codable, Equatable {
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

    var casinoUnlocked: Bool { lifetimeCoins >= CasinoEngine.unlockAtLifetime }
    func ownsCity(_ id: String) -> Bool { cafes.contains { $0.city == id } }

    static func newGame() -> GameState {
        var s = GameState()
        s.cafes = [CafeState.fresh(city: "home")]
        return s.normalized()
    }

    /// Fills empty café list / stock / menus (new games and migrated saves).
    func normalized() -> GameState {
        var s = self
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
        }
        s.reputation = min(100, max(0, s.reputation))
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
        case casinoWagered, casinoWon, casinoBiggestWin
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
    }
}
