import SwiftUI

/// Small icon button that opens the "how's my café doing" dashboard. Lives in
/// PanelView's existing top ZStack (the same proven overlay layer AwayToast
/// and the event banner already use) so it never touches header/tabBar/the
/// scroll area — just a corner tap target above the SpriteView.
struct DashboardEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.cream)
                .frame(width: 24, height: 24)
                .background(Theme.bg.opacity(0.75))
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.gold.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("How's my café doing?")
    }
}

/// Glanceable "is anything actually wrong right now" dashboard. Dismissible
/// via the scrim, the close button, or tapping the card's own close control.
/// Sized to live comfortably inside the fixed 360×544 popover, scrolling
/// internally (its own ScrollView — never the tab-content one) if content
/// ever runs long.
struct DashboardOverlay: View {
    @ObservedObject var controller: GameController
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    Text("📊 Café Health")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        overallBanner
                        reputationRow
                        cleanlinessRow
                        seasonRow
                        throughputRow
                        storageRow
                        if controller.hasStockOut { stockOutRow }
                        if controller.isClosed { closedRow }
                        if controller.state.deliveryUnlocked { deliveryRow }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 420)
            }
            .frame(width: 320)
            .background(Theme.bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
        .frame(width: 360, height: 544)
        .transition(.opacity)
    }

    // MARK: derived diagnostics

    private var s: GameState { controller.state }
    private var reputationTier: HealthCheck.Tier { HealthCheck.reputationTier(s.reputation) }
    private var cleanlinessTier: HealthCheck.Tier { HealthCheck.cleanlinessTier(s.cleanliness) }
    private var throughputTier: HealthCheck.Tier {
        HealthCheck.throughputTier(capacityPerSec: SalesEngine.capacityPerSec(s),
                                    customerRate: SalesEngine.customerRate(s))
    }
    private var storageFill: Double {
        HealthCheck.storageFillPercent(stock: s.stock,
                                        ingredientIds: MenuCatalog.ingredients.map(\.id),
                                        cap: EconomyEngine.storageCap(s))
    }
    private var storageTier: HealthCheck.Tier { HealthCheck.storageTier(fillPercent: storageFill) }
    private var seasonalAlert: HealthCheck.SeasonalAlert? {
        HealthCheck.notableSeasonalPrice(ingredientIds: MenuCatalog.ingredients.map(\.id), season: s.season)
    }

    private var overallBanner: some View {
        let worst = [reputationTier.severity, cleanlinessTier.severity, throughputTier.severity, storageTier.severity]
            .max { severityRank($0) < severityRank($1) } ?? .good
        let (emoji, text): (String, String) = {
            if controller.isClosed { return ("🚨", "Café is closed — needs attention now") }
            switch worst {
            case .critical: return ("🚨", "Something needs attention right now")
            case .warning: return ("⚠️", "Mostly fine, a couple things worth checking")
            case .good: return ("✅", "Running smoothly")
            }
        }()
        return HStack(spacing: 8) {
            Text(emoji).font(.system(size: 16))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Spacer()
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func severityRank(_ sev: HealthCheck.Severity) -> Int {
        switch sev {
        case .good: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    private func color(for severity: HealthCheck.Severity) -> Color {
        switch severity {
        case .good: return Theme.dealGreen
        case .warning: return Theme.gold
        case .critical: return Theme.danger
        }
    }

    private var reputationRow: some View {
        DashboardRow(
            icon: "💖", title: "Reputation",
            value: "\(Int(s.reputation)) · \(reputationTier.label)",
            color: color(for: reputationTier.severity),
            detail: "Happy customers build it, angry or turned-away ones wreck it."
        )
    }

    private var cleanlinessRow: some View {
        let chipHired = (s.staffLevels["chip"] ?? 0) > 0
        return DashboardRow(
            icon: "🧽", title: "Cleanliness",
            value: "\(Int(s.cleanliness))% · \(cleanlinessTier.label)",
            color: color(for: cleanlinessTier.severity),
            detail: chipHired ? "Chip is on staff, auto-cleaning on a cooldown." : "Chip isn't hired — cleaning is manual only."
        )
    }

    private var seasonRow: some View {
        let day = GameCalendar.dayOfSeason(s)
        let daysLeft = max(0, GameCalendar.daysPerSeason - day)
        var detail = "Day \(day) of \(GameCalendar.daysPerSeason) · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        if let alert = seasonalAlert, let ing = MenuCatalog.ingredients.first(where: { $0.id == alert.ingredientId }) {
            let pct = Int((abs(alert.multiplier - 1.0) * 100).rounded())
            detail += " · \(ing.emoji) \(ing.name) is \(pct)% \(alert.cheaper ? "cheaper" : "pricier") right now"
        }
        return DashboardRow(
            icon: seasonEmoji, title: "Season — \(s.season.rawValue.capitalized)",
            value: "", color: Theme.dim, detail: detail
        )
    }

    private var seasonEmoji: String {
        switch s.season {
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .autumn: return "🍂"
        case .winter: return "❄️"
        }
    }

    private var throughputRow: some View {
        DashboardRow(
            icon: "👩‍🍳", title: "Throughput",
            value: throughputTier.label,
            color: color(for: throughputTier.severity),
            detail: "Is the kitchen prepping/serving as fast as customers arrive."
        )
    }

    private var storageRow: some View {
        DashboardRow(
            icon: "📦", title: "Storage",
            value: "\(Int(storageFill))% full · \(storageTier.label)",
            color: color(for: storageTier.severity),
            detail: "Average fill across every ingredient vs. this café's pantry cap."
        )
    }

    private var stockOutRow: some View {
        DashboardRow(
            icon: "❗", title: "Stock-out",
            value: "Some menu items unavailable",
            color: Theme.danger,
            detail: "Restock, or raise Marble's refill threshold in Stock."
        )
    }

    private var closedRow: some View {
        DashboardRow(
            icon: "🚫", title: "Closed",
            value: "No customers being served",
            color: Theme.danger,
            detail: "Nothing has been servable for too long — restock immediately."
        )
    }

    private var deliveryRow: some View {
        let cafe = s.cafe
        let total = cafe.deliveryOrdersServed + cafe.deliveryOrdersMissed
        let fillPct = total > 0 ? Int((cafe.deliveryOrdersServed / total * 100).rounded()) : 0
        return DashboardRow(
            icon: "🚚", title: "Delivery",
            value: total > 0 ? "\(fillPct)% of orders filled" : "Unlocked, no orders yet",
            color: total > 0 && fillPct < 20 ? Theme.danger : Theme.dealGreen,
            detail: "Extra orders on top of walk-ins — capped by the same prep capacity."
        )
    }
}

/// One diagnostic line: icon + title, a colored status value, and a short
/// plain-language explanation. Matches Rows.swift's card visual language
/// (Theme.card background, 9pt corner radius) so it reads as part of the
/// same app rather than a bolted-on screen.
private struct DashboardRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(icon) \(title)")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                        .multilineTextAlignment(.trailing)
                }
            }
            Text(detail)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(Theme.dim)
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}
