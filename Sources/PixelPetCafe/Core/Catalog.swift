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
    let multPerLevel: Double    // income ×(multPerLevel^level)
}

enum Catalog {
    static let staff: [StaffDef] = [
        StaffDef(id: "mocha",   name: "Mocha",   role: "Barista",     baseRate: 1,     baseCost: 15,        unlockAtLifetime: 0),
        StaffDef(id: "biscuit", name: "Biscuit", role: "Waiter",      baseRate: 6,     baseCost: 220,       unlockAtLifetime: 120),
        StaffDef(id: "poppy",   name: "Poppy",   role: "Pâtissier",   baseRate: 32,    baseCost: 2_800,     unlockAtLifetime: 1_500),
        StaffDef(id: "juno",    name: "Juno",    role: "Cashier",     baseRate: 160,   baseCost: 32_000,    unlockAtLifetime: 18_000),
        StaffDef(id: "bo",      name: "Bo",      role: "Roaster",     baseRate: 900,   baseCost: 400_000,   unlockAtLifetime: 220_000),
        StaffDef(id: "earl",    name: "Earl",    role: "Night Shift", baseRate: 4_500, baseCost: 5_000_000, unlockAtLifetime: 2_500_000),
    ]

    static let equipment: [EquipmentDef] = [
        EquipmentDef(id: "espresso", name: "Espresso Machine", baseCost: 100,     multPerLevel: 1.25),
        EquipmentDef(id: "grinder",  name: "Bean Grinder",     baseCost: 1_200,   multPerLevel: 1.20),
        EquipmentDef(id: "oven",     name: "Stone Oven",       baseCost: 9_000,   multPerLevel: 1.22),
        EquipmentDef(id: "decor",    name: "Cozy Decor",       baseCost: 60_000,  multPerLevel: 1.18),
        EquipmentDef(id: "sound",    name: "Sound System",     baseCost: 450_000, multPerLevel: 1.20),
    ]


    static func staffDef(_ id: String) -> StaffDef? { staff.first { $0.id == id } }
    static func equipmentDef(_ id: String) -> EquipmentDef? { equipment.first { $0.id == id } }
}
