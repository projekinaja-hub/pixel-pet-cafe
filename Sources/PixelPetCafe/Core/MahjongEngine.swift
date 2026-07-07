import Foundation

/// Hong Kong–style mahjong vs 3 AI players, simplified but real:
/// 136 tiles, draw/discard turns, Pong (any discard), Chow (from the player's
/// left), win = 4 melds + 1 pair. No kongs/flowers. Player is seat 0; the
/// discarder to the player's left is seat 3.
enum Mahjong {

    // MARK: tiles

    struct Tile: Hashable, Comparable, Identifiable {
        let suit: Int   // 0 characters, 1 dots, 2 bamboo, 3 honors
        let rank: Int   // suits: 1-9 · honors: 1-4 winds E S W N, 5-7 dragons R G Wh
        var id: String { "\(suit)-\(rank)" }

        static func < (a: Tile, b: Tile) -> Bool {
            a.suit == b.suit ? a.rank < b.rank : a.suit < b.suit
        }

        /// Pixel sprite id (Sprites/mjtile_<suit>_<rank>.png) — hand-drawn tile
        /// faces render crisp and centered, unlike system mahjong glyphs which
        /// have wildly inconsistent font metrics across platforms.
        var spriteIcon: String { "mjtile_\(suit)_\(rank)" }
    }

    static func freshWall<R: RandomNumberGenerator>(rng: inout R) -> [Tile] {
        var wall: [Tile] = []
        for suit in 0..<3 {
            for rank in 1...9 {
                for _ in 0..<4 { wall.append(Tile(suit: suit, rank: rank)) }
            }
        }
        for rank in 1...7 {
            for _ in 0..<4 { wall.append(Tile(suit: 3, rank: rank)) }
        }
        wall.shuffle(using: &rng)
        return wall
    }

    // MARK: win detection (4 melds + pair, concealed part via backtracking)

    /// `melds` = number of melds still needed from `tiles` (claimed melds excluded).
    static func canFormSets(_ tiles: [Tile], needMelds: Int, hasPair: Bool) -> Bool {
        if tiles.isEmpty { return needMelds == 0 && hasPair }
        var counts: [Tile: Int] = [:]
        for t in tiles { counts[t, default: 0] += 1 }
        let sorted = tiles.sorted()
        let first = sorted[0]
        // try pair
        if !hasPair, counts[first]! >= 2 {
            var rest = sorted
            removeTiles(&rest, first, 2)
            if canFormSets(rest, needMelds: needMelds, hasPair: true) { return true }
        }
        guard needMelds > 0 else { return false }
        // try triplet
        if counts[first]! >= 3 {
            var rest = sorted
            removeTiles(&rest, first, 3)
            if canFormSets(rest, needMelds: needMelds - 1, hasPair: hasPair) { return true }
        }
        // try run
        if first.suit < 3 && first.rank <= 7 {
            let t2 = Tile(suit: first.suit, rank: first.rank + 1)
            let t3 = Tile(suit: first.suit, rank: first.rank + 2)
            if counts[t2, default: 0] >= 1, counts[t3, default: 0] >= 1 {
                var rest = sorted
                removeTiles(&rest, first, 1)
                removeTiles(&rest, t2, 1)
                removeTiles(&rest, t3, 1)
                if canFormSets(rest, needMelds: needMelds - 1, hasPair: hasPair) { return true }
            }
        }
        return false
    }

    private static func removeTiles(_ tiles: inout [Tile], _ tile: Tile, _ n: Int) {
        var left = n
        tiles.removeAll { t in
            if t == tile, left > 0 { left -= 1; return true }
            return false
        }
    }

    static func isWinningHand(concealed: [Tile], claimedMelds: Int) -> Bool {
        canFormSets(concealed, needMelds: 4 - claimedMelds, hasPair: false)
    }

    // MARK: game

    enum Phase: Equatable {
        case playerDiscard                 // player has 14-x tiles, must discard
        case playerClaim(discard: Tile, from: Int)  // player may pong/chow/win/pass
        case finished(Outcome)
    }

    enum Outcome: Equatable {
        case playerWinSelfDraw    // pays 3×
        case playerWinDiscard     // pays 2.5×
        case aiWin(seat: Int)     // bet lost
        case wallExhausted        // bet returned
    }

    struct Meld: Equatable, Identifiable {
        let tiles: [Tile]
        var id: String { tiles.map(\.id).joined(separator: "+") }
    }

    struct Game {
        var wall: [Tile]
        var hands: [[Tile]]          // seat 0 = player
        var melds: [[Meld]]
        var discards: [Tile] = []    // shared pool, newest last
        var phase: Phase
        var lastDiscardSeat = -1
        var lastDrawn: Tile?         // the tile the player just drew

        init<R: RandomNumberGenerator>(rng: inout R) {
            var w = Mahjong.freshWall(rng: &rng)
            hands = (0..<4).map { _ in
                (0..<13).map { _ in w.removeLast() }.sorted()
            }
            melds = [[], [], [], []]
            wall = w
            // player draws the first tile
            let first = wall.removeLast()
            hands[0].append(first)
            hands[0].sort()
            lastDrawn = first
            phase = .playerDiscard
        }

        var playerCanWinNow: Bool {
            Mahjong.isWinningHand(concealed: hands[0], claimedMelds: melds[0].count)
        }

        // MARK: player actions

        /// Discard from the player's hand, then run AI turns.
        mutating func playerDiscard<R: RandomNumberGenerator>(_ tile: Tile, rng: inout R) {
            guard case .playerDiscard = phase, let i = hands[0].firstIndex(of: tile) else { return }
            hands[0].remove(at: i)
            lastDrawn = nil
            discards.append(tile)
            lastDiscardSeat = 0
            runAI(from: 1, pendingDiscard: tile, discardSeat: 0, rng: &rng)
        }

        mutating func playerDeclareWin() {
            if case .playerDiscard = phase, playerCanWinNow {
                phase = .finished(.playerWinSelfDraw)
            }
        }

        mutating func playerPong<R: RandomNumberGenerator>(rng: inout R) {
            guard case .playerClaim(let d, _) = phase, canPong(d) else { return }
            Mahjong.removeTiles(&hands[0], d, 2)
            melds[0].append(Meld(tiles: [d, d, d]))
            lastDrawn = nil
            phase = .playerDiscard
            _ = rng
        }

        mutating func playerChow<R: RandomNumberGenerator>(_ low: Tile, rng: inout R) {
            guard case .playerClaim(let d, let seat) = phase, seat == 3,
                  let run = chowRun(d, startingAt: low) else { return }
            for t in run where t != d {
                if let i = hands[0].firstIndex(of: t) { hands[0].remove(at: i) }
            }
            melds[0].append(Meld(tiles: run))
            lastDrawn = nil
            phase = .playerDiscard
            _ = rng
        }

        mutating func playerClaimWin() {
            guard case .playerClaim(let d, _) = phase else { return }
            var h = hands[0]; h.append(d)
            if Mahjong.isWinningHand(concealed: h, claimedMelds: melds[0].count) {
                hands[0] = h
                phase = .finished(.playerWinDiscard)
            }
        }

        mutating func playerPass<R: RandomNumberGenerator>(rng: inout R) {
            guard case .playerClaim(let d, let seat) = phase else { return }
            runAI(from: seat + 1, pendingDiscard: d, discardSeat: seat, rng: &rng)
        }

        // MARK: claims available to the player

        func canPong(_ tile: Tile) -> Bool {
            hands[0].filter { $0 == tile }.count >= 2
        }

        /// Chow options: the possible runs using the discard (player's left only).
        func chowOptions(_ tile: Tile) -> [Tile] {
            guard tile.suit < 3 else { return [] }
            var starts: [Tile] = []
            for offset in -2...0 {
                let low = tile.rank + offset
                guard low >= 1, low + 2 <= 9 else { continue }
                let run = (low...(low + 2)).map { Tile(suit: tile.suit, rank: $0) }
                let needed = run.filter { $0 != tile }
                if needed.allSatisfy({ n in hands[0].contains(n) }) {
                    starts.append(run[0])
                }
            }
            return starts
        }

        private func chowRun(_ discard: Tile, startingAt low: Tile) -> [Tile]? {
            guard chowOptions(discard).contains(low) else { return nil }
            return (low.rank...(low.rank + 2)).map { Tile(suit: discard.suit, rank: $0) }
        }

        // MARK: AI

        /// Advances AI seats until the player must act again (or game ends).
        private mutating func runAI<R: RandomNumberGenerator>(
            from seat: Int, pendingDiscard: Tile?, discardSeat: Int, rng: inout R
        ) {
            var discard = pendingDiscard
            var dSeat = discardSeat
            var next = seat
            var safety = 400
            while safety > 0 {
                safety -= 1
                if next > 3 { next = 0 }
                if next == 0 {
                    // back to the player: draw a tile (discard passed everyone)
                    guard !wall.isEmpty else { phase = .finished(.wallExhausted); return }
                    let drawn = wall.removeLast()
                    hands[0].append(drawn)
                    hands[0].sort()
                    lastDrawn = drawn
                    phase = .playerDiscard
                    return
                }
                // AI may claim the pending discard: win > pong
                if let d = discard {
                    var h = hands[next]; h.append(d)
                    if Mahjong.isWinningHand(concealed: h, claimedMelds: melds[next].count) {
                        hands[next] = h.sorted()
                        phase = .finished(.aiWin(seat: next))
                        return
                    }
                    if hands[next].filter({ $0 == d }).count >= 2, Bool.random(using: &rng) {
                        Mahjong.removeTiles(&hands[next], d, 2)
                        melds[next].append(Meld(tiles: [d, d, d]))
                        discard = nil
                        // claimed: this AI must now discard
                        let out = aiChooseDiscard(next, rng: &rng)
                        if let i = hands[next].firstIndex(of: out) { hands[next].remove(at: i) }
                        discards.append(out)
                        lastDiscardSeat = next
                        discard = out
                        dSeat = next
                        if next == 3, playerHasClaim(out) { phase = .playerClaim(discard: out, from: 3); return }
                        if playerCanPongOrWin(out) { phase = .playerClaim(discard: out, from: next); return }
                        next += 1
                        continue
                    }
                }
                // normal AI turn: draw + discard
                guard !wall.isEmpty else { phase = .finished(.wallExhausted); return }
                hands[next].append(wall.removeLast())
                hands[next].sort()
                if Mahjong.isWinningHand(concealed: hands[next], claimedMelds: melds[next].count) {
                    phase = .finished(.aiWin(seat: next))
                    return
                }
                let out = aiChooseDiscard(next, rng: &rng)
                if let i = hands[next].firstIndex(of: out) { hands[next].remove(at: i) }
                discards.append(out)
                lastDiscardSeat = next
                discard = out
                dSeat = next
                if next == 3, playerHasClaim(out) { phase = .playerClaim(discard: out, from: 3); return }
                if playerCanPongOrWin(out) { phase = .playerClaim(discard: out, from: next); return }
                next += 1
            }
            phase = .finished(.wallExhausted)
            _ = dSeat
        }

        private func playerCanPongOrWin(_ tile: Tile) -> Bool {
            if canPong(tile) { return true }
            var h = hands[0]; h.append(tile)
            return Mahjong.isWinningHand(concealed: h, claimedMelds: melds[0].count)
        }

        private func playerHasClaim(_ tile: Tile) -> Bool {
            playerCanPongOrWin(tile) || !chowOptions(tile).isEmpty
        }

        /// Heuristic: keep pairs/triplets and suited neighbors, ditch lone honors first.
        private func aiChooseDiscard<R: RandomNumberGenerator>(_ seat: Int, rng: inout R) -> Tile {
            let hand = hands[seat]
            func usefulness(_ t: Tile) -> Int {
                let same = hand.filter { $0 == t }.count
                var score = (same - 1) * 4
                if t.suit < 3 {
                    for dr in [-2, -1, 1, 2] {
                        let n = Tile(suit: t.suit, rank: t.rank + dr)
                        if hand.contains(n) { score += abs(dr) == 1 ? 2 : 1 }
                    }
                }
                return score
            }
            let minScore = hand.map(usefulness).min() ?? 0
            let worst = hand.filter { usefulness($0) == minScore }
            return worst[Int.random(in: 0..<worst.count, using: &rng)]
        }

    }

    /// Coins returned for the (already deducted) bet.
    static func payout(_ outcome: Outcome, bet: Double) -> Double {
        switch outcome {
        case .playerWinSelfDraw: return bet * 3
        case .playerWinDiscard: return bet * 2.5
        case .aiWin: return 0
        case .wallExhausted: return bet
        }
    }
}
