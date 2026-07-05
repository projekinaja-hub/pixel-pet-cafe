import SpriteKit
import SwiftUI

enum PanelTab: String, CaseIterable {
    case cafe = "Café", staff = "Staff", recipes = "Recipes", renovate = "Renovate"
}

enum Theme {
    static let bg = Color(red: 0.16, green: 0.12, blue: 0.13)
    static let card = Color(red: 0.23, green: 0.17, blue: 0.17)
    static let cream = Color(red: 0.97, green: 0.91, blue: 0.80)
    static let gold = Color(red: 0.98, green: 0.73, blue: 0.09)
    static let dim = Color(red: 0.72, green: 0.62, blue: 0.56)
}

struct PanelView: View {
    @ObservedObject var controller: GameController
    let scene: CafeScene
    @State private var tab: PanelTab = .cafe

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
                    case .cafe: CafeTab(controller: controller)
                    case .staff: StaffTab(controller: controller)
                    case .recipes: RecipesTab(controller: controller)
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
        HStack(alignment: .firstTextBaseline) {
            Text("🪙 \(formatNumber(controller.state.coins))")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.gold)
            Spacer()
            Text("+\(formatNumber(controller.coinsPerSecond))/s")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
            if controller.state.stars > 0 {
                Text("⭐ \(controller.state.stars)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cream)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(tab == t ? Theme.bg : Theme.dim)
                        .padding(.horizontal, 10)
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
