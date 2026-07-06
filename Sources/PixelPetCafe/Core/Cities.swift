import Foundation

struct CityDef {
    let id: String
    let name: String
    let vibe: String
    let cost: Double
    let rateBonus: Double    // × customer rate
    let priceBonus: Double   // × prices
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

    static func def(_ id: String) -> CityDef {
        all.first { $0.id == id } ?? all[0]
    }
}

/// One café location. The active café is the only one operating.
struct CafeState: Codable, Equatable {
    var city: String = "home"
    var staffLevels: [String: Int] = [:]
    var equipmentLevels: [String: Int] = [:]
    var stock: [String: Int] = [:]
    var menuEnabled: [String] = []
    var cleanliness: Double = 100
    var customerProgress: Double = 0
    var lastSaleAt: Date?

    static func fresh(city: String) -> CafeState {
        var c = CafeState()
        c.city = city
        c.staffLevels = ["mocha": 1]
        c.stock = GameState.starterStock
        return c
    }
}
