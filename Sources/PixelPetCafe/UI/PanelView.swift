import SpriteKit
import SwiftUI

enum PanelTab: String, CaseIterable {
    case menu = "Menu", stock = "Stock", staff = "Staff"
    case cafe = "Café", style = "Style", casino = "Casino", renovate = "Renovate"

    /// SF Symbol per tab — replaces raw emoji with a consistent icon set.
    var symbol: String {
        switch self {
        case .menu: return "fork.knife"
        case .stock: return "shippingbox.fill"
        case .staff: return "person.2.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .style: return "paintbrush.pointed.fill"
        case .casino: return "suit.spade.fill"
        case .renovate: return "star.fill"
        }
    }
}

enum Theme {
    static let bg = Color(red: 0.16, green: 0.12, blue: 0.13)
    static let card = Color(red: 0.23, green: 0.17, blue: 0.17)
    static let cream = Color(red: 0.97, green: 0.91, blue: 0.80)
    static let gold = Color(red: 0.98, green: 0.73, blue: 0.09)
    static let dim = Color(red: 0.72, green: 0.62, blue: 0.56)
    static let danger = Color(red: 0.93, green: 0.47, blue: 0.42)
    static let dealGreen = Color(red: 0.55, green: 0.85, blue: 0.55)
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
    @State private var tab: PanelTab
    @State private var showDashboard: Bool

    init(controller: GameController, scene: CafeScene) {
        self.controller = controller
        self.scene = scene
        // dev hook: PPC_TAB=style|casino|... opens on a specific tab
        let initial = ProcessInfo.processInfo.environment["PPC_TAB"]
            .flatMap { key in PanelTab.allCases.first { "\($0)" == key } } ?? .menu
        _tab = State(initialValue: initial)
        // dev hook: PPC_DASHBOARD=1 opens the café health dashboard on launch,
        // for offscreen PPC_SNAPSHOT verification.
        _showDashboard = State(initialValue: ProcessInfo.processInfo.environment["PPC_DASHBOARD"] == "1")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                SpriteView(scene: scene)
                    .frame(width: 360, height: 240)
                    .clipped()
                if let haul = controller.awayReport {
                    AwayToast(haul: haul) { controller.awayReport = nil }
                        .padding(.top, 10)
                } else if let banner = controller.banner {
                    HStack(spacing: 7) {
                        Text(banner.emoji).font(.system(size: 15))
                        Text(banner.text)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.cream)
                        Button { controller.banner = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.dim)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.bg.opacity(0.92))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gold.opacity(0.6), lineWidth: 1))
                    .padding(.top, 10)
                    .transition(.opacity)
                }
                // Entry point for the "how's my café doing" dashboard — lives
                // in this same proven overlay layer as AwayToast/banner above,
                // top-leading so it never collides with their centered content.
                VStack {
                    HStack {
                        DashboardEntryButton { showDashboard = true }
                        Spacer()
                    }
                    Spacer()
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
                    case .casino: CasinoTab(controller: controller)
                    case .renovate: RenovateTab(controller: controller)
                    }
                }
                .padding(10)
                .frame(width: 360)
            }
            // Fixed, not maxHeight/.infinity: a flexible height here previously caused
            // the SpriteKit scene to render a single static frame and never update again
            // (likely an NSHostingView redraw stall from the ambiguous flexible layout).
            // 176 is sized for the WORST case — header showing its 3rd (goal-progress)
            // row — so the scroll area never overflows the fixed 544pt popover, even
            // though that leaves a little unused space when the header is only 2 rows.
            .frame(height: 176)
        }
        .frame(width: 360, height: 544, alignment: .top)
        .clipped()
        .background(panelTint)
        .onAppear {
            scene.setMode(tab == .casino ? .casino : .cafe)
            scene.configure(with: controller.state)
        }
        .onChange(of: controller.state) { newState in
            scene.configure(with: newState)
        }
        .onChange(of: tab) { newTab in
            scene.setMode(newTab == .casino ? .casino : .cafe)
        }
        .overlay {
            if showDashboard {
                DashboardOverlay(controller: controller) { showDashboard = false }
            }
        }
    }

    /// The panel subtly re-tints per location — and goes velvet in the casino.
    private var panelTint: Color {
        if tab == .casino { return Color(red: 0.20, green: 0.10, blue: 0.14) }
        switch controller.state.cafe.city {
        case "sakura": return Color(red: 0.21, green: 0.13, blue: 0.16)
        case "neon":   return Color(red: 0.14, green: 0.12, blue: 0.20)
        default:       return Theme.bg
        }
    }

    private var header: some View {
        VStack(spacing: 3) {
            // money row — big and unobstructed
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("🪙 \(formatNumber(controller.state.coins))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.gold)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("+\(formatNumber(controller.incomeEstimate * controller.workBoost))/s")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                if controller.workBoost > 1.05 {
                    Text(String(format: "⚡%.1f×", controller.workBoost))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.gold)
                }
                Spacer()
                Button {
                    controller.toggleMuted()
                } label: {
                    Image(systemName: controller.state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(controller.state.muted ? Theme.dim : Theme.cream)
                }
                .buttonStyle(.plain)
                .help(controller.state.muted ? "Unmute sounds" : "Mute all sounds")
            }
            // status row — compact chips
            HStack(spacing: 8) {
                Text("💖 \(Int(controller.state.reputation))")
                    .foregroundColor(controller.state.reputation < 30 ? Theme.danger : Theme.dim)
                    .help("Reputation — happy sales build it, angry customers wreck it")
                Text("🧽 \(Int(controller.state.cleanliness))%")
                    .foregroundColor(controller.state.cleanliness < 40 ? Theme.danger : Theme.dim)
                if controller.state.stars > 0 {
                    Text("⭐ \(controller.state.stars)")
                        .foregroundColor(Theme.cream)
                }
                if let id = controller.state.activeEvent, let ev = Events.def(id),
                   let ends = controller.state.eventEndsAt, ends > Date() {
                    Text("\(ev.emoji) \(ev.name) · \(Int(ends.timeIntervalSinceNow))s")
                        .foregroundColor(Theme.gold)
                        .help(ev.desc)
                }
                Spacer()
                if controller.isClosed {
                    Text("CLOSED")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.danger).cornerRadius(4)
                } else if controller.hasStockOut {
                    Text("📦❗").help("Some menu items are out of ingredients")
                }
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            // next milestone — anticipation you can see
            if let goal = Achievements.nextGoal(controller.state) {
                HStack(spacing: 6) {
                    Text("\(goal.def.emoji) \(goal.def.name)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.dim)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.card)
                            Capsule().fill(Theme.gold)
                                .frame(width: max(3, geo.size.width * goal.progress))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(goal.progress * 100))%")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gold)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { t in
                let active = tab == t
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { tab = t }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(t.rawValue)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(active ? Theme.bg : Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(active ? Theme.gold : Color.clear)
                            .shadow(color: active ? Theme.gold.opacity(0.45) : .clear, radius: 4, y: 1)
                    )
                    .scaleEffect(active ? 1.0 : 0.94)
                    .contentShape(Rectangle())   // whole padded box is tappable, not just the glyph/text pixels
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Theme.card.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.04), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
