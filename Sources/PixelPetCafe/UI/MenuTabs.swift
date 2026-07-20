import SwiftUI

// MARK: Menu tab — toggle items, create custom items

struct MenuTab: View {
    @ObservedObject var controller: GameController
    @State private var creating = false

    private var bestSeller: String? {
        controller.state.salesCount.max { $0.value < $1.value }?.key
    }

    var body: some View {
        GoalsCard(controller: controller)
        TasteResearchRow(controller: controller)
        ForEach(MenuCatalog.items, id: \.id) { def in
            if controller.state.lifetimeCoins >= def.unlockAtLifetime {
                MenuRow(controller: controller,
                        id: def.id, name: def.name, icon: def.icon,
                        category: def.category, basePrice: def.basePrice,
                        ingredients: def.ingredients, deletable: false,
                        isBestSeller: bestSeller == def.id)
            } else {
                LockedRow(hint: "Secret recipe · 🪙 \(formatNumber(def.unlockAtLifetime)) lifetime")
            }
        }
        ForEach(controller.state.customItems, id: \.id) { item in
            MenuRow(controller: controller,
                    id: item.id, name: item.name, icon: item.icon,
                    category: item.category, basePrice: MenuCatalog.customPrice(item),
                    ingredients: item.ingredients, deletable: true,
                    isBestSeller: bestSeller == item.id)
        }
        if creating {
            CustomItemForm(controller: controller, dismiss: { creating = false })
        } else {
            Button {
                creating = true
            } label: {
                Text("＋ Invent a new recipe")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.gold)
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Rotating short-term goals — a fresh 2-3 set roughly once per in-game day
/// (see Goals.swift). Distinct from the permanent Milestones list on the
/// Renovate tab: these are a small chase to actively pursue this session,
/// not a lifetime unlock.
struct GoalsCard: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🎯 Today's Goals")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Spacer()
                Text("resets daily")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            ForEach(controller.state.activeGoals, id: \.kind) { goal in
                GoalRow(controller: controller, goal: goal)
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

struct GoalRow: View {
    @ObservedObject var controller: GameController
    let goal: ActiveGoal

    var body: some View {
        let def = Goals.def(goal.kind)
        let complete = Goals.isComplete(goal)
        let frac = min(1, goal.progress / max(0.0001, def.target))
        HStack(spacing: 8) {
            Text(def.emoji).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(def.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text(def.desc)
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.bg.opacity(0.6))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(goal.claimed ? Theme.dealGreen : Theme.gold)
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 6)
                Text(goal.claimed ? "claimed" : def.progressText(goal.progress))
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            Spacer()
            if goal.claimed {
                Text("✓")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Theme.dealGreen)
            } else if complete {
                Button {
                    controller.claimGoal(goal.kind)
                } label: {
                    Text("Claim 🪙\(formatNumber(goal.rewardCoins))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.gold)
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            } else {
                Text("🪙\(formatNumber(goal.rewardCoins))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
        }
    }
}

struct TasteResearchRow: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let city = controller.state.city
        let known = controller.state.tasteKnown.contains(city.id)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("🔎 \(city.name) tastes")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                if known {
                    Text(tasteSummary(city))
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(Theme.gold)
                } else {
                    Text("Locals have their own cravings — run a tasting event to learn them")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
            }
            Spacer()
            if !known {
                CostButton(cost: SalesEngine.researchCost(controller.state),
                           affordable: controller.state.coins >= SalesEngine.researchCost(controller.state)) {
                    controller.researchTaste()
                }
            }
        }
        .padding(8)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func tasteSummary(_ city: CityDef) -> String {
        let names: [ItemCategory: String] = [.drink: "Drinks", .pastry: "Pastries", .special: "Specials"]
        let parts = ItemCategory.allCases.compactMap { cat -> String? in
            let w = city.tasteWeight(cat)
            guard abs(w - 1) > 0.01 else { return nil }
            return "\(names[cat]!) ×\(String(format: "%.1f", w))"
        }
        return parts.isEmpty ? "Balanced tastes — everything sells evenly" : parts.joined(separator: " · ")
    }
}

struct MenuRow: View {
    @ObservedObject var controller: GameController
    let id: String
    let name: String
    let icon: String
    let category: ItemCategory
    let basePrice: Double
    let ingredients: [String: Int]
    let deletable: Bool
    let isBestSeller: Bool

    private var enabled: Bool { controller.state.menuEnabled.contains(id) }
    private var servable: Bool {
        ingredients.allSatisfy { (controller.state.stock[$0.key] ?? 0) >= $0.value }
    }
    private var resolved: ResolvedItem {
        ResolvedItem(id: id, name: name, icon: icon, category: category,
                     ingredients: ingredients, basePrice: basePrice, isCustom: deletable)
    }

    var body: some View {
        let taste = controller.state.menuTaste[id] ?? 0
        let sold = controller.state.salesCount[id] ?? 0
        HStack(spacing: 8) {
            PixelImage(name: "item_\(icon)", scale: 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(enabled ? Theme.cream : Theme.dim)
                    if isBestSeller && sold > 0 {
                        Text("★ popular")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.gold)
                    }
                    if !servable && enabled {
                        Text("out of stock!")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.danger)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(ingredients.sorted(by: { $0.key < $1.key }), id: \.key) { ing, qty in
                        Text("\(MenuCatalog.ingredientDef(ing)?.emoji ?? "?")\(qty)")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                    }
                    Text("⏱ ~\(String(format: "%.1f", SalesEngine.prepTime(resolved, controller.state)))s to prep")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                    if sold > 0 {
                        Text("· sold \(formatNumber(Double(sold)))")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                    }
                }
                HStack(spacing: 2) {
                    Text(taste > 0 ? String(repeating: "★", count: min(taste, 10)) : "☆ basic recipe")
                        .font(.system(size: 8))
                        .foregroundColor(taste > 0 ? Theme.gold : Theme.dim)
                    if taste < SalesEngine.maxTaste {
                        Button {
                            controller.upgradeTaste(id)
                        } label: {
                            Text("improve 🪙\(formatNumber(SalesEngine.tasteUpgradeCost(resolved, controller.state)))")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundColor(controller.state.coins >= SalesEngine.tasteUpgradeCost(resolved, controller.state) ? Theme.bg : Theme.dim)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(controller.state.coins >= SalesEngine.tasteUpgradeCost(resolved, controller.state) ? Theme.gold.opacity(0.9) : Theme.bg.opacity(0.5))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Text("🪙 \(formatNumber(SalesEngine.price(resolved, controller.state)))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.gold)
            if deletable {
                Button { controller.deleteCustomItem(id) } label: {
                    Image(systemName: "trash").font(.system(size: 10)).foregroundColor(Theme.dim)
                }
                .buttonStyle(.plain)
            }
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { _ in controller.toggleMenuItem(id) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(8)
        .background(Theme.card.opacity(enabled ? 1 : 0.55))
        .cornerRadius(9)
    }
}

// MARK: custom item creation form

struct CustomItemForm: View {
    @ObservedObject var controller: GameController
    let dismiss: () -> Void

    @State private var name = ""
    @State private var icon = "cookie"
    @State private var category: ItemCategory = .drink
    @State private var amounts: [String: Int] = [:]

    private var ingredients: [String: Int] { amounts.filter { $0.value > 0 } }
    private var price: Double {
        MenuCatalog.customPrice(CustomMenuItem(id: "", name: "", icon: icon,
                                               category: category, ingredients: ingredients))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New recipe")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            TextField("Name (e.g. Leo's Honey Latte)", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            HStack(spacing: 5) {
                ForEach(MenuCatalog.itemIcons, id: \.self) { ic in
                    Button { icon = ic } label: {
                        PixelImage(name: "item_\(ic)", scale: 2)
                            .padding(3)
                            .background(icon == ic ? Theme.gold.opacity(0.35) : .clear)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("", selection: $category) {
                Text("Drink").tag(ItemCategory.drink)
                Text("Pastry").tag(ItemCategory.pastry)
                Text("Special").tag(ItemCategory.special)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(spacing: 4) {
                ForEach(MenuCatalog.ingredients, id: \.id) { ing in
                    HStack {
                        Text("\(ing.emoji) \(ing.name)")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundColor(Theme.cream)
                        Spacer()
                        Stepper("\(amounts[ing.id] ?? 0)",
                                value: Binding(get: { amounts[ing.id] ?? 0 },
                                               set: { amounts[ing.id] = $0 }),
                                in: 0...3)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.gold)
                    }
                }
            }
            HStack {
                Text("Sells for 🪙 \(formatNumber(price))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.gold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                Button("Add to menu") {
                    controller.addCustomItem(name: name, icon: icon,
                                             category: category, ingredients: ingredients)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(ingredients.isEmpty ? Theme.dim : Theme.bg)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ingredients.isEmpty ? Theme.card : Theme.gold)
                .cornerRadius(7)
                .disabled(ingredients.isEmpty)
            }
        }
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

// MARK: Stock tab

struct StockTab: View {
    @ObservedObject var controller: GameController

    var body: some View {
        Text("Ingredients are used up by every sale — keep the pantry full or the café closes! Prices drift with the market and the season, so watch for dips.")
            .font(.system(size: 9.5, design: .rounded))
            .foregroundColor(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
        StorageCard(controller: controller)
        ForEach(MenuCatalog.ingredients, id: \.id) { ing in
            let have = controller.state.stock[ing.id] ?? 0
            let cap = EconomyEngine.storageCap(controller.state)
            let price = MenuCatalog.currentUnitCost(ing.id, controller.state)
            let goodDeal = price <= ing.unitCost * 0.97
            let pricey = price >= ing.unitCost * 1.15
            HStack(spacing: 8) {
                PixelImage(name: "ing_\(ing.id)", scale: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ing.name)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("\(have)/\(cap) in stock")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(have == 0 ? Theme.danger : Theme.dim)
                    HStack(spacing: 5) {
                        Text("🪙\(String(format: "%.1f", price))/unit")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(goodDeal ? Theme.dealGreen : (pricey ? Theme.danger : Theme.dim))
                        if goodDeal {
                            Text("good deal!")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.dealGreen)
                        }
                        PriceSparkline(history: controller.state.priceHistory[ing.id] ?? [],
                                       base: ing.unitCost)
                            .frame(width: 44, height: 14)
                    }
                }
                Spacer()
                CostButton(cost: SalesEngine.packPrice(ing.id, units: 25, controller.state),
                           affordable: have + 25 <= cap
                               && controller.state.coins >= SalesEngine.packPrice(ing.id, units: 25, controller.state),
                           label: "25 · ") { controller.buyPack(ing.id, units: 25) }
                CostButton(cost: SalesEngine.packPrice(ing.id, units: 100, controller.state),
                           affordable: have + 100 <= cap
                               && controller.state.coins >= SalesEngine.packPrice(ing.id, units: 100, controller.state),
                           label: "100 · ") { controller.buyPack(ing.id, units: 100) }
            }
            .padding(8)
            .background(Theme.card)
            .cornerRadius(9)
        }
    }
}

/// Storage capacity + Marble's refill-threshold setting: one card up top of
/// the Stock tab, in the same "capped, buyable, N/max" shape as Seating in
/// the Café tab.
struct StorageCard: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let cap = EconomyEngine.storageCap(controller.state)
        let maxed = controller.state.storageLevel >= EconomyEngine.maxStorageLevel
        let cost = EconomyEngine.storageCost(controller.state)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("📦 Pantry storage — \(cap)/unit cap")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("Lv \(controller.state.storageLevel)/\(EconomyEngine.maxStorageLevel) · caps every ingredient's stock and Marble's restocking")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                Spacer()
                if maxed {
                    Text("Maxed out")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                } else {
                    CostButton(cost: cost, affordable: controller.state.coins >= cost) {
                        controller.buyStorage()
                    }
                }
            }
            if (controller.state.staffLevels["marble"] ?? 0) > 0 {
                HStack {
                    Text("🔧 Marble refills to \(Int(controller.state.refillThreshold * 100))% of cap")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Spacer()
                    Stepper("", value: Binding(
                        get: { controller.state.refillThreshold },
                        set: { controller.setRefillThreshold($0) }),
                        in: 0...1, step: 0.1)
                        .labelsHidden()
                }
            }
        }
        .padding(9)
        .background(Theme.card)
        .cornerRadius(9)
    }
}

/// Tiny inline line chart of an ingredient's recent price history — enough
/// to eyeball "is this cheap right now?" without a full chart library.
struct PriceSparkline: View {
    let history: [Double]
    let base: Double

    private var samples: [Double] { history.isEmpty ? [base] : history }

    var body: some View {
        let values = samples
        let minV = min(values.min() ?? base, base * 0.98)
        let maxV = max(values.max() ?? base, base * 1.02)
        let range = max(maxV - minV, 0.0001)
        let lineColor = (values.last ?? base) <= base ? Theme.dealGreen : Theme.gold
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((v - minV) / range))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: Style tab — owner customization + bar character

struct StyleTab: View {
    @ObservedObject var controller: GameController
    @Binding var editingStaffColorId: String?
    @Binding var editingStaffPaintId: String?

    var body: some View {
        let owner = controller.state.owner
        workModeSection
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    PixelImage(name: "owner_\(owner.species)_\(owner.palette)_0", scale: 4)
                    if owner.accessory != "none" {
                        PixelImage(name: "acc_\(owner.accessory)", scale: 4)
                    }
                }
                .frame(width: 72, height: 84)
                .background(Theme.bg.opacity(0.6))
                .cornerRadius(9)
                VStack(alignment: .leading, spacing: 5) {
                    Text("The Owner (you!)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    TextField("Café name", text: Binding(
                        get: { controller.state.owner.cafeName },
                        set: { var o = controller.state.owner; o.cafeName = String($0.prefix(28)); controller.setOwner(o) }))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }
            styleRow(title: "Species", options: OwnerConfig.speciesOptions, selected: owner.species) { sp in
                var o = owner; o.species = sp; controller.setOwner(o)
            } label: { sp in
                AnyView(PixelImage(name: "owner_\(sp)_\(owner.palette)_0", scale: 1.7))
            }
            styleRow(title: "Fur", options: OwnerConfig.paletteOptions, selected: owner.palette) { pal in
                var o = owner; o.palette = pal; controller.setOwner(o)
            } label: { pal in
                AnyView(PixelImage(name: "bar_\(owner.species)_\(pal)_0", scale: 1.7))
            }
            styleRow(title: "Accessory", options: OwnerConfig.accessoryOptions, selected: owner.accessory) { acc in
                var o = owner; o.accessory = acc; controller.setOwner(o)
            } label: { acc in
                acc == "none"
                    ? AnyView(Text("✕").font(.system(size: 14)).foregroundColor(Theme.dim))
                    : AnyView(PixelImage(name: "acc_\(acc)", scale: 1.7))
            }
        }
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)

        // menu bar character picker
        VStack(alignment: .leading, spacing: 6) {
            Text("Menu bar buddy")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("Who greets you from the menu bar")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundColor(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 5), count: 7),
                      alignment: .leading, spacing: 5) {
                barChoice("owner", icon: "bar_\(owner.species)_\(owner.palette)_0")
                barChoice("coffee", icon: "barcup_2_0")
                ForEach(Catalog.staff, id: \.id) { def in
                    if (controller.state.staffLevels[def.id] ?? 0) > 0 {
                        barChoice(def.id, icon: "barstaff_\(def.id)_0")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)

        staffColorsSection
    }

    /// Free, cosmetic, per-staff-role recoloring — tap a hired staff member
    /// to mix their own body/clothes colors. Only staff already on payroll
    /// show up here (nothing to preview/tint until they're hired).
    private var staffColorsSection: some View {
        let hired = Catalog.staff.filter { (controller.state.staffLevels[$0.id] ?? 0) > 0 }
        return Group {
            if !hired.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🎨 Staff colors")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("Tap to mix colors, or the 🖌️ to draw a whole custom portrait — both free")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(50), spacing: 6), count: 6),
                              alignment: .leading, spacing: 6) {
                        ForEach(hired, id: \.id) { def in
                            ZStack(alignment: .topTrailing) {
                                Button { editingStaffColorId = def.id } label: {
                                    StaffLayeredIcon(id: def.id, pair: StaffPalette.pair(for: def.id, in: controller.state),
                                                      paint: controller.state.staffPaint[def.id], scale: 1.6)
                                        .frame(width: 44, height: 50)
                                        .background(Theme.bg.opacity(0.5))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Recolor \(def.name)")

                                Button { editingStaffPaintId = def.id } label: {
                                    Text("🖌️")
                                        .font(.system(size: 8))
                                        .padding(2)
                                        .background(Theme.bg.opacity(0.85))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                                .help("Draw a custom portrait for \(def.name)")
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
    }

    var workModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("⚡ Typing Energy")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("Your real typing anywhere on your Mac fuels the café.\nCounts keystrokes only — never reads what you type.")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controller.state.workMode },
                    set: { _ in controller.toggleWorkMode() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if controller.state.workMode {
                if controller.axTrusted {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("✓ listening — type fast and watch the ☕ steam & ⚡ in the menu bar")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.55))
                        // live proof: raw keystrokes/sec, no trust required
                        HStack(spacing: 6) {
                            Text("⌨️ \(String(format: "%.1f", controller.keystrokesPerSec)) keys/sec")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.cream)
                            if let last = controller.lastKeystrokeAt {
                                Text("· last key \(Int(Date().timeIntervalSince(last)))s ago")
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundColor(Theme.dim)
                            } else {
                                Text("· type something to test!")
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.gold)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("⚠️ macOS permission needed to hear typing in other apps")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.danger)
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.bg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.gold)
                        .cornerRadius(5)
                    }
                    // live proof even without trust: in-app keystrokes count
                    // regardless of the permission, so typing in the café-name
                    // field must always move this — if it does, the pipeline
                    // works and only the global permission is missing.
                    Text("⌨️ \(String(format: "%.1f", controller.keystrokesPerSec)) keys/sec (type in the café name field to test)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("System Settings → Privacy & Security → Accessibility → enable Pixel Pet Café.\nAfter the game updates, macOS may require re-enabling it (toggle off & on).")
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
            }
        }
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func barChoice(_ id: String, icon: String) -> some View {
        Button { controller.setBarCharacter(id) } label: {
            PixelImage(name: icon, scale: 1.8)
                .frame(width: 42, height: 40)
                .background(controller.state.barCharacter == id ? Theme.gold.opacity(0.4) : Theme.bg.opacity(0.5))
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    private func styleRow(title: String, options: [String], selected: String,
                          pick: @escaping (String) -> Void,
                          label: @escaping (String) -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(46), spacing: 5), count: 6),
                      alignment: .leading, spacing: 5) {
                ForEach(options, id: \.self) { opt in
                    Button { pick(opt) } label: {
                        label(opt)
                            .frame(width: 46, height: 42)
                            .background(selected == opt ? Theme.gold.opacity(0.4) : Theme.bg.opacity(0.5))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
