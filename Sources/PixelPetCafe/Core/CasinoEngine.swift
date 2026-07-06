import Foundation

/// Real-rules casino minigames, all pure and seedable. Bets move `coins` only —
/// gambling never advances lifetime counters, unlocks or prestige.
enum CasinoEngine {
    static let unlockAtLifetime: Double = 50_000

    // MARK: - Slots

    /// Café-themed symbols, weighted. Star is rare, honey uncommon.
    static let slotSymbols = ["beans", "croissant", "matcha", "berry", "honey", "star"]
    static let slotWeights: [Double] = [26, 24, 20, 16, 10, 4]

    static func slotSpin<R: RandomNumberGenerator>(rng: inout R) -> [String] {
        (0..<3).map { _ in
            var roll = Double.random(in: 0..<slotWeights.reduce(0, +), using: &rng)
            for (i, w) in slotWeights.enumerated() {
                if roll < w { return slotSymbols[i] }
                roll -= w
            }
            return slotSymbols[0]
        }
    }

    /// Payout multiple of the bet (0 = lost).
    static func slotPayout(_ reels: [String]) -> Double {
        guard reels.count == 3 else { return 0 }
        if reels[0] == reels[1], reels[1] == reels[2] {
            if reels[0] == "star" { return 60 }
            if reels[0] == "honey" { return 25 }
            return 10
        }
        if reels[0] == reels[1] || reels[1] == reels[2] || reels[0] == reels[2] {
            return 1    // pair: money back (overall RTP ≈ 94%)
        }
        return 0
    }

    // MARK: - Cards (blackjack)

    struct Card: Equatable {
        let rank: Int      // 1=A … 11=J 12=Q 13=K
        let suit: Int      // 0♠ 1♥ 2♦ 3♣
        var label: String {
            let r = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank - 1]
            return r
        }
        var suitSymbol: String { ["♠", "♥", "♦", "♣"][suit] }
        var isRed: Bool { suit == 1 || suit == 2 }
    }

    static func freshDeck<R: RandomNumberGenerator>(rng: inout R) -> [Card] {
        var deck = (0..<4).flatMap { s in (1...13).map { Card(rank: $0, suit: s) } }
        deck.shuffle(using: &rng)
        return deck
    }

    /// Best blackjack value ≤ 21 when possible (aces 1 or 11).
    static func handValue(_ hand: [Card]) -> Int {
        var total = 0
        var aces = 0
        for c in hand {
            if c.rank == 1 { aces += 1; total += 1 } else { total += min(c.rank, 10) }
        }
        while aces > 0, total + 10 <= 21 {
            total += 10
            aces -= 1
        }
        return total
    }

    static func isBlackjack(_ hand: [Card]) -> Bool {
        hand.count == 2 && handValue(hand) == 21
    }

    enum BlackjackOutcome: Equatable {
        case playerBlackjack   // pays 3:2
        case win               // pays 1:1
        case push              // bet returned
        case lose
    }

    /// One blackjack round. Player draws via `hit`/`stand`/`double`; dealer
    /// stands on all 17s.
    struct BlackjackGame: Equatable {
        var deck: [Card]
        var player: [Card]
        var dealer: [Card]     // dealer[0] is the upcard
        var bet: Double
        var doubled = false
        var finished = false

        init<R: RandomNumberGenerator>(bet: Double, rng: inout R) {
            var d = CasinoEngine.freshDeck(rng: &rng)
            player = [d.removeLast(), d.removeLast()]
            dealer = [d.removeLast(), d.removeLast()]
            deck = d
            self.bet = bet
            if CasinoEngine.isBlackjack(player) || CasinoEngine.isBlackjack(dealer) {
                finished = true
            }
        }

        mutating func hit() {
            guard !finished else { return }
            player.append(deck.removeLast())
            if CasinoEngine.handValue(player) >= 21 { finishDealer() }
        }

        mutating func doubleDown() {
            guard !finished, player.count == 2 else { return }
            bet *= 2
            doubled = true
            player.append(deck.removeLast())
            finishDealer()
        }

        mutating func stand() {
            guard !finished else { return }
            finishDealer()
        }

        private mutating func finishDealer() {
            finished = true
            guard CasinoEngine.handValue(player) <= 21 else { return }  // busted: dealer needn't draw
            while CasinoEngine.handValue(dealer) < 17 {
                dealer.append(deck.removeLast())
            }
        }

        var outcome: BlackjackOutcome? {
            guard finished else { return nil }
            let p = CasinoEngine.handValue(player)
            let d = CasinoEngine.handValue(dealer)
            let pBJ = CasinoEngine.isBlackjack(player)
            let dBJ = CasinoEngine.isBlackjack(dealer)
            if pBJ && dBJ { return .push }
            if pBJ { return .playerBlackjack }
            if dBJ { return .lose }
            if p > 21 { return .lose }
            if d > 21 { return .win }
            if p > d { return .win }
            if p < d { return .lose }
            return .push
        }

        /// Coins returned to the player for the (already deducted) bet.
        var payout: Double {
            switch outcome {
            case .playerBlackjack: return bet * 2.5
            case .win: return bet * 2
            case .push: return bet
            default: return 0
            }
        }
    }

    // MARK: - Roulette (European, single zero)

    static let redNumbers: Set<Int> = [1, 3, 5, 7, 9, 12, 14, 16, 18,
                                       19, 21, 23, 25, 27, 30, 32, 34, 36]

    enum RouletteBet: Equatable {
        case straight(Int)   // 35:1
        case red, black      // 1:1
        case odd, even       // 1:1
        case low, high       // 1:1  (1-18 / 19-36)
        case dozen(Int)      // 2:1  (0: 1-12, 1: 13-24, 2: 25-36)
    }

    static func rouletteSpin<R: RandomNumberGenerator>(rng: inout R) -> Int {
        Int.random(in: 0...36, using: &rng)
    }

    /// Coins returned for a 1-coin stake (includes the stake). 0 = lost.
    static func roulettePayout(_ bet: RouletteBet, result: Int) -> Double {
        switch bet {
        case .straight(let n): return result == n ? 36 : 0
        case .red:   return redNumbers.contains(result) ? 2 : 0
        case .black: return result != 0 && !redNumbers.contains(result) ? 2 : 0
        case .odd:   return result % 2 == 1 ? 2 : 0
        case .even:  return result != 0 && result % 2 == 0 ? 2 : 0
        case .low:   return (1...18).contains(result) ? 2 : 0
        case .high:  return (19...36).contains(result) ? 2 : 0
        case .dozen(let d): return result != 0 && (result - 1) / 12 == d ? 3 : 0
        }
    }
}
