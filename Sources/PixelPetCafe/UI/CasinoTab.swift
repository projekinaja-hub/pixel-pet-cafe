import SwiftUI

/// Casino corner: slots, blackjack, roulette, mahjong. Real rules, café coins.
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
                Text("🃏 21").tag(1)
                Text("🎡 Roulette").tag(2)
                Text("🀄 Mahjong").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onAppear { publishGame(game) }
            .onChange(of: game) { publishGame($0) }
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
            case 2: RouletteView(controller: controller, bet: $bet)
            default: MahjongView(controller: controller, bet: $bet)
            }
            Text("The house always wins in the long run — gambling never counts toward unlocks or stars.")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(Theme.dim.opacity(0.8))
        }
    }

    private func publishGame(_ g: Int) {
        let games: [CasinoGame] = [.slots, .blackjack, .roulette, .mahjong]
        controller.casinoGameChanged.send(games[min(g, 3)])
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
        hand = g
        publishCards()
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
            controller.rouletteResult.send(result)
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


// MARK: - Mahjong (Hong Kong style, vs 3 AI)

struct MahjongView: View {
    @ObservedObject var controller: GameController
    @Binding var bet: Double
    @State private var game: Mahjong.Game?
    @State private var settled = false
    @State private var message = "4 melds + a pair wins · self-draw 3× · off a discard 2.5×"
    @State private var rng = SystemRandomNumberGenerator()

    private static let aiFaces = ["🐱", "🐻", "🐰"]

    var body: some View {
        VStack(spacing: 8) {
            if let g = game {
                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { seat in
                        Text("\(Self.aiFaces[seat - 1]) \(g.hands[seat].count)🀫\(g.melds[seat].isEmpty ? "" : " ·\(g.melds[seat].count)m")")
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
                        ForEach(Array(g.discards.suffix(12).enumerated()), id: \.offset) { _, t in
                            tileFace(t, size: 13)
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
                mjButton("Deal 🪙 \(formatNumber(bet))", disabled: controller.state.coins < bet) { deal() }
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
                    mjButton("🀄 WIN — Self-draw!") { mutate { $0.playerDeclareWin() } }
                }
                Text("Tap a tile to discard · melds \(g.melds[0].count)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(Theme.dim)
                let hand = g.hands[0]
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 3), count: 7), spacing: 4) {
                    ForEach(Array(hand.enumerated()), id: \.offset) { _, t in
                        Button { mutate { $0.playerDiscard(t, rng: &rng) } } label: {
                            tileFace(t, size: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .playerClaim(let d, _):
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Text("Discarded:")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(Theme.dim)
                    tileFace(d, size: 20)
                }
                HStack(spacing: 6) {
                    if canClaimWin(g, d) { mjButton("WIN!") { mutate { $0.playerClaimWin() } } }
                    if g.canPong(d) { mjButton("Pong") { mutate { $0.playerPong(rng: &rng) } } }
                    ForEach(g.chowOptions(d), id: \.id) { low in
                        mjButton("Chow \(low.rank)-\(low.rank + 2)") { mutate { $0.playerChow(low, rng: &rng) } }
                    }
                    mjButton("Pass") { mutate { $0.playerPass(rng: &rng) } }
                }
            }
        case .finished:
            mjButton("Play again 🪙 \(formatNumber(bet))", disabled: controller.state.coins < bet) { deal() }
        }
    }

    private func canClaimWin(_ g: Mahjong.Game, _ d: Mahjong.Tile) -> Bool {
        var h = g.hands[0]; h.append(d)
        return Mahjong.isWinningHand(concealed: h, claimedMelds: g.melds[0].count)
    }

    private func tileFace(_ t: Mahjong.Tile, size: CGFloat) -> some View {
        Text(t.glyph)
            .font(.system(size: size))
            .foregroundColor(.black)
            .frame(width: size + 4, height: size + 8)
            .background(Color.white)
            .cornerRadius(3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.2), lineWidth: 0.5))
    }

    private func mjButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(disabled ? Theme.dim : Theme.bg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(disabled ? Theme.card.opacity(0.6) : Theme.gold)
            .cornerRadius(7)
            .disabled(disabled)
    }

    private func deal() {
        guard controller.casinoTrySpend(bet) else { return }
        settled = false
        game = Mahjong.Game(rng: &rng)
        message = "Your turn — tap a tile to discard"
    }

    private func mutate(_ change: (inout Mahjong.Game) -> Void) {
        guard var g = game else { return }
        change(&g)
        game = g
        if case .finished(let outcome) = g.phase, !settled {
            settled = true
            let ret = Mahjong.payout(outcome, bet: bet)
            controller.casinoAward(ret)
            switch outcome {
            case .playerWinSelfDraw: message = "🀄 Self-draw! Won 🪙 \(formatNumber(ret - bet))"
            case .playerWinDiscard: message = "🀄 Mahjong! Won 🪙 \(formatNumber(ret - bet))"
            case .aiWin(let seat): message = "\(Self.aiFaces[seat - 1]) wins this round"
            case .wallExhausted: message = "Wall empty — draw, bet returned"
            }
        } else if case .playerClaim = g.phase {
            message = "You can claim this tile!"
        } else if case .playerDiscard = g.phase {
            message = "Your turn — tap a tile to discard"
        }
    }
}
