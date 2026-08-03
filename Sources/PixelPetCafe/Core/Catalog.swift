import Foundation

struct StaffDef {
    let id: String
    let name: String
    let role: String
    let baseRate: Double        // coins/sec per level
    let baseCost: Double
    let unlockAtLifetime: Double
}

struct EquipmentDef {
    let id: String
    let name: String
    let baseCost: Double
    /// Legacy per-level income multiplier. ECONOMY V2 no longer reads this —
    /// every equipment level grants a flat +6% (SalesEngine.
    /// equipBenefitPerLevel) regardless of which piece of gear it's on.
    let multPerLevel: Double
    /// Prep-time speed effect: divides prep time by (speedMultPerLevel^level)
    /// for every item in `speedCategories`. Defaults mean "no speed role" —
    /// existing equipment definitions that don't set these behave exactly as
    /// before.
    var speedMultPerLevel: Double = 1.0
    var speedCategories: Set<ItemCategory> = []
}

enum Catalog {
    static let staff: [StaffDef] = [
        StaffDef(id: "mocha",   name: "Mocha",   role: "Barista",     baseRate: 1,     baseCost: 15,        unlockAtLifetime: 0),
        StaffDef(id: "biscuit", name: "Biscuit", role: "Waiter",      baseRate: 6,     baseCost: 220,       unlockAtLifetime: 120),
        StaffDef(id: "chip",    name: "Chip",    role: "Cleaner",     baseRate: 0,     baseCost: 900,       unlockAtLifetime: 800),
        StaffDef(id: "poppy",   name: "Poppy",   role: "Pâtissier",   baseRate: 32,    baseCost: 2_800,     unlockAtLifetime: 1_500),
        StaffDef(id: "juno",    name: "Juno",    role: "Cashier",     baseRate: 160,   baseCost: 32_000,    unlockAtLifetime: 18_000),
        StaffDef(id: "bo",      name: "Bo",      role: "Roaster",     baseRate: 900,   baseCost: 400_000,   unlockAtLifetime: 220_000),
        StaffDef(id: "earl",    name: "Earl",    role: "Night Shift", baseRate: 4_500, baseCost: 5_000_000, unlockAtLifetime: 2_500_000),
        StaffDef(id: "marble",  name: "Marble",  role: "Manager",     baseRate: 0,     baseCost: 1_000_000, unlockAtLifetime: 500_000),
        // Comet, the arctic fox in a bubble helmet — the roster's last hire.
        // Follows the step Earl set (~5x rate, ~10x cost, ~10x unlock), so the
        // curve past 2.5M lifetime keeps its shape instead of flattening out.
        StaffDef(id: "comet",   name: "Comet",   role: "Astro-Barista", baseRate: 25_000, baseCost: 60_000_000, unlockAtLifetime: 25_000_000),
    ]

    static let equipment: [EquipmentDef] = [
        EquipmentDef(id: "espresso", name: "Espresso Machine", baseCost: 100,     multPerLevel: 1.10,
                     speedMultPerLevel: 1.06, speedCategories: [.drink]),
        EquipmentDef(id: "grinder",  name: "Bean Grinder",     baseCost: 1_200,   multPerLevel: 1.09,
                     speedMultPerLevel: 1.02, speedCategories: [.drink]),
        EquipmentDef(id: "oven",     name: "Stone Oven",       baseCost: 9_000,   multPerLevel: 1.09,
                     speedMultPerLevel: 1.08, speedCategories: [.pastry, .special]),
        EquipmentDef(id: "decor",    name: "Cozy Decor",       baseCost: 60_000,  multPerLevel: 1.08),
        EquipmentDef(id: "sound",    name: "Sound System",     baseCost: 450_000, multPerLevel: 1.08),
    ]


    static func staffDef(_ id: String) -> StaffDef? { staff.first { $0.id == id } }
    static func equipmentDef(_ id: String) -> EquipmentDef? { equipment.first { $0.id == id } }
}
