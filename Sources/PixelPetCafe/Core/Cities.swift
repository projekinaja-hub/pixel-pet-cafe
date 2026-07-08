import Foundation

struct CityDef {
    let id: String
    let name: String
    let vibe: String
    let cost: Double
    let rateBonus: Double    // × customer rate
    let priceBonus: Double   // × prices
    var taste: [ItemCategory: Double] = [:]   // locals' category cravings

    func tasteWeight(_ category: ItemCategory) -> Double { taste[category] ?? 1.0 }
}

enum Cities {
    static let all: [CityDef] = [
        CityDef(id: "home",    name: "Home Town",     vibe: "Warm & cozy",         cost: 0,        rateBonus: 1.0,  priceBonus: 1.0),
        CityDef(id: "sakura",  name: "Sakura Town",   vibe: "Cherry blossoms 🌸",  cost: 250_000,  rateBonus: 1.3,  priceBonus: 1.0),
        CityDef(id: "neon",    name: "Neon City",     vibe: "Nightlife & neon 🌙", cost: 2e6,      rateBonus: 1.0,  priceBonus: 1.5),
        CityDef(id: "seaside", name: "Seaside Bay",   vibe: "Salt air & surf 🌊",  cost: 20e6,     rateBonus: 1.45, priceBonus: 1.1),
        CityDef(id: "forest",  name: "Whisperwood",   vibe: "Deep green calm 🌲",  cost: 150e6,    rateBonus: 1.3,  priceBonus: 1.3),
        CityDef(id: "desert",  name: "Oasis Dunes",   vibe: "Golden heat 🏜️",      cost: 1e9,      rateBonus: 1.1,  priceBonus: 1.7),
        CityDef(id: "snowy",   name: "Frostpeak",     vibe: "Cocoa weather ❄️",    cost: 8e9,      rateBonus: 1.6,  priceBonus: 1.25),
        CityDef(id: "sunset",  name: "Amber Harbor",  vibe: "Endless golden hour 🌅", cost: 60e9,  rateBonus: 1.35, priceBonus: 1.6),
        CityDef(id: "ember",   name: "Emberfall",     vibe: "Volcanic springs 🌋", cost: 500e9,    rateBonus: 1.8,  priceBonus: 1.4),
        CityDef(id: "royal",   name: "Crown Court",   vibe: "Royal patronage 👑",  cost: 5e12,     rateBonus: 1.4,  priceBonus: 2.0),
        CityDef(id: "cloud",   name: "Cloudspire",    vibe: "Above the sky ☁️",    cost: 50e12,    rateBonus: 2.0,  priceBonus: 1.7),
        CityDef(id: "moon",    name: "Mare Café",     vibe: "Earthrise views 🌕",  cost: 800e12,   rateBonus: 2.0,  priceBonus: 2.2),
    ]

    static let tastes: [String: [ItemCategory: Double]] = [
        "home":    [:],
        "sakura":  [.pastry: 1.5, .special: 1.2, .drink: 0.8],
        "neon":    [.drink: 1.4, .special: 1.3, .pastry: 0.7],
        "seaside": [.drink: 1.4, .pastry: 0.9],
        "forest":  [.pastry: 1.5, .drink: 0.9],
        "desert":  [.drink: 1.7, .pastry: 0.6],
        "snowy":   [.drink: 1.5, .special: 1.3, .pastry: 0.8],
        "sunset":  [.special: 1.5, .drink: 1.1, .pastry: 0.8],
        "ember":   [.drink: 1.3, .special: 1.4, .pastry: 0.7],
        "royal":   [.special: 1.8, .pastry: 1.1, .drink: 0.7],
        "cloud":   [.pastry: 1.4, .special: 1.3, .drink: 0.9],
        "moon":    [.special: 1.6, .drink: 1.2, .pastry: 0.9],
    ]

    static func def(_ id: String) -> CityDef {
        var d = all.first { $0.id == id } ?? all[0]
        d.taste = tastes[d.id] ?? [:]
        return d
    }
}

/// One café location. The active café is the only one operating.
struct CafeState: Equatable {
    var city: String = "home"
    var staffLevels: [String: Int] = [:]
    var equipmentLevels: [String: Int] = [:]
    var stock: [String: Int] = [:]
    var menuEnabled: [String] = []
    var cleanliness: Double = 100
    var customerProgress: Double = 0
    var lastSaleAt: Date?
    var tables: Int = 2
    /// Ingredient id -> smoothed units-consumed-per-second (rolling EMA), used
    /// to size the spoilage buffer so normal buffer-stocking never spoils.
    var consumptionEMA: [String: Double] = [:]
    /// Pantry upgrade level — see EconomyEngine.storageCap. Same numeric cap
    /// applies to every ingredient's stock in this café (not a shared pool).
    var storageLevel: Int = 0
    /// Fraction (0...1) of the storage cap Marble's auto-restock tries to
    /// keep every ingredient topped up to. Defaults to 1.0 (top off
    /// completely) to match the pre-cap behavior every existing save saw.
    var refillThreshold: Double = 1.0

    static func fresh(city: String) -> CafeState {
        var c = CafeState()
        c.city = city
        c.staffLevels = ["mocha": 1]
        c.stock = GameState.starterStock
        c.tables = 2
        return c
    }
}

extension CafeState: Codable {
    enum CodingKeys: String, CodingKey {
        case city, staffLevels, equipmentLevels, stock, menuEnabled
        case cleanliness, customerProgress, lastSaleAt, tables, consumptionEMA
        case storageLevel, refillThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? "home"
        staffLevels = try c.decodeIfPresent([String: Int].self, forKey: .staffLevels) ?? [:]
        equipmentLevels = try c.decodeIfPresent([String: Int].self, forKey: .equipmentLevels) ?? [:]
        stock = try c.decodeIfPresent([String: Int].self, forKey: .stock) ?? [:]
        menuEnabled = try c.decodeIfPresent([String].self, forKey: .menuEnabled) ?? []
        cleanliness = try c.decodeIfPresent(Double.self, forKey: .cleanliness) ?? 100
        customerProgress = try c.decodeIfPresent(Double.self, forKey: .customerProgress) ?? 0
        lastSaleAt = try c.decodeIfPresent(Date.self, forKey: .lastSaleAt)
        tables = try c.decodeIfPresent(Int.self, forKey: .tables) ?? 2
        consumptionEMA = try c.decodeIfPresent([String: Double].self, forKey: .consumptionEMA) ?? [:]
        storageLevel = try c.decodeIfPresent(Int.self, forKey: .storageLevel) ?? 0
        refillThreshold = try c.decodeIfPresent(Double.self, forKey: .refillThreshold) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(city, forKey: .city)
        try c.encode(staffLevels, forKey: .staffLevels)
        try c.encode(equipmentLevels, forKey: .equipmentLevels)
        try c.encode(stock, forKey: .stock)
        try c.encode(menuEnabled, forKey: .menuEnabled)
        try c.encode(cleanliness, forKey: .cleanliness)
        try c.encode(customerProgress, forKey: .customerProgress)
        try c.encodeIfPresent(lastSaleAt, forKey: .lastSaleAt)
        try c.encode(tables, forKey: .tables)
        try c.encode(consumptionEMA, forKey: .consumptionEMA)
        try c.encode(storageLevel, forKey: .storageLevel)
        try c.encode(refillThreshold, forKey: .refillThreshold)
    }
}
