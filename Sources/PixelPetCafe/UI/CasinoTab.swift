import SwiftUI

/// Casino corner: slots, blackjack, roulette. Real rules, café coins.
struct CasinoTab: View {
    @ObservedObject var controller: GameController
    @State private var game = 0
    @State private var bet: Double = 25

    var body: some View {
        if !controller.state.casinoUnlocked {
            LockedRow(hint: "Casino corner · unlocks at 🪙 \(formatNumber(CasinoEngine.unlockAtLifetime)) lifetime")
        } else {
            Picker("", selection: $game) {
                Text("🎰 Slots").tag(0)
                Text("🃏 Blackjack").tag(1)
                Text("🎡 Roulette").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 5) {
                Text("Bet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                ForEach([25.0, 100, 500, 2500], id: \.self) { b in
                    Button {
                        bet = b
                    } label: {
                        Text(formatNumber(b))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(bet == b ? Theme.bg : Theme.dim)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(bet == b ? Theme.gold : Theme.card)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            switch game {
            case 0: SlotsView(controller: controller, bet: $bet)
            case 1: BlackjackView(controller: controller, bet: $bet)
            default: RouletteView(controller: controller, bet: $bet)
            }
            Text("The house always wins in the long run — gambling never counts toward unlocks or stars.")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(Theme.dim.opacity(0.8))
        }
    }
}

// MARK: - Slots

struct SlotsView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    @State private var reels = ["beans", "croissant", "star"]
    @State private var spinning = false
    @State private var message = "3×⭐ 60× · 3×🍯 25× · triple 10× · pair = bet back"
    @State private var rng = SystemRandomNumberGenerator()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    PixelImage(name: slotSprite(reels[i]), scale: 4)
                        .frame(width: 48, height: 48)
                        .background(Theme.bg.opacity(0.6))
                        .cornerRadius(8)
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
        default: return "tip"              // ⭐ = the golden coin
        }
    }

    private func spin() {
        guard controller.casinoTrySpend(bet) else { return }
        spinning = true
        message = "…"
        Task { @MainActor in
            for _ in 0..<9 {   // reel flicker
                reels = CasinoEngine.slotSpin(rng: &rng)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            let final = CasinoEngine.slotSpin(rng: &rng)
            reels = final
            let mult = CasinoEngine.slotPayout(final)
            if mult > 0 {
                let win = bet * mult
                controller.casinoAward(win)
                message = "🎉 \(Int(mult))× — won 🪙 \(formatNumber(win))!"
            } else {
                message = "No luck — try again?"
            }
            spinning = false
        }
    }
}

// MARK: - Blackjack

struct BlackjackView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    @State private var hand: CasinoEngine.BlackjackGame?
    @State private var settled = false
    @State private var message = "Dealer stands on 17 · blackjack pays 3:2"
    @State private var rng = SystemRandomNumberGenerator()

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
            HStack(spacing: 8) {
                if let g = hand, !g.finished {
                    actionButton("Hit") { mutate { $0.hit() } }
                    actionButton("Stand") { mutate { $0.stand() } }
                    if g.player.count == 2, controller.state.coins >= g.bet {
                        actionButton("Double") {
                            _ = controller.casinoTrySpend(g.bet)
                            mutate { $0.doubleDown() }
                        }
                    }
                } else {
                    actionButton("Deal 🪙 \(formatNumber(bet))", disabled: controller.state.coins < bet) { deal() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card)
        .cornerRadius(9)
    }

    private func cardRow(_ title: String, cards: [CasinoEngine.Card], hidden: Int, value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.dim)
                .frame(width: 42, alignment: .leading)
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                CardView(card: card)
            }
            ForEach(0..<hidden, id: \.self) { _ in CardBack() }
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
        hand = CasinoEngine.BlackjackGame(bet: bet, rng: &rng)
        message = "Hit, stand or double?"
        settleIfFinished()
    }

    private func mutate(_ change: (inout CasinoEngine.BlackjackGame) -> Void) {
        guard var g = hand else { return }
        change(&g)
        hand = g
        settleIfFinished()
    }

    private func settleIfFinished() {
        guard let g = hand, g.finished, !settled else { return }
        settled = true
        controller.casinoAward(g.payout)
        switch g.outcome {
        case .playerBlackjack: message = "🃏 BLACKJACK! Won 🪙 \(formatNumber(g.payout - g.bet))"
        case .win: message = "🎉 You win 🪙 \(formatNumber(g.payout - g.bet))"
        case .push: message = "Push — bet returned"
        case .lose: message = CasinoEngine.handValue(g.player) > 21 ? "Bust! Dealer takes it" : "Dealer wins"
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
            .overlay(Text("🐾").font(.system(size: 12)))
    }
}

// MARK: - Roulette

struct RouletteView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    @State private var betKind = 0
    @State private var number = 17
    @State private var history: [Int] = []
    @State private var message = "European wheel — single zero"
    @State private var spinning = false
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
            // bet type grid
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
        let placed = currentBet
        Task { @MainActor in
            for _ in 0..<8 {
                message = "🎡 \(CasinoEngine.rouletteSpin(rng: &rng))…"
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            let result = CasinoEngine.rouletteSpin(rng: &rng)
            history.append(result)
            let ret = CasinoEngine.roulettePayout(placed, result: result) * bet
            controller.casinoAward(ret)
            let color = result == 0 ? "green" : (CasinoEngine.redNumbers.contains(result) ? "red" : "black")
            message = ret > 0
                ? "Ball lands \(result) (\(color)) — won 🪙 \(formatNumber(ret - bet))!"
                : "Ball lands \(result) (\(color)) — house takes it"
            spinning = false
        }
    }
}
