import SwiftUI

/// Shared purchase row: leading view, name + detail, cost button.
struct PurchaseRow<Leading: View>: View {
    let leading: Leading
    let name: String
    let subtitle: String
    let detail: String
    let cost: Double
    let affordable: Bool
    var maxed: Bool = false
    var maxedLabel: String = "MAX"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            leading.frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                Text(detail)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            if maxed {
                Text(maxedLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.dim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.card.opacity(0.6))
                    .cornerRadius(7)
            } else {
                CostButton(cost: cost, affordable: affordable, action: action)
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

struct CostButton: View {
    let cost: Double
    let affordable: Bool
    var label: String = ""
    let action: () -> Void

    @State private var repeater: Timer?

    var body: some View {
        Button(action: action) {
            Text("\(label)🪙 \(formatNumber(cost))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(affordable ? Theme.bg : Theme.dim)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(affordable ? Theme.gold : Theme.card.opacity(0.6))
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
        // Hold to rapid-buy: after 0.45s of pressing, repeats the purchase
        // ~12x/sec until released — one gesture to bulk-level anything
        // (staff, equipment, packs, taste...). Each fire re-runs the same
        // guarded action, so caps/gates/affordability still stop it cold.
        .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
            if pressing { return }
            repeater?.invalidate(); repeater = nil
        }, perform: {
            repeater?.invalidate()
            let t = Timer(timeInterval: 0.085, repeats: true) { _ in
                Task { @MainActor in action() }
            }
            RunLoop.main.add(t, forMode: .common)
            repeater = t
        })
        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in
            repeater?.invalidate(); repeater = nil
        })
        .help("Hold to rapid-upgrade")
    }
}

struct LockedRow: View {
    let hint: String

    var body: some View {
        HStack {
            Text("🔒").font(.system(size: 16))
            Text(hint)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
            Spacer()
        }
        .padding(9)
        .background(Theme.card.opacity(0.5))
        .cornerRadius(9)
    }
}

// MARK: Café tab (equipment + cleaning)

struct CafeTab: View {
    @ObservedObject var controller: GameController
    @Binding var showFullCalendar: Bool
    @State private var calendarExpanded = false

    private static let emoji = ["espresso": "☕", "grinder": "⚙️", "oven": "🔥", "decor": "🪴", "sound": "🎵"]
    private static let cityEmoji = ["home": "🏡", "sakura": "🌸", "neon": "🌃", "seaside": "🌊",
                                    "forest": "🌲", "desert": "🏜️", "snowy": "❄️", "sunset": "🌅",
                                    "ember": "🌋", "royal": "👑", "cloud": "☁️", "moon": "🌕"]
    private static let seasonEmoji: [Season: String] = [
        .spring: "🌱", .summer: "☀️", .autumn: "🍂", .winter: "❄️",
    ]

    var body: some View {
        // calendar — tap to open the full breakdown (days left, seasonal ingredient prices)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { calendarExpanded.toggle() }
            } label: {
                HStack {
                    let season = controller.state.season
                    Text("\(Self.seasonEmoji[season] ?? "") Day \(GameCalendar.dayOfSeason(controller.state)) of \(season.rawValue.capitalized)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    if let holiday = Holidays.today(controller.state) {
                        Text("\(holiday.emoji) \(holiday.name)!")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.gold)
                    }
                    Spacer()
                    Text("~1hr/day")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                    Image(systemName: calendarExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if calendarExpanded {
                let season = controller.state.season
                let daysLeft = max(0, GameCalendar.daysPerSeason - GameCalendar.dayOfSeason(controller.state))
                VStack(alignment: .leading, spacing: 5) {
                    Divider().background(Theme.dim.opacity(0.3))
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left in \(season.rawValue.capitalized)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                    let seasonal = MenuCatalog.ingredients
                        .map { ($0, SeasonalPricing.multiplier($0.id, season)) }
                        .filter { $0.1 != 1.0 }
                    if seasonal.isEmpty {
                        Text("No ingredients are in or out of season right now")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                    } else {
                        Text("🛒 Seasonal prices")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.dim)
                        ForEach(seasonal, id: \.0.id) { ing, mult in
                            HStack {
                                Text("\(ing.emoji) \(ing.name)")
                                    .font(.system(size: 9.5, design: .rounded))
                                    .foregroundColor(Theme.cream)
                                Spacer()
                                Text(mult < 1 ? "▼ cheaper" : "▲ pricier")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(mult < 1 ? Theme.dealGreen : Theme.danger)
                            }
                        }
                    }
                    Button { showFullCalendar = true } label: {
                        Text("📅 View full calendar →")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.gold)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)

        MomentumCard(controller: controller)

        // locations
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Locations")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Spacer()
                Button {
                    controller.mapOpen.send(true)
                } label: {
                    Text("🗺 World Map")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.gold)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                      alignment: .leading, spacing: 4) {
                ForEach(Array(controller.state.cafes.enumerated()), id: \.offset) { i, cafe in
                    Button {
                        controller.switchCafe(i)
                    } label: {
                        Text("\(Self.cityEmoji[cafe.city] ?? "☕") \(Cities.def(cafe.city).name)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(controller.state.activeCafe == i ? Theme.bg : Theme.dim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(controller.state.activeCafe == i ? Theme.gold : Theme.bg.opacity(0.5))
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            }
            // only the next destination is on offer — one dream at a time
            if let next = Cities.all.first(where: { !controller.state.ownsCity($0.id) }) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next: \(Self.cityEmoji[next.id] ?? "") \(next.name)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.cream)
                        Text(next.vibe
                             + (next.rateBonus > 1 ? " · ×\(String(format: "%.1f", next.rateBonus)) customers" : "")
                             + (next.priceBonus > 1 ? " · ×\(String(format: "%.1f", next.priceBonus)) prices" : ""))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                        Text("\(Cities.all.filter { !controller.state.ownsCity($0.id) }.count) destinations still undiscovered")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(Theme.dim.opacity(0.7))
                    }
                    Spacer()
                    CostButton(cost: next.cost,
                               affordable: controller.state.coins >= next.cost) {
                        controller.buyCity(next.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)

        // ads campaign
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("📣 Ad campaign")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Text("×1.8 customers & slowly builds 💖 — costs 25% of income/s")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { controller.state.adsActive },
                set: { _ in controller.toggleAds() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("🪑 Seating — \(controller.state.tables)/\(EconomyEngine.maxTables(controller.state)) tables")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Text("~\(Int(SalesEngine.tableAvailability(controller.state) * 100))% of dine-in guests get a seat right now")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(SalesEngine.tableAvailability(controller.state) < 0.6 ? Theme.danger : Theme.dim)
            }
            Spacer()
            if controller.state.tables >= EconomyEngine.maxTables(controller.state) {
                if EconomyEngine.maxTables(controller.state) < 6 {
                    Text("Own \(EconomyEngine.citiesForBiggerCafe) cities to expand")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("Room is full")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
            } else {
                CostButton(cost: EconomyEngine.tableCost(controller.state),
                           affordable: controller.state.coins >= EconomyEngine.tableCost(controller.state)) {
                    controller.buyTable()
                }
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
        if controller.state.cleanliness < 100 {
            HStack {
                Text("🧹 Sweep the café")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Text("→ 100%")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Theme.dim)
                Spacer()
                CostButton(cost: SalesEngine.sweepCost(controller.state),
                           affordable: controller.state.coins >= SalesEngine.sweepCost(controller.state)) {
                    controller.sweepAll()
                }
            }
            .padding(9)
            .background(Theme.card)
            .cornerRadius(9)
            Text("Tip: click stains in the café to spot-clean for free")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.dim)
        }
        ThroughputCard(controller: controller)
        if controller.state.deliveryUnlocked {
            DeliveryCard(controller: controller)
        }
        let equipCap = EconomyEngine.equipmentLevelCap(controller.state)
        ForEach(Catalog.equipment, id: \.id) { def in
            let level = controller.state.equipmentLevels[def.id] ?? 0
            let cost = EconomyEngine.equipmentCost(def.id, controller.state)
            let atCap = level >= equipCap
            let repNeeded = EconomyEngine.requiredReputation(forLevel: level)
            let repBlocked = !atCap && controller.state.reputation < repNeeded
            let speedNote = def.speedCategories.isEmpty ? ""
                : String(format: " · ×%.2f prep speed/level (%@)", def.speedMultPerLevel,
                         def.speedCategories.contains(.drink) ? "drinks" : "pastries")
            PurchaseRow(
                leading: Text(Self.emoji[def.id] ?? "🧰").font(.system(size: 20)),
                name: def.name,
                subtitle: level > 0 ? "Lv \(level)/\(equipCap)" : "New · cap \(equipCap)",
                detail: atCap ? "Maxed for this café — a fancier café raises the cap"
                    : repBlocked ? "Word needs to spread first — build reputation to keep upgrading"
                    : String(format: "×%.2f prices & customers per level", def.multPerLevel) + speedNote,
                cost: cost,
                affordable: controller.state.coins >= cost,
                maxed: atCap || repBlocked,
                maxedLabel: atCap ? "MAX Lv \(equipCap)" : "Needs 💖\(Int(repNeeded))"
            ) { controller.buyEquipment(def.id) }
        }
    }
}

/// How fast the café can actually prep/serve right now, and whether that's
/// keeping up with who's walking in — the visible face of the throughput cap.
struct ThroughputCard: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let s = controller.state
        let cap = SalesEngine.capacityPerSec(s)
        let rate = SalesEngine.customerRate(s)
        let strained = cap.isFinite && cap < rate
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("👩‍🍳 Kitchen throughput")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Spacer()
                Text(cap.isFinite ? String(format: "~%.1f/sec", cap) : "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(strained ? Theme.danger : Theme.gold)
            }
            Text(strained
                 ? "Demand is outpacing prep speed — customers are being turned away. Hire Mocha/Poppy/Biscuit or upgrade the Espresso Machine/Stone Oven."
                 : "Comfortably keeping up with walk-in demand right now.")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.dim)
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

/// Late-game Delivery channel — unlocked once 10 of 12 cities are owned.
/// Shows lifetime served/missed so under-investment in service capacity is
/// visible, not just a silent number.
struct DeliveryCard: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let cafe = controller.state.cafe
        let total = cafe.deliveryOrdersServed + cafe.deliveryOrdersMissed
        let fillPct = total > 0 ? Int((cafe.deliveryOrdersServed / total * 100).rounded()) : 0
        VStack(alignment: .leading, spacing: 4) {
            Text("🚚 Delivery — unlocked")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("A flood of new orders on top of walk-ins — but only your prep capacity decides how many you can actually fill.")
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(Theme.dim)
            if total > 0 {
                Text("Filled \(fillPct)% of \(formatNumber(total)) delivery orders so far")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(fillPct < 20 ? Theme.danger : Theme.dealGreen)
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

// MARK: Staff tab

struct StaffTab: View {
    @ObservedObject var controller: GameController

    /// Every role's real, distinct effect — replaces a stale generic
    /// "+15% customer flow per level" line that was shown for ALL staff
    /// regardless of what they actually do, hiding how differentiated the
    /// roles already are (each also adds a small flat +8%/level to base
    /// customer flow on top of this, from just being on staff).
    private static func detail(_ id: String) -> String {
        switch id {
        case "mocha":   return "+4% drink prices/lv (slower past 25) · helps keep drinks fast"
        case "biscuit": return "Waits tables · adds real serving capacity (throughput)"
        case "poppy":   return "+4% pastry prices/lv (slower past 25) · helps keep pastries fast"
        case "juno":    return "+2% all prices/lv (slower past 25)"
        case "bo":      return "2%/lv chance a sale costs no ingredients (cap 85%)"
        case "earl":    return "+1h away-earnings cap per level"
        case "marble":  return "Auto-restocks ingredients, and cheaper restocks per level"
        case "chip":    return "Auto-cleans on a cooldown, bigger bursts per level, free once hired"
        default:        return "+8% customer flow per level"
        }
    }

    var body: some View {
        let cap = EconomyEngine.staffLevelCap(controller.state)
        let wagePct = Int((EconomyEngine.wageShare(controller.state) * 100).rounded())
        if wagePct > 0 {
            // net income is already wage-deducted; back out the gross to show
            // the actual coins/sec leaving the till as payroll.
            let share = EconomyEngine.wageShare(controller.state)
            let wagePerSec = controller.incomeEstimate * share / (1 - share)
            HStack {
                Text("💸 Payroll: \(wagePct)% of sales · paying ≈ 🪙\(formatNumber(wagePerSec))/s")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.danger)
                Spacer()
            }
            .padding(9)
            .background(Theme.card)
            .cornerRadius(9)
        }
        ForEach(Catalog.staff, id: \.id) { def in
            if controller.state.lifetimeCoins >= def.unlockAtLifetime {
                let level = controller.state.staffLevels[def.id] ?? 0
                let cost = EconomyEngine.staffCost(def.id, controller.state)
                let atCap = level >= cap
                let repNeeded = EconomyEngine.requiredReputation(forLevel: level)
                let repBlocked = !atCap && controller.state.reputation < repNeeded
                PurchaseRow(
                    leading: StaffLayeredIcon(id: def.id, pair: StaffPalette.pair(for: def.id, in: controller.state),
                                               paint: controller.state.staffPaint[def.id], scale: 1.4),
                    name: def.name,
                    subtitle: level > 0 ? "\(def.role) · Lv \(level)/\(cap)" : "\(def.role) · Hire",
                    detail: atCap ? "Maxed for this café — a fancier café raises the cap"
                        : repBlocked ? "Word needs to spread first — build reputation to keep growing"
                        : Self.detail(def.id),
                    cost: cost,
                    affordable: controller.state.coins >= cost,
                    maxed: atCap || repBlocked,
                    maxedLabel: atCap ? "MAX Lv \(cap)" : "Needs 💖\(Int(repNeeded))"
                ) { controller.buyStaff(def.id) }
            } else {
                LockedRow(hint: "??? · unlocks at 🪙 \(formatNumber(def.unlockAtLifetime)) lifetime")
            }
        }
    }
}

// MARK: Renovate tab

struct RenovateTab: View {
    @ObservedObject var controller: GameController
    @State private var confirming = false
    @State private var confirmingWorld = false

    var body: some View {
        let pending = EconomyEngine.prestigeStars(controller.state)
        VStack(spacing: 10) {
            Text("⭐ \(controller.state.stars) stars · +\(controller.state.stars * 10)% income & customers")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("Renovating resets coins, staff, gear and stock —\nbut your custom menu, style and stars stay forever.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.dim)
                .multilineTextAlignment(.center)
            if pending >= 1 {
                if confirming {
                    HStack(spacing: 8) {
                        Button("Renovate for ⭐ \(pending)") {
                            controller.renovate()
                            confirming = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.gold).cornerRadius(8)
                        Button("Cancel") { confirming = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.dim)
                    }
                } else {
                    Button("🔨 Renovate → earn ⭐ \(pending)") { confirming = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.gold).cornerRadius(9)
                }
            } else {
                let need = EconomyEngine.prestigeThreshold
                Text("Earn 🪙 \(formatNumber(need)) this run to renovate\n(\(formatNumber(controller.state.lifetimeCoinsThisRun)) so far)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card)
        .cornerRadius(9)

        VStack(spacing: 10) {
            let s = controller.state
            let eligible = EconomyEngine.canMoveToNewCountry(s)
            let jumpstart = EconomyEngine.worldJumpstartCoins(s)
            Text("🌍 \(s.worldsVisited) countries visited · +\(Int(EconomyEngine.worldPermanentBonusPerVisit * Double(s.worldsVisited) * 100))% prices forever")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("Move to a New Country is a whole-game reset: every café\n(not just this one), stars, reputation and the market all\nstart over. You keep achievements, style and settings —\nand start the new run with 10% of this run's earnings.")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.dim)
                .multilineTextAlignment(.center)
            if eligible {
                if confirmingWorld {
                    VStack(spacing: 6) {
                        Text("Jumpstart: 🪙 \(formatNumber(jumpstart)) · +\(Int(EconomyEngine.worldPermanentBonusPerVisit * 100))% permanent prices")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.gold)
                        HStack(spacing: 8) {
                            Button("Move to a New Country") {
                                controller.moveToNewCountry()
                                confirmingWorld = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.bg)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.gold).cornerRadius(8)
                            Button("Cancel") { confirmingWorld = false }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.dim)
                        }
                    }
                } else {
                    Button("🌍 Move to a New Country") { confirmingWorld = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.gold).cornerRadius(9)
                }
            } else {
                let need = EconomyEngine.worldPrestigeCoinThreshold
                let citiesNeed = EconomyEngine.worldPrestigeCitiesRequired
                Text("Earn 🪙 \(formatNumber(need)) lifetime and own \(citiesNeed) cities\n(🪙 \(formatNumber(s.lifetimeCoins)) lifetime · \(s.cafes.count)/\(citiesNeed) cities)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card)
        .cornerRadius(9)

        VStack(alignment: .leading, spacing: 5) {
            Text("Milestones \(controller.state.achievements.count)/\(Achievements.all.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            ForEach(Achievements.all, id: \.id) { def in
                let earned = controller.state.achievements.contains(def.id)
                HStack(spacing: 7) {
                    Text(earned ? def.emoji : "🔒")
                        .font(.system(size: 13))
                        .opacity(earned ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(def.name)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(earned ? Theme.gold : Theme.dim)
                        Text(def.desc)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                    }
                    Spacer()
                    if earned {
                        Text("✓")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.55))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)
    }
}


/// Live income momentum: a ~2 minute sparkline of net income/s with the
/// percent change vs a minute ago — makes rising/falling fortunes visible
/// at a glance instead of having to stare at the coin counter.
struct MomentumCard: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let history = controller.incomeHistory
        let trend = controller.incomeTrend
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("📈 Momentum")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Spacer()
                if history.count >= 30 {
                    Text(String(format: "%+.0f%% vs 1 min ago", trend * 100))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(abs(trend) < 0.03 ? Theme.dim : (trend > 0 ? Theme.dealGreen : Theme.danger))
                } else {
                    Text("warming up…")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
            }
            Canvas { context, size in
                guard history.count >= 2 else { return }
                let maxV = max(history.max() ?? 1, 1e-9)
                let minV = history.min() ?? 0
                let span = max(maxV - minV, maxV * 0.01)
                var path = Path()
                for (i, v) in history.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(history.count - 1)
                    let y = size.height - size.height * CGFloat((v - minV) / span) * 0.9 - size.height * 0.05
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(Theme.gold), lineWidth: 1.5)
            }
            .frame(height: 30)
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}
