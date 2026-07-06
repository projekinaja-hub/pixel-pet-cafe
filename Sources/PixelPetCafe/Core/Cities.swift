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
        CityDef(id: "home",   name: "Home Town",   vibe: "Warm & cozy",        cost: 0,         rateBonus: 1.0, priceBonus: 1.0),
        CityDef(id: "sakura", name: "Sakura Town", vibe: "Cherry blossoms 🌸", cost: 250_000,   rateBonus: 1.3, priceBonus: 1.0),
        CityDef(id: "neon",   name: "Neon City",   vibe: "Nightlife & neon 🌙", cost: 2_000_000, rateBonus: 1.0, priceBonus: 1.5),
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
