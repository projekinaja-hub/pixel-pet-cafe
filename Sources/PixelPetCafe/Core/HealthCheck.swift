import Foundation

/// Pure "is this actually healthy right now" judgments for the at-a-glance
/// dashboard (PanelView's DashboardOverlay). Deliberately display-agnostic —
/// returns a severity + plain-language label, and the SwiftUI layer maps
/// severity to a Theme color. Kept separate from SalesEngine/EconomyEngine
/// so these read as diagnostics rather than simulation rules.
enum HealthCheck {
    enum Severity {
        case good, warning, critical
    }

    struct Tier: Equatable {
        let label: String
        let severity: Severity

        static func == (lhs: Tier, rhs: Tier) -> Bool {
            lhs.label == rhs.label && lhs.severity == rhs.severity
        }
    }

    // MARK: reputation

    /// Plain-language read on the 0-100 reputation number — the dashboard's
    /// whole point is not making the player do this translation themselves.
    static func reputationTier(_ value: Double) -> Tier {
        switch value {
        case ..<20: return Tier(label: "Struggling", severity: .critical)
        case ..<40: return Tier(label: "Shaky", severity: .warning)
        case ..<60: return Tier(label: "Steady", severity: .good)
        case ..<80: return Tier(label: "Solid", severity: .good)
        default:    return Tier(label: "Beloved", severity: .good)
        }
    }

    // MARK: cleanliness

    static func cleanlinessTier(_ value: Double) -> Tier {
        switch value {
        case ..<25: return Tier(label: "Filthy", severity: .critical)
        case ..<50: return Tier(label: "Grubby", severity: .warning)
        case ..<75: return Tier(label: "Tidy", severity: .good)
        default:    return Tier(label: "Spotless", severity: .good)
        }
    }

    // MARK: throughput

    /// Is the kitchen keeping up with who's walking in right now? Mirrors
    /// Rows.swift's ThroughputCard bool, but as a graded severity — a small
    /// shortfall reads as a warning, a large one as critical, so the
    /// dashboard doesn't cry wolf over comfortable margins.
    static func throughputTier(capacityPerSec: Double, customerRate: Double) -> Tier {
        guard customerRate > 0 else { return Tier(label: "Quiet", severity: .good) }
        guard capacityPerSec.isFinite else {
            return Tier(label: "Nothing servable — kitchen idle", severity: .critical)
        }
        let ratio = capacityPerSec / customerRate
        if ratio < 0.6 { return Tier(label: "Badly bottlenecked", severity: .critical) }
        if ratio < 1.0 { return Tier(label: "Falling behind", severity: .warning) }
        return Tier(label: "Keeping up", severity: .good)
    }

    // MARK: storage

    /// Average fill percentage (0...100) across every ingredient's stock vs.
    /// the café's storage cap — one glanceable number instead of eight bars.
    static func storageFillPercent(stock: [String: Int], ingredientIds: [String], cap: Int) -> Double {
        guard cap > 0, !ingredientIds.isEmpty else { return 0 }
        let total = ingredientIds.reduce(0.0) { partial, id in
            partial + min(100.0, 100.0 * Double(stock[id] ?? 0) / Double(cap))
        }
        return total / Double(ingredientIds.count)
    }

    static func storageTier(fillPercent: Double) -> Tier {
        switch fillPercent {
        case ..<15: return Tier(label: "Nearly empty", severity: .critical)
        case ..<35: return Tier(label: "Running low", severity: .warning)
        default:    return Tier(label: "Well stocked", severity: .good)
        }
    }

    // MARK: seasonal price alert

    struct SeasonalAlert: Equatable {
        let ingredientId: String
        let multiplier: Double   // SeasonalPricing.multiplier for this ingredient/season
        var cheaper: Bool { multiplier < 1.0 }
    }

    /// The single most notable seasonal price swing among the café's
    /// ingredients right now (furthest from the season-neutral 1.0×), if any
    /// — a "matcha's 25% cheaper this season" style callout. Returns nil when
    /// nothing is currently discounted or surcharged.
    static func notableSeasonalPrice(ingredientIds: [String], season: Season) -> SeasonalAlert? {
        let alerts = ingredientIds
            .map { SeasonalAlert(ingredientId: $0, multiplier: SeasonalPricing.multiplier($0, season)) }
            .filter { abs($0.multiplier - 1.0) >= 0.05 }
        return alerts.max { abs($0.multiplier - 1.0) < abs($1.multiplier - 1.0) }
    }
}
