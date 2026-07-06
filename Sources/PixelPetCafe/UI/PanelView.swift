import SpriteKit
import SwiftUI

enum PanelTab: String, CaseIterable {
    case menu = "Menu", stock = "Stock", staff = "Staff"
    case cafe = "Café", style = "Style", renovate = "⭐"
}

enum Theme {
    static let bg = Color(red: 0.16, green: 0.12, blue: 0.13)
    static let card = Color(red: 0.23, green: 0.17, blue: 0.17)
    static let cream = Color(red: 0.97, green: 0.91, blue: 0.80)
    static let gold = Color(red: 0.98, green: 0.73, blue: 0.09)
    static let dim = Color(red: 0.72, green: 0.62, blue: 0.56)
    static let danger = Color(red: 0.93, green: 0.47, blue: 0.42)
}

/// Crisp pixel sprite from the bundle for SwiftUI.
struct PixelImage: View {
    let name: String
    var scale: CGFloat = 2

    var body: some View {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: img.size.width * scale, height: img.size.height * scale)
        }
    }
}

struct PanelView: View {
    @ObservedObject var controller: GameController
    let scene: CafeScene
    @State private var tab: PanelTab = .menu

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SpriteView(scene: scene)
                    .frame(width: 360, height: 240)
                    .clipped()
                if let haul = controller.awayReport {
                    AwayToast(haul: haul) { controller.awayReport = nil }
                        .padding(.top, 10)
                }
            }
            header
            tabBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    switch tab {
                    case .menu: MenuTab(controller: controller)
                    case .stock: StockTab(controller: controller)
                    case .staff: StaffTab(controller: controller)
                    case .cafe: CafeTab(controller: controller)
                    case .style: StyleTab(controller: controller)
                    case .renovate: RenovateTab(controller: controller)
                    }
                }
                .padding(10)
            }
            .frame(height: 236)
        }
        .frame(width: 360, height: 544)
        .background(Theme.bg)
        .onAppear { scene.configure(with: controller.state) }
        .onChange(of: controller.state) { newState in
            scene.configure(with: newState)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("🪙 \(formatNumber(controller.state.coins))")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(Theme.gold)
            Text("+\(formatNumber(controller.incomeEstimate))/s")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
            Spacer()
            if controller.isClosed {
                Text("CLOSED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.danger).cornerRadius(5)
            } else if controller.hasStockOut {
                Text("📦❗")
                    .font(.system(size: 12))
                    .help("Some menu items are out of ingredients")
            }
            Text("🧽 \(Int(controller.state.cleanliness))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(controller.state.cleanliness < 40 ? Theme.danger : Theme.dim)
            if controller.state.stars > 0 {
                Text("⭐ \(controller.state.stars)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(PanelTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(tab == t ? Theme.bg : Theme.dim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tab == t ? Theme.gold : Theme.card)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.bg)
    }
}

struct AwayToast: View {
    let haul: Double
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("😴 While you were away")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("+🪙 \(formatNumber(haul))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.gold)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.bg.opacity(0.92))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
    }
}
