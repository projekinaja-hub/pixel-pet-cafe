import XCTest
@testable import PixelPetCafe

final class MahjongTests: XCTestCase {
    func t(_ suit: Int, _ rank: Int) -> Mahjong.Tile { .init(suit: suit, rank: rank) }

    func testWallHas136Tiles() {
        var rng = SeededGenerator(seed: 1)
        let wall = Mahjong.freshWall(rng: &rng)
        XCTAssertEqual(wall.count, 136)
        XCTAssertEqual(Set(wall).count, 34)
        XCTAssertEqual(wall.filter { $0 == t(3, 5) }.count, 4)   // four red dragons
    }

    func testWinDetection() {
        // 123m 456p 789s 111z EE  (4 melds + pair)
        let win = [t(0,1), t(0,2), t(0,3), t(1,4), t(1,5), t(1,6),
                   t(2,7), t(2,8), t(2,9), t(3,1), t(3,1), t(3,1), t(3,2), t(3,2)]
        XCTAssertTrue(Mahjong.isWinningHand(concealed: win, claimedMelds: 0))
        // same but one tile off
        var lose = win; lose[13] = t(3,3)
        XCTAssertFalse(Mahjong.isWinningHand(concealed: lose, claimedMelds: 0))
        // with 2 claimed melds: 2 melds + pair from 8 tiles
        let partial = [t(0,1), t(0,1), t(0,1), t(1,2), t(1,3), t(1,4), t(2,5), t(2,5)]
        XCTAssertTrue(Mahjong.isWinningHand(concealed: partial, claimedMelds: 2))
    }

    func testDealShapes() {
        var rng = SeededGenerator(seed: 7)
        let g = Mahjong.Game(rng: &rng)
        XCTAssertEqual(g.hands[0].count, 14)         // player drew first tile
        for seat in 1...3 { XCTAssertEqual(g.hands[seat].count, 13) }
        XCTAssertEqual(g.wall.count, 136 - 13 * 4 - 1)
        XCTAssertEqual(g.phase, .playerDiscard)
    }

    func testChowOptionsOnlyAdjacent() {
        var rng = SeededGenerator(seed: 7)
        var g = Mahjong.Game(rng: &rng)
        g.hands[0] = [t(0,2), t(0,3), t(0,5), t(0,6), t(3,1), t(3,1)]
        let opts = g.chowOptions(t(0,4))
        XCTAssertEqual(Set(opts.map(\.rank)), Set([2, 3, 4]))   // 234, 345, 456
        XCTAssertTrue(g.chowOptions(t(3,2)).isEmpty)            // honors can't run
    }

    func testGameAlwaysTerminates() {
        var rng = SeededGenerator(seed: 3)
        for seed in 0..<12 {
            var r = SeededGenerator(seed: UInt64(seed))
            var g = Mahjong.Game(rng: &r)
            var safety = 300
            loop: while safety > 0 {
                safety -= 1
                switch g.phase {
                case .playerDiscard:
                    if g.playerCanWinNow { g.playerDeclareWin(); break loop }
                    let tile = g.hands[0].last!
                    g.playerDiscard(tile, rng: &r)
                case .playerClaim:
                    g.playerPass(rng: &r)
                case .finished:
                    break loop
                }
            }
            guard case .finished = g.phase else {
                return XCTFail("game did not finish (seed \(seed))")
            }
        }
        _ = rng
    }

    func testPayouts() {
        XCTAssertEqual(Mahjong.payout(.playerWinSelfDraw, bet: 100), 300)
        XCTAssertEqual(Mahjong.payout(.playerWinDiscard, bet: 100), 250)
        XCTAssertEqual(Mahjong.payout(.aiWin(seat: 2), bet: 100), 0)
        XCTAssertEqual(Mahjong.payout(.wallExhausted, bet: 100), 100)
    }
}
