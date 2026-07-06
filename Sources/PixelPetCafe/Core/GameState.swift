import Foundation

struct OwnerConfig: Codable, Equatable {
    var species: String = "cat"      // cat, corgi, bunny, fox, bear, owl
    var palette: String = "brown"    // brown, cream, orange, gray
    var accessory: String = "none"   // none, bow, cap, glasses, scarf
    var cafeName: String = "Pixel Pet Café"

    static let speciesOptions = ["cat", "corgi", "bunny", "fox", "bear", "owl"]
    static let paletteOptions = ["brown", "cream", "orange", "gray"]
    static let accessoryOptions = ["none", "bow", "cap", "glasses", "scarf"]
}

/// Entire savable game state. Pure data — rules live in EconomyEngine/SalesEngine.
/// Decoding is backward compatible: every field missing from an old save gets
/// its default, then `normalized()` fills starter stock/menu.
struct GameState: Codable, Equatable {
    var coins: Double = 0
    var lifetimeCoins: Double = 0
    var lifetimeCoinsThisRun: Double = 0
    var staffLevels: [String: Int] = [:]
    var equipmentLevels: [String: Int] = [:]
    var stars: Int = 0
    var lastSaved: Date?
    var muted: Bool = false
    // v2
    var stock: [String: Int] = [:]
    var menuEnabled: [String] = []
    var customItems: [CustomMenuItem] = []
    var cleanliness: Double = 100
    var customerProgress: Double = 0
    var owner: OwnerConfig = OwnerConfig()
    var barCharacter: String = "owner"   // "owner" or a staff id
    var lastSaleAt: Date?

    static let starterStock: [String: Int] = ["beans": 40, "milk": 25, "flour": 20, "sugar": 20]

    static func newGame() -> GameState {
        var s = GameState()
        s.staffLevels["mocha"] = 1
        return s.normalized()
    }

    /// Fills empty stock/menu (new games and migrated v1 saves).
    func normalized() -> GameState {
        var s = self
        if s.stock.isEmpty { s.stock = Self.starterStock }
        if s.menuEnabled.isEmpty {
            s.menuEnabled = MenuCatalog.items
                .filter { s.lifetimeCoins >= $0.unlockAtLifetime }
                .map(\.id)
            s.menuEnabled += s.customItems.map(\.id)
        }
        s.cleanliness = min(100, max(0, s.cleanliness))
        return s
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Double.self, forKey: .coins) ?? 0
        lifetimeCoins = try c.decodeIfPresent(Double.self, forKey: .lifetimeCoins) ?? 0
        lifetimeCoinsThisRun = try c.decodeIfPresent(Double.self, forKey: .lifetimeCoinsThisRun) ?? 0
        staffLevels = try c.decodeIfPresent([String: Int].self, forKey: .staffLevels) ?? [:]
        equipmentLevels = try c.decodeIfPresent([String: Int].self, forKey: .equipmentLevels) ?? [:]
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        lastSaved = try c.decodeIfPresent(Date.self, forKey: .lastSaved)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        stock = try c.decodeIfPresent([String: Int].self, forKey: .stock) ?? [:]
        menuEnabled = try c.decodeIfPresent([String].self, forKey: .menuEnabled) ?? []
        customItems = try c.decodeIfPresent([CustomMenuItem].self, forKey: .customItems) ?? []
        cleanliness = try c.decodeIfPresent(Double.self, forKey: .cleanliness) ?? 100
        customerProgress = try c.decodeIfPresent(Double.self, forKey: .customerProgress) ?? 0
        owner = try c.decodeIfPresent(OwnerConfig.self, forKey: .owner) ?? OwnerConfig()
        barCharacter = try c.decodeIfPresent(String.self, forKey: .barCharacter) ?? "owner"
        lastSaleAt = try c.decodeIfPresent(Date.self, forKey: .lastSaleAt)
    }
}
