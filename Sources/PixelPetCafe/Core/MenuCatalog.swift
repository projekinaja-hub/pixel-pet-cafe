import Foundation

enum ItemCategory: String, Codable, CaseIterable {
    case drink, pastry, special
}

struct IngredientDef {
    let id: String
    let name: String
    let emoji: String
    let unitCost: Double
}

struct MenuItemDef {
    let id: String
    let name: String
    let icon: String            // item_<icon>.png sprite id
    let category: ItemCategory
    let unlockAtLifetime: Double
    let ingredients: [String: Int]
    let basePrice: Double
}

/// A player-created menu item. Price is derived from ingredient cost so custom
/// items are always viable: cost × CUSTOM_MARGIN.
struct CustomMenuItem: Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var category: ItemCategory
    var ingredients: [String: Int]
}

/// A menu entry resolved for the simulation (built-in or custom).
struct ResolvedItem: Equatable {
    let id: String
    let name: String
    let icon: String
    let category: ItemCategory
    let ingredients: [String: Int]
    let basePrice: Double
    let isCustom: Bool
}

enum MenuCatalog {
    static let customMargin = 6.0

    static let ingredients: [IngredientDef] = [
        IngredientDef(id: "beans",  name: "Coffee Beans", emoji: "🫘", unitCost: 2),
        IngredientDef(id: "milk",   name: "Milk",         emoji: "🥛", unitCost: 3),
        IngredientDef(id: "flour",  name: "Flour",        emoji: "🌾", unitCost: 2),
        IngredientDef(id: "sugar",  name: "Sugar",        emoji: "🧂", unitCost: 1),
        IngredientDef(id: "matcha", name: "Matcha",       emoji: "🍵", unitCost: 6),
        IngredientDef(id: "cocoa",  name: "Cocoa",        emoji: "🍫", unitCost: 4),
        IngredientDef(id: "berry",  name: "Berries",      emoji: "🍓", unitCost: 5),
        IngredientDef(id: "honey",  name: "Honey",        emoji: "🍯", unitCost: 8),
    ]

    static let items: [MenuItemDef] = [
        MenuItemDef(id: "espresso_shot", name: "Espresso",     icon: "espresso",     category: .drink,
                    unlockAtLifetime: 0,         ingredients: ["beans": 1],                         basePrice: 8),
        MenuItemDef(id: "latte",         name: "Latte",        icon: "latte",        category: .drink,
                    unlockAtLifetime: 120,       ingredients: ["beans": 1, "milk": 1],              basePrice: 15),
        MenuItemDef(id: "croissant",     name: "Croissant",    icon: "croissant",    category: .pastry,
                    unlockAtLifetime: 1_500,     ingredients: ["flour": 2, "sugar": 1],             basePrice: 20),
        MenuItemDef(id: "matcha_latte",  name: "Matcha Latte", icon: "matcha_latte", category: .drink,
                    unlockAtLifetime: 18_000,    ingredients: ["matcha": 1, "milk": 1],             basePrice: 34),
        MenuItemDef(id: "hot_cocoa",     name: "Hot Cocoa",    icon: "cocoa",        category: .drink,
                    unlockAtLifetime: 120_000,   ingredients: ["cocoa": 1, "milk": 1, "sugar": 1],  basePrice: 38),
        MenuItemDef(id: "berry_tart",    name: "Berry Tart",   icon: "berry_tart",   category: .pastry,
                    unlockAtLifetime: 800_000,   ingredients: ["flour": 2, "berry": 2, "sugar": 1], basePrice: 68),
        MenuItemDef(id: "honey_cake",    name: "Honey Cake",   icon: "honey_cake",   category: .special,
                    unlockAtLifetime: 5_000_000, ingredients: ["flour": 2, "honey": 1, "sugar": 2], basePrice: 98),
    ]

    static let itemIcons = ["espresso", "latte", "croissant", "matcha_latte",
                            "cocoa", "berry_tart", "honey_cake", "cookie"]

    static func ingredientDef(_ id: String) -> IngredientDef? { ingredients.first { $0.id == id } }
    static func itemDef(_ id: String) -> MenuItemDef? { items.first { $0.id == id } }

    static func ingredientCost(_ ingredients: [String: Int]) -> Double {
        ingredients.reduce(0) { $0 + Double($1.value) * (ingredientDef($1.key)?.unitCost ?? 0) }
    }

    static func customPrice(_ item: CustomMenuItem) -> Double {
        (ingredientCost(item.ingredients) * customMargin).rounded()
    }

    /// Pack purchase: 25 units at cost, 100 units at 10% off. Uses the flat
    /// base unitCost — kept for callers that want the static reference price.
    static func packCost(_ id: String, units: Int) -> Double {
        let unit = ingredientDef(id)?.unitCost ?? 0
        let discount = units >= 100 ? 0.9 : 1.0
        return (unit * Double(units) * discount).rounded()
    }

    /// The ingredient's live market price: `MarketEngine.drift`'s random walk
    /// (falling back to the flat base cost for any ingredient the market
    /// hasn't priced yet — e.g. a save that predates the market system)
    /// multiplied by the current season's price effect (see
    /// `SeasonalPricing`). The two effects compose independently — the
    /// random walk's own clamp is checked against the flat base cost and
    /// never sees the seasonal multiplier at all.
    static func currentUnitCost(_ id: String, _ s: GameState) -> Double {
        let raw = s.marketPrices[id] ?? ingredientDef(id)?.unitCost ?? 0
        return raw * SeasonalPricing.multiplier(id, s.season) * supplierTier(s)
    }

    /// Premium suppliers: sale prices scale exponentially with equipment
    /// (equipMultiplier), but ingredient costs used to stay pinned near their
    /// flat base — so late-game margins approached 100% and money flooded
    /// in ("we get too much money now"). A top-tier kitchen now sources
    /// top-tier ingredients: unit cost scales with equipMultiplier^0.9 —
    /// slightly sub-linear so upgrading is always still net-positive, but
    /// cost-of-goods stays a real, growing share of revenue instead of
    /// rounding to zero. A fresh café (equipMultiplier 1) is unaffected.
    static let supplierTierExponent = 0.9
    static func supplierTier(_ s: GameState) -> Double {
        pow(SalesEngine.equipMultiplier(s), supplierTierExponent)
    }

    /// Marble's experience shaves a bit off every pack purchase (manual or
    /// her own auto-restock), on top of just being hired — level 1 only
    /// gates whether she acts at all (see SalesEngine.managerTarget), so
    /// without this every level past 1 did literally nothing. Floors at 50%
    /// off (level 50) rather than trending toward free.
    static let marbleDiscountPerLevel = 0.01
    static let marbleDiscountFloor = 0.5
    static func marbleDiscount(_ s: GameState) -> Double {
        let level = s.staffLevels["marble"] ?? 0
        guard level > 1 else { return 1 }
        return max(marbleDiscountFloor, 1 - marbleDiscountPerLevel * Double(level - 1))
    }

    /// Pack purchase priced off the *live* market price rather than the flat
    /// base cost: 25 units at cost, 100 units at 10% off, further discounted
    /// by Marble's level if she's hired.
    static func livePackCost(_ id: String, units: Int, _ s: GameState) -> Double {
        let unit = currentUnitCost(id, s)
        let bulkDiscount = units >= 100 ? 0.9 : 1.0
        return (unit * Double(units) * bulkDiscount * marbleDiscount(s)).rounded()
    }

    static func resolve(_ s: GameState) -> [ResolvedItem] {
        var out: [ResolvedItem] = []
        for def in items where s.lifetimeCoins >= def.unlockAtLifetime && s.menuEnabled.contains(def.id) {
            out.append(ResolvedItem(id: def.id, name: def.name, icon: def.icon, category: def.category,
                                    ingredients: def.ingredients, basePrice: def.basePrice, isCustom: false))
        }
        for c in s.customItems where s.menuEnabled.contains(c.id) {
            out.append(ResolvedItem(id: c.id, name: c.name, icon: c.icon, category: c.category,
                                    ingredients: c.ingredients, basePrice: customPrice(c), isCustom: true))
        }
        return out
    }
}
