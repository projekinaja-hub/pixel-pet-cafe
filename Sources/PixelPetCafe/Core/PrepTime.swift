import Foundation

/// Per-item prep time — how long it takes staff to make one unit, before any
/// equipment speed bonus. Deliberately a standalone lookup table (keyed by
/// item id, with a category-based fallback) rather than a new stored field on
/// `MenuItemDef`/`CustomMenuItem`/`ResolvedItem` — those are hand-constructed
/// in several places across the codebase, and threading a new field through
/// every call site is unnecessary risk for a value that's pure static data.
enum PrepTime {
    /// Seconds to prepare one unit at equipment level 0 (base, unmodified by
    /// speed effects). Espresso is the quick grab-and-go order; drinks that
    /// need steaming/whisking take longer; pastries and the honey cake
    /// showpiece take longer still.
    static let base: [String: Double] = [
        "espresso_shot": 5,
        "latte":         12,
        "matcha_latte":  13,
        "hot_cocoa":     14,
        "croissant":     20,
        "berry_tart":    26,
        "honey_cake":    32,
    ]

    /// Fallback for ids not in the table above — covers every player-created
    /// `CustomMenuItem` (which has no static catalog entry) without needing
    /// any new stored/Codable field on it.
    static func fallback(for category: ItemCategory) -> Double {
        switch category {
        case .drink:   return 10
        case .pastry:  return 22
        case .special: return 24
        }
    }

    static func base(_ item: ResolvedItem) -> Double {
        base[item.id] ?? fallback(for: item.category)
    }
}
