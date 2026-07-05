import SwiftUI

/// Shared purchase row: icon, name + detail, cost button.
struct PurchaseRow: View {
    let emoji: String
    let name: String
    let subtitle: String
    let detail: String
    let cost: Double
    let affordable: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 20))
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
            Button(action: action) {
                Text("🪙 \(formatNumber(cost))")
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
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
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

// MARK: tabs

struct CafeTab: View {
    @ObservedObject var controller: GameController

    private static let emoji = ["espresso": "☕", "grinder": "⚙️", "oven": "🔥", "decor": "🪴", "sound": "🎵"]

    var body: some View {
        ForEach(Catalog.equipment, id: \.id) { def in
            let level = controller.state.equipmentLevels[def.id] ?? 0
            let cost = EconomyEngine.equipmentCost(def.id, controller.state)
            PurchaseRow(
                emoji: Self.emoji[def.id] ?? "🧰",
                name: def.name,
                subtitle: level > 0 ? "Lv \(level)" : "New",
                detail: String(format: "×%.2f income per level", def.multPerLevel),
                cost: cost,
                affordable: controller.state.coins >= cost
            ) { controller.buyEquipment(def.id) }
        }
    }
}

struct StaffTab: View {
    @ObservedObject var controller: GameController

    private static let emoji = ["mocha": "🐱", "biscuit": "🐶", "poppy": "🐰", "juno": "🦊", "bo": "🐻", "earl": "🦉"]

    var body: some View {
        ForEach(Catalog.staff, id: \.id) { def in
            if controller.state.lifetimeCoins >= def.unlockAtLifetime {
                let level = controller.state.staffLevels[def.id] ?? 0
                let cost = EconomyEngine.staffCost(def.id, controller.state)
                let extra = def.id == "earl" ? " · +1h away cap/lv" : ""
                PurchaseRow(
                    emoji: Self.emoji[def.id] ?? "🐾",
                    name: def.name,
                    subtitle: level > 0 ? "\(def.role) · Lv \(level)" : "\(def.role) · Hire",
                    detail: "+\(formatNumber(def.baseRate))/s per level\(extra)",
                    cost: cost,
                    affordable: controller.state.coins >= cost
                ) { controller.buyStaff(def.id) }
            } else {
                LockedRow(hint: "??? · unlocks at 🪙 \(formatNumber(def.unlockAtLifetime)) lifetime")
            }
        }
    }
}

struct RecipesTab: View {
    @ObservedObject var controller: GameController

    private static let emoji = ["latte_art": "🎨", "croissant": "🥐", "matcha": "🍵", "affogato": "🍨",
                                "cinnamon": "🥮", "cold_brew": "🧋", "tiramisu": "🍰", "honey_cake": "🍯"]

    var body: some View {
        ForEach(Catalog.recipes, id: \.id) { def in
            if controller.state.unlockedRecipes.contains(def.id) {
                HStack(spacing: 10) {
                    Text(Self.emoji[def.id] ?? "🍽").font(.system(size: 18))
                    Text(def.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Spacer()
                    Text(String(format: "×%.2f", def.multiplier))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gold)
                }
                .padding(9)
                .background(Theme.card)
                .cornerRadius(9)
            } else {
                LockedRow(hint: "Secret recipe · 🪙 \(formatNumber(def.unlockAtLifetime)) lifetime")
            }
        }
    }
}

struct RenovateTab: View {
    @ObservedObject var controller: GameController
    @State private var confirming = false

    var body: some View {
        let pending = EconomyEngine.prestigeStars(controller.state)
        VStack(spacing: 10) {
            Text("⭐ \(controller.state.stars) stars · +\(controller.state.stars * 10)% income")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("Renovating resets your café (coins, staff, gear, recipes)\nbut earns permanent stars. Each star: +10% income forever.")
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
