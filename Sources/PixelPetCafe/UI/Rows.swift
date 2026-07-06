import SwiftUI

/// Shared purchase row: leading view, name + detail, cost button.
struct PurchaseRow<Leading: View>: View {
    let leading: Leading
    let name: String
    let subtitle: String
    let detail: String
    let cost: Double
    let affordable: Bool
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
            CostButton(cost: cost, affordable: affordable, action: action)
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

    private static let emoji = ["espresso": "☕", "grinder": "⚙️", "oven": "🔥", "decor": "🪴", "sound": "🎵"]

    var body: some View {
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
        ForEach(Catalog.equipment, id: \.id) { def in
            let level = controller.state.equipmentLevels[def.id] ?? 0
            let cost = EconomyEngine.equipmentCost(def.id, controller.state)
            PurchaseRow(
                leading: Text(Self.emoji[def.id] ?? "🧰").font(.system(size: 20)),
                name: def.name,
                subtitle: level > 0 ? "Lv \(level)" : "New",
                detail: String(format: "×%.2f prices & customers per level", def.multPerLevel),
                cost: cost,
                affordable: controller.state.coins >= cost
            ) { controller.buyEquipment(def.id) }
        }
    }
}

// MARK: Staff tab

struct StaffTab: View {
    @ObservedObject var controller: GameController

    var body: some View {
        ForEach(Catalog.staff, id: \.id) { def in
            if controller.state.lifetimeCoins >= def.unlockAtLifetime {
                let level = controller.state.staffLevels[def.id] ?? 0
                let cost = EconomyEngine.staffCost(def.id, controller.state)
                let extra = def.id == "earl" ? " · +1h away cap/lv" : ""
                PurchaseRow(
                    leading: PixelImage(name: "staff_\(def.id)_0", scale: 1.4),
                    name: def.name,
                    subtitle: level > 0 ? "\(def.role) · Lv \(level)" : "\(def.role) · Hire",
                    detail: "+15% customer flow per level\(extra)",
                    cost: cost,
                    affordable: controller.state.coins >= cost
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
    }
}
