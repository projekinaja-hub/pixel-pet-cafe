import SwiftUI

// MARK: Menu tab — toggle items, create custom items

struct MenuTab: View {
    @ObservedObject var controller: GameController
    @State private var creating = false

    var body: some View {
        ForEach(MenuCatalog.items, id: \.id) { def in
            if controller.state.lifetimeCoins >= def.unlockAtLifetime {
                MenuRow(controller: controller,
                        id: def.id, name: def.name, icon: def.icon,
                        price: def.basePrice * SalesEngine.priceMultiplier(controller.state),
                        ingredients: def.ingredients, deletable: false)
            } else {
                LockedRow(hint: "Secret recipe · 🪙 \(formatNumber(def.unlockAtLifetime)) lifetime")
            }
        }
        ForEach(controller.state.customItems, id: \.id) { item in
            MenuRow(controller: controller,
                    id: item.id, name: item.name, icon: item.icon,
                    price: MenuCatalog.customPrice(item) * SalesEngine.priceMultiplier(controller.state),
                    ingredients: item.ingredients, deletable: true)
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

struct MenuRow: View {
    @ObservedObject var controller: GameController
    let id: String
    let name: String
    let icon: String
    let price: Double
    let ingredients: [String: Int]
    let deletable: Bool

    private var enabled: Bool { controller.state.menuEnabled.contains(id) }
    private var servable: Bool {
        ingredients.allSatisfy { (controller.state.stock[$0.key] ?? 0) >= $0.value }
    }

    var body: some View {
        HStack(spacing: 8) {
            PixelImage(name: "item_\(icon)", scale: 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(enabled ? Theme.cream : Theme.dim)
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
                }
            }
            Spacer()
            Text("🪙 \(formatNumber(price))")
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
        Text("Ingredients are used up by every sale — keep the pantry full or the café closes!")
            .font(.system(size: 9.5, design: .rounded))
            .foregroundColor(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(MenuCatalog.ingredients, id: \.id) { ing in
            let have = controller.state.stock[ing.id] ?? 0
            HStack(spacing: 8) {
                PixelImage(name: "ing_\(ing.id)", scale: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ing.name)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Text("\(have) in stock")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(have == 0 ? Theme.danger : Theme.dim)
                }
                Spacer()
                CostButton(cost: MenuCatalog.packCost(ing.id, units: 25),
                           affordable: controller.state.coins >= MenuCatalog.packCost(ing.id, units: 25),
                           label: "25 · ") { controller.buyPack(ing.id, units: 25) }
                CostButton(cost: MenuCatalog.packCost(ing.id, units: 100),
                           affordable: controller.state.coins >= MenuCatalog.packCost(ing.id, units: 100),
                           label: "100 · ") { controller.buyPack(ing.id, units: 100) }
            }
            .padding(8)
            .background(Theme.card)
            .cornerRadius(9)
        }
    }
}

// MARK: Style tab — owner customization + bar character

struct StyleTab: View {
    @ObservedObject var controller: GameController

    var body: some View {
        let owner = controller.state.owner
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
    }

    var workModeSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("⚡ Work Mode")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
                Text("Typing on your Mac boosts customers up to ×2.5 (counts keystrokes only,\nnever reads them — needs Accessibility permission)")
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
