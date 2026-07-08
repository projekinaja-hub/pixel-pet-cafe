import SwiftUI

// MARK: - Shared result celebration

struct CasinoResult: Equatable {
    enum Kind { case win, jackpot, lose, push }
    let text: String
    let kind: Kind

    var color: Color {
        switch kind {
        case .win: return Theme.gold
        case .jackpot: return Color(red: 1, green: 0.78, blue: 0.25)
        case .lose: return Theme.danger
        case .push: return Theme.dim
        }
    }
    var icon: String {
        switch kind {
        case .win: return "sparkles"
        case .jackpot: return "star.circle.fill"
        case .lose: return "xmark.circle.fill"
        case .push: return "arrow.uturn.left.circle.fill"
        }
    }
}

/// Big centered celebration banner shared by every casino game — makes wins
/// (and losses) land with real weight instead of a one-line status message.
struct ResultBannerOverlay: View {
    let result: CasinoResult?

    var body: some View {
        if let r = result {
            VStack(spacing: 6) {
                Image(systemName: r.icon)
                    .font(.system(size: 30))
                    .foregroundColor(r.color)
                    .shadow(color: r.color.opacity(0.7), radius: 8)
                Text(r.text)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(r.color.opacity(0.8), lineWidth: 1.5))
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.6).combined(with: .opacity),
                removal: .opacity.combined(with: .scale(scale: 1.15))))
            .zIndex(10)
        }
    }
}

// MARK: - Casino tab

struct CasinoTab: View {
    @ObservedObject var controller: GameController
    @State private var game = 0
    @State private var bet: Double = 100
    @State private var betIdx = 0
    @State private var result: CasinoResult?
    @State private var dismissWork: DispatchWorkItem?

    /// Stakes that scale with your fortune — risk stays real forever.
    private var betOptions: [(label: String, value: Double)] {
        let c = controller.state.coins
        return [("100", 100),
                ("1% · \(formatNumber(max(100, (c * 0.01).rounded())))", max(100, (c * 0.01).rounded())),
                ("5% · \(formatNumber(max(100, (c * 0.05).rounded())))", max(100, (c * 0.05).rounded())),
                ("10% · \(formatNumber(max(100, (c * 0.10).rounded())))", max(100, (c * 0.10).rounded()))]
    }

    private func announce(_ r: CasinoResult) {
        dismissWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { result = r }
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.3)) { result = nil } }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (r.kind == .jackpot ? 2.2 : 1.5), execute: work)
    }

    var body: some View {
        if !controller.state.casinoUnlocked {
            LockedRow(hint: "Casino corner · unlocks at 🪙 \(formatNumber(CasinoEngine.unlockAtLifetime)) lifetime")
        } else {
            Picker("", selection: $game.animation(.easeInOut(duration: 0.22))) {
                Text("Slots").tag(0)
                Text("21").tag(1)
                Text("Roulette").tag(2)
                Text("Mahjong").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onAppear { publishGame(game) }
            .onChange(of: game) { publishGame($0) }

            jackpotStrip
            statsStrip

            HStack(spacing: 5) {
                Text("Bet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                ForEach(Array(betOptions.enumerated()), id: \.offset) { i, opt in
                    Button {
                        betIdx = i
                        bet = opt.value
                    } label: {
                        Text(opt.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(betIdx == i ? Theme.bg : Theme.dim)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(betIdx == i ? Theme.gold : Theme.card)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .onChange(of: controller.state.coins) { _ in bet = betOptions[betIdx].value }
            .onAppear { bet = betOptions[betIdx].value }

            ZStack {
                Group {
                    switch game {
                    case 0: SlotsView(controller: controller, bet: $bet, onResult: announce)
                    case 1: BlackjackView(controller: controller, bet: $bet, onResult: announce)
                    case 2: RouletteView(controller: controller, bet: $bet, onResult: announce)
                    default: MahjongView(controller: controller, bet: $bet, onResult: announce)
                    }
                }
                .id(game)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity))
                ResultBannerOverlay(result: result)
            }

            Text("The house always wins in the long run — gambling never counts toward unlocks or stars.")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(Theme.dim.opacity(0.8))
        }
    }

    /// Always-visible pot readout, plus a Lucky Hour callout when it's live —
    /// the reason to check the casino even when not actively playing a hand.
    private var jackpotStrip: some View {
        let luckyHour = Events.isActive("lucky_hour", controller.state)
        return HStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .foregroundColor(Color(red: 1, green: 0.78, blue: 0.25))
            Text("Progressive Jackpot")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cream)
            Text("🪙 \(formatNumber(controller.state.casinoJackpotPot))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 1, green: 0.78, blue: 0.25))
            Spacer()
            if luckyHour {
                Text("🍀 Lucky Hour — payouts boosted!")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.gold)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(red: 1, green: 0.78, blue: 0.25).opacity(luckyHour ? 0.22 : 0.12))
        .cornerRadius(8)
        .animation(.easeInOut(duration: 0.3), value: luckyHour)
    }

    private var statsStrip: some View {
        let net = controller.state.casinoWon - controller.state.casinoWagered
        return HStack(spacing: 10) {
            Text("Wagered \(formatNumber(controller.state.casinoWagered))")
            Text("Won \(formatNumber(controller.state.casinoWon))")
            Text("Best \(formatNumber(controller.state.casinoBiggestWin))")
            Spacer()
            Text((net >= 0 ? "+" : "") + formatNumber(net))
                .foregroundColor(net >= 0 ? Color(red: 0.5, green: 0.85, blue: 0.5) : Theme.danger)
        }
        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
        .foregroundColor(Theme.dim)
    }

    private func publishGame(_ g: Int) {
        let games: [CasinoGame] = [.slots, .blackjack, .roulette, .mahjong]
        controller.casinoGameChanged.send(games[min(g, 3)])
        controller.casinoFocus.send(false)
        result = nil
    }
}

// MARK: - Slots

struct SlotsView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    let onResult: (CasinoResult) -> Void

    @State private var reels = ["beans", "croissant", "star"]
    @State private var locked = [false, false, false]
    @State private var winPulse = false
    @State private var spinning = false
    @State private var message = "3×⭐ 60× · 3×honey 25× · triple 10× · pair = bet back"
    @State private var rng = SystemRandomNumberGenerator()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    ZStack {
                        if winPulse {
                            Circle().fill(Theme.gold.opacity(0.35)).blur(radius: 10)
                                .frame(width: 60, height: 60)
                        }
                        PixelImage(name: slotSprite(reels[i]), scale: 4)
                    }
                    .frame(width: 48, height: 48)
                    .background(Theme.bg.opacity(0.6))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(winPulse ? Theme.gold : (locked[i] && spinning ? Theme.cream.opacity(0.6) : .clear),
                                lineWidth: winPulse ? 2.5 : 1.5))
                    .scaleEffect(locked[i] && spinning ? 1.08 : (winPulse ? 1.06 : 1.0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: locked[i])
                    .animation(.easeInOut(duration: 0.3).repeatCount(5, autoreverses: true), value: winPulse)
                }
            }
            Text(message)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
            Button(spinning ? "Spinning…" : "Spin 🪙 \(formatNumber(bet))") { spin() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.bg)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(spinning || controller.state.coins < bet ? Theme.card : Theme.gold)
                .cornerRadius(8)
                .disabled(spinning || controller.state.coins < bet)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func slotSprite(_ symbol: String) -> String {
        switch symbol {
        case "beans": return "ing_beans"
        case "croissant": return "item_croissant"
        case "matcha": return "ing_matcha"
        case "berry": return "ing_berry"
        case "honey": return "ing_honey"
        default: return "tip"
        }
    }

    private func spin() {
        guard controller.casinoTrySpend(bet) else { return }
        spinning = true
        winPulse = false
        locked = [false, false, false]
        controller.casinoFocus.send(true)
        message = "…"
        Task { @MainActor in
            let final = CasinoEngine.slotSpin(rng: &rng)
            for stop in 0..<3 {
                let near = stop == 2 && final[0] == final[1]
                let spins = near ? 10 : 6
                for _ in 0..<spins {
                    var r = reels
                    for i in stop..<3 { r[i] = CasinoEngine.slotSymbols.randomElement(using: &rng)! }
                    reels = r
                    try? await Task.sleep(nanoseconds: near ? 130_000_000 : 75_000_000)
                }
                reels[stop] = final[stop]
                locked[stop] = true
                SoundPlayer.shared.play("clack", minGap: 0.05)
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            reels = final
            let mult = CasinoEngine.slotPayout(final)
            let jackpot = final.allSatisfy { $0 == "star" }
            if mult > 0 {
                let raw = bet * mult
                let win = CasinoEngine.applyLuckyHour(raw, bet: bet,
                                                       active: Events.isActive("lucky_hour", controller.state))
                controller.casinoAward(win)
                message = "\(Int(mult))× — won 🪙 \(formatNumber(win))!"
                winPulse = true
                if jackpot {
                    controller.unlockAchievement("slots_jackpot")
                    onResult(CasinoResult(text: "JACKPOT!\n+🪙 \(formatNumber(win))", kind: .jackpot))
                } else {
                    onResult(CasinoResult(text: "+🪙 \(formatNumber(win))", kind: .win))
                }
            } else {
                message = "No luck — try again?"
                onResult(CasinoResult(text: "No match", kind: .lose))
            }
            spinning = false
            locked = [false, false, false]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                controller.casinoFocus.send(false)
            }
        }
    }
}

// MARK: - Blackjack

struct BlackjackView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    let onResult: (CasinoResult) -> Void

    @State private var hand: CasinoEngine.BlackjackGame?
    @State private var settled = false
    @State private var message = "Dealer stands on 17 · blackjack pays 3:2"
    @State private var rng = SystemRandomNumberGenerator()
    @State private var busy = false

    private var inRound: Bool { hand.map { !$0.finished } ?? false }

    var body: some View {
        VStack(spacing: 8) {
            if let g = hand {
                cardRow("Dealer", cards: g.finished ? g.dealer : [g.dealer[0]],
                        hidden: g.finished ? 0 : 1,
                        value: g.finished ? CasinoEngine.handValue(g.dealer) : nil)
                cardRow("You", cards: g.player, hidden: 0, value: CasinoEngine.handValue(g.player))
            }
            Text(message)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.cream)
            if inRound, let g = hand {
                HStack(spacing: 8) {
                    actionButton("Hit", disabled: busy) { act { mutate { $0.hit() } } }
                    actionButton("Stand", disabled: busy) { act { mutate { $0.stand() } } }
                    actionButton("Double",
                                 disabled: busy || g.player.count != 2 || controller.state.coins < g.bet) {
                        act {
                            _ = controller.casinoTrySpend(g.bet)
                            mutate { $0.doubleDown() }
                        }
                    }
                }
            } else {
                actionButton("▶ Deal a hand — 🪙 \(formatNumber(bet))",
                             disabled: busy || controller.state.coins < bet) { act { deal() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func act(_ body: () -> Void) {
        guard !busy else { return }
        busy = true
        body()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { busy = false }
    }

    private func cardRow(_ title: String, cards: [CasinoEngine.Card], hidden: Int, value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
                .frame(width: 42, alignment: .leading)
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                CardView(card: card)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 1.3)),
                        removal: .opacity))
            }
            ForEach(0..<hidden, id: \.self) { _ in
                CardBack().transition(.opacity)
            }
            if let v = value {
                Text("= \(v)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(v > 21 ? Theme.danger : Theme.gold)
            }
            Spacer()
        }
    }

    private func actionButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .foregroundColor(disabled ? Theme.dim : Theme.bg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(disabled ? Theme.card.opacity(0.6) : Theme.gold)
            .cornerRadius(7)
            .disabled(disabled)
    }

    private func deal() {
        guard controller.casinoTrySpend(bet) else { return }
        settled = false
        controller.casinoFocus.send(true)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            hand = CasinoEngine.BlackjackGame(bet: bet, rng: &rng)
        }
        SoundPlayer.shared.play("clack", minGap: 0.05)
        message = "Hit, stand or double?"
        publishCards()
        settleIfFinished()
    }

    private func publishCards() {
        guard let g = hand else { return }
        func fmt(_ c: CasinoEngine.Card) -> (String, Bool) { ("\(c.label)\(c.suitSymbol)", c.isRed) }
        controller.blackjackDisplay.send((
            player: g.player.map(fmt),
            dealer: (g.finished ? g.dealer : [g.dealer[0]]).map(fmt),
            hole: !g.finished))
    }

    private func mutate(_ change: (inout CasinoEngine.BlackjackGame) -> Void) {
        guard var g = hand else { return }
        change(&g)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { hand = g }
        SoundPlayer.shared.play("clack", minGap: 0.05)
        publishCards()
        settleIfFinished()
    }

    private func settleIfFinished() {
        guard let g = hand, g.finished, !settled else { return }
        settled = true
        let payout = CasinoEngine.applyLuckyHour(g.payout, bet: g.bet,
                                                  active: Events.isActive("lucky_hour", controller.state))
        controller.casinoAward(payout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            controller.casinoFocus.send(false)
        }
        let net = payout - g.bet
        switch g.outcome {
        case .playerBlackjack:
            message = "BLACKJACK! Won 🪙 \(formatNumber(net))"
            controller.unlockAchievement("blackjack_natural")
            onResult(CasinoResult(text: "BLACKJACK!\n+🪙 \(formatNumber(net))", kind: .jackpot))
        case .win:
            message = "You win 🪙 \(formatNumber(net))"
            onResult(CasinoResult(text: "+🪙 \(formatNumber(net))", kind: .win))
        case .push:
            message = "Push — bet returned"
            onResult(CasinoResult(text: "Push", kind: .push))
        case .lose:
            let bust = CasinoEngine.handValue(g.player) > 21
            message = bust ? "Bust! Dealer takes it" : "Dealer wins"
            onResult(CasinoResult(text: bust ? "BUST" : "Dealer wins", kind: .lose))
        case nil: break
        }
    }
}

struct CardView: View {
    let card: CasinoEngine.Card

    var body: some View {
        VStack(spacing: 0) {
            Text(card.label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
            Text(card.suitSymbol)
                .font(.system(size: 10))
        }
        .foregroundColor(card.isRed ? Color(red: 0.8, green: 0.2, blue: 0.2) : .black)
        .frame(width: 26, height: 36)
        .background(Color.white)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
    }
}

struct CardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(red: 0.35, green: 0.25, blue: 0.5))
            .frame(width: 26, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .padding(3))
    }
}

// MARK: - Roulette

/// Real European wheel pocket order (0 through 36), used both to draw the
/// wheel and to compute the exact stopping angle for a spin result.
enum RouletteWheelOrder {
    static let sequence = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23,
                           10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
    static func index(of number: Int) -> Int { sequence.firstIndex(of: number) ?? 0 }
    static let anglePerPocket = 360.0 / Double(sequence.count)
}

struct RouletteWheel: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let seq = RouletteWheelOrder.sequence
            let step = RouletteWheelOrder.anglePerPocket
            for (i, num) in seq.enumerated() {
                let start = Angle(degrees: Double(i) * step - 90 - step / 2)
                let end = Angle(degrees: Double(i) * step - 90 + step / 2)
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                path.closeSubpath()
                let color: Color = num == 0
                    ? Color(red: 0.15, green: 0.5, blue: 0.3)
                    : (CasinoEngine.redNumbers.contains(num)
                        ? Color(red: 0.72, green: 0.18, blue: 0.16)
                        : Color(red: 0.12, green: 0.12, blue: 0.15))
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                let mid = Angle(degrees: Double(i) * step - 90)
                let labelR = radius * 0.74
                let lp = CGPoint(x: center.x + Foundation.cos(mid.radians) * labelR,
                                 y: center.y + Foundation.sin(mid.radians) * labelR)
                context.draw(Text("\(num)").font(.system(size: 6.5, weight: .bold)).foregroundColor(.white), at: lp)
            }
            context.stroke(Path(ellipseIn: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2)),
                           with: .color(Theme.gold.opacity(0.7)), lineWidth: 1.5)
            let hub = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: hub), with: .color(Theme.gold))
        }
    }
}

struct RouletteView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    let onResult: (CasinoResult) -> Void

    @State private var betKind = 0
    @State private var number = 17
    @State private var history: [Int] = []
    @State private var message = "European wheel — single zero"
    @State private var spinning = false
    @State private var rotation: Double = 0
    @State private var rng = SystemRandomNumberGenerator()

    private static let kinds = ["Red", "Black", "Odd", "Even", "1-18", "19-36", "1st 12", "2nd 12", "3rd 12", "Number"]

    private var currentBet: CasinoEngine.RouletteBet {
        switch Self.kinds[betKind] {
        case "Red": return .red
        case "Black": return .black
        case "Odd": return .odd
        case "Even": return .even
        case "1-18": return .low
        case "19-36": return .high
        case "1st 12": return .dozen(0)
        case "2nd 12": return .dozen(1)
        case "3rd 12": return .dozen(2)
        default: return .straight(number)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RouletteWheel()
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(rotation))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.cream)
                    .offset(y: -54)
                Circle().fill(Theme.card).frame(width: 10, height: 10)
            }
            .padding(.vertical, 2)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(Array(Self.kinds.enumerated()), id: \.offset) { i, kind in
                    Button {
                        betKind = i
                    } label: {
                        Text(kind)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(betKind == i ? Theme.bg : Theme.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(betKind == i ? Theme.gold : Theme.bg.opacity(0.5))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            if Self.kinds[betKind] == "Number" {
                Stepper("Number: \(number) (pays 35:1)", value: $number, in: 0...36)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cream)
            }
            if !history.isEmpty {
                HStack(spacing: 3) {
                    Text("Last:")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                    ForEach(Array(history.suffix(9).enumerated()), id: \.offset) { _, n in
                        Text("\(n)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 17, height: 15)
                            .background(rouletteColor(n))
                            .cornerRadius(3)
                    }
                }
            }
            Text(message)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.cream)
            Button(spinning ? "Spinning…" : "Spin 🪙 \(formatNumber(bet))") { spin() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.bg)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(spinning || controller.state.coins < bet ? Theme.card : Theme.gold)
                .cornerRadius(8)
                .disabled(spinning || controller.state.coins < bet)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func rouletteColor(_ n: Int) -> Color {
        if n == 0 { return Color(red: 0.15, green: 0.5, blue: 0.3) }
        return CasinoEngine.redNumbers.contains(n)
            ? Color(red: 0.75, green: 0.2, blue: 0.2)
            : Color(red: 0.15, green: 0.15, blue: 0.18)
    }

    private func spin() {
        guard controller.casinoTrySpend(bet) else { return }
        spinning = true
        controller.casinoFocus.send(true)
        let placed = currentBet
        let result = CasinoEngine.rouletteSpin(rng: &rng)
        let targetIndex = RouletteWheelOrder.index(of: result)
        let targetAngle = -Double(targetIndex) * RouletteWheelOrder.anglePerPocket

        // reset without animating, then spin several full turns to the target
        withTransaction(Transaction(animation: nil)) { rotation = 0 }
        message = "Spinning…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.timingCurve(0.15, 0.85, 0.25, 1, duration: 2.6)) {
                rotation = 6 * 360 + targetAngle
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            controller.rouletteResult.send(result)
            history.append(result)
            let raw = CasinoEngine.roulettePayout(placed, result: result) * bet
            let ret = CasinoEngine.applyLuckyHour(raw, bet: bet,
                                                   active: Events.isActive("lucky_hour", controller.state))
            controller.casinoAward(ret)
            let color = result == 0 ? "green" : (CasinoEngine.redNumbers.contains(result) ? "red" : "black")
            if ret > 0 {
                message = "Ball lands \(result) (\(color)) — won 🪙 \(formatNumber(ret - bet))!"
                onResult(CasinoResult(text: "\(result) \(color)\n+🪙 \(formatNumber(ret - bet))", kind: .win))
            } else {
                message = "Ball lands \(result) (\(color)) — house takes it"
                onResult(CasinoResult(text: "\(result) \(color)", kind: .lose))
            }
            spinning = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                controller.casinoFocus.send(false)
            }
        }
    }
}

// MARK: - Mahjong (Hong Kong style, vs 3 AI)

struct MahjongView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    let onResult: (CasinoResult) -> Void

    @State private var game: Mahjong.Game?
    @State private var settled = false
    @State private var message = "4 melds + a pair wins · self-draw 3× · off a discard 2.5×"
    @State private var rng = SystemRandomNumberGenerator()
    @State private var selected: Mahjong.Tile?
    @State private var busy = false

    private static let aiFaces = ["🐱", "🐻", "🐰"]
    private static let seatNames = ["You", "Momo", "Baxter", "Lily"]

    var body: some View {
        VStack(spacing: 8) {
            if let g = game {
                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { seat in
                        Text("\(Self.aiFaces[seat - 1]) \(g.hands[seat].count)  \(g.melds[seat].isEmpty ? "" : "·\(g.melds[seat].count)m")")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.dim)
                    }
                    Spacer()
                    Text("wall \(g.wall.count)")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                if !g.discards.isEmpty {
                    HStack(spacing: 1) {
                        let recent = Array(g.discards.suffix(9))
                        ForEach(Array(recent.enumerated()), id: \.offset) { i, t in
                            tileFace(t, size: 17)
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .stroke(i == recent.count - 1 ? Theme.gold : .clear, lineWidth: 1.5))
                        }
                        if g.lastDiscardSeat >= 0 {
                            Text("← \(Self.seatNames[g.lastDiscardSeat])")
                                .font(.system(size: 8.5, design: .rounded))
                                .foregroundColor(Theme.dim)
                        }
                        Spacer()
                    }
                }
                if !g.melds[0].isEmpty {
                    HStack(spacing: 5) {
                        Text("Your melds:")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(Theme.dim)
                        ForEach(g.melds[0]) { meld in
                            HStack(spacing: 1) {
                                ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, t in
                                    tileFace(t, size: 15)
                                }
                            }
                            .padding(2)
                            .background(Color(red: 0.2, green: 0.4, blue: 0.28).opacity(0.6))
                            .cornerRadius(4)
                        }
                        Spacer()
                    }
                }
                Text(message)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cream)
                phaseControls(g)
            } else {
                Text(message)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cream)
                    .multilineTextAlignment(.center)
                mjButton("▶ Sit at the table — 🪙 \(formatNumber(bet))",
                         disabled: controller.state.coins < bet) { deal() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.card)
        .cornerRadius(9)
        .onChange(of: game?.discards.count ?? 0) { n in
            controller.mahjongDiscards.send(n)
        }
    }

    @ViewBuilder
    private func phaseControls(_ g: Mahjong.Game) -> some View {
        switch g.phase {
        case .playerDiscard:
            VStack(spacing: 5) {
                if g.playerCanWinNow {
                    mjButton("WIN — Self-draw!", glow: true) { mutate { $0.playerDeclareWin() } }
                }
                Text(selected == nil ? "Tap a tile, tap again to discard" : "Tap again to discard — or pick another")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(Theme.dim)
                var handTiles = g.hands[0]
                let drawn: Mahjong.Tile? = g.lastDrawn
                let _ = drawn.map { d in
                    if let i = handTiles.firstIndex(of: d) { handTiles.remove(at: i) }
                }
                HStack(spacing: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 3), count: 7), spacing: 4) {
                        ForEach(Array(handTiles.enumerated()), id: \.offset) { _, t in
                            handTile(t)
                        }
                    }
                    if let d = drawn {
                        VStack(spacing: 1) {
                            Text("drew")
                                .font(.system(size: 7, design: .rounded))
                                .foregroundColor(Theme.gold)
                            handTile(d)
                        }
                        .padding(.leading, 6)
                    }
                }
            }
        case .playerClaim(let d, _):
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Text("Discarded:")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(Theme.dim)
                    tileFace(d, size: 28)
                }
                HStack(spacing: 6) {
                    if canClaimWin(g, d) { mjButton("WIN!", glow: true) { mutate { $0.playerClaimWin() } } }
                    if g.canPong(d) { mjButton("Pong") { mutate { $0.playerPong(rng: &rng) } } }
                    ForEach(g.chowOptions(d), id: \.id) { low in
                        mjButton("Chow \(low.rank)-\(low.rank + 2)") { mutate { $0.playerChow(low, rng: &rng) } }
                    }
                    mjButton("Pass") { mutateSlow { $0.playerPass(rng: &rng) } }
                }
            }
        case .finished:
            mjButton("▶ Play again — 🪙 \(formatNumber(bet))", disabled: controller.state.coins < bet) { deal() }
        }
    }

    private func handTile(_ t: Mahjong.Tile) -> some View {
        Button {
            if selected == t {
                selected = nil
                SoundPlayer.shared.play("clack", minGap: 0.1)
                mutateSlow { $0.playerDiscard(t, rng: &rng) }
            } else {
                selected = t
            }
        } label: {
            tileFace(t, size: 28)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(selected == t ? Theme.gold : .clear, lineWidth: 2))
                .offset(y: selected == t ? -3 : 0)
                .animation(.easeOut(duration: 0.12), value: selected)
        }
        .buttonStyle(.plain)
    }

    private func canClaimWin(_ g: Mahjong.Game, _ d: Mahjong.Tile) -> Bool {
        var h = g.hands[0]; h.append(d)
        return Mahjong.isWinningHand(concealed: h, claimedMelds: g.melds[0].count)
    }

    private func tileFace(_ t: Mahjong.Tile, size: CGFloat) -> some View {
        PixelImage(name: t.spriteIcon, scale: size / 18)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
    }

    @State private var glowPulse = false

    private func mjButton(_ label: String, disabled: Bool = false, glow: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(disabled ? Theme.dim : Theme.bg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(disabled ? Theme.card.opacity(0.6) : Theme.gold)
            .cornerRadius(7)
            .shadow(color: glow ? Theme.gold.opacity(glowPulse ? 0.9 : 0.3) : .clear, radius: glow ? 6 : 0)
            .animation(glow ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: glowPulse)
            .onAppear { if glow { glowPulse = true } }
            .disabled(disabled)
    }

    private func deal() {
        guard controller.casinoTrySpend(bet) else { return }
        settled = false
        controller.casinoFocus.send(true)
        game = Mahjong.Game(rng: &rng)
        message = "Your turn — tap a tile to discard"
    }

    private func mutateSlow(_ change: @escaping (inout Mahjong.Game) -> Void) {
        guard !busy, game != nil else { return }
        busy = true
        message = "· · · the table plays · · ·"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            busy = false
            mutate(change)
        }
    }

    private func mutate(_ change: (inout Mahjong.Game) -> Void) {
        guard !busy, var g = game else { return }
        busy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { busy = false }
        change(&g)
        game = g
        if case .finished(let outcome) = g.phase, !settled {
            settled = true
            let raw = Mahjong.payout(outcome, bet: bet)
            let ret = CasinoEngine.applyLuckyHour(raw, bet: bet,
                                                   active: Events.isActive("lucky_hour", controller.state))
            controller.casinoAward(ret)
            switch outcome {
            case .playerWinSelfDraw:
                message = "Self-draw! Won 🪙 \(formatNumber(ret - bet))"
                controller.unlockAchievement("mahjong_win")
                onResult(CasinoResult(text: "SELF-DRAW!\n+🪙 \(formatNumber(ret - bet))", kind: .jackpot))
            case .playerWinDiscard:
                message = "Mahjong! Won 🪙 \(formatNumber(ret - bet))"
                controller.unlockAchievement("mahjong_win")
                onResult(CasinoResult(text: "MAHJONG!\n+🪙 \(formatNumber(ret - bet))", kind: .win))
            case .aiWin(let seat):
                message = "\(Self.aiFaces[seat - 1]) wins this round"
                onResult(CasinoResult(text: "\(Self.seatNames[seat]) wins", kind: .lose))
            case .wallExhausted:
                message = "Wall empty — draw, bet returned"
                onResult(CasinoResult(text: "Wall exhausted", kind: .push))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                controller.casinoFocus.send(false)
            }
        } else if case .playerClaim = g.phase {
            message = "You can claim this tile!"
        } else if case .playerDiscard = g.phase {
            message = "Your turn — tap a tile to discard"
        }
    }
}
