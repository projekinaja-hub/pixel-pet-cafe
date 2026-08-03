import XCTest
@testable import PixelPetCafe

/// The café animation used to run at one fixed pace regardless of business:
/// ~11.9s per visit, 4 customers maximum, so it could depict at most ~0.34
/// sales/sec and silently dropped everything above that. A café earning
/// millions looked identical to one earning pennies. These pin the curve that
/// ties the picture back to the actual sales rate.
final class CafePacingTests: XCTestCase {

    // MARK: a quiet café is left alone

    func testAnIdleCafeKeepsTheOriginalLeisurelyPace() {
        XCTAssertEqual(CafePacing.speed(salesPerSec: 0), 1.0)
        XCTAssertEqual(CafePacing.onScreenCap(salesPerSec: 0), CafePacing.baseOnScreen)
    }

    /// A fresh café sells about 0.05/sec. Nothing about that should look rushed.
    func testAFreshCafeIsNotSpedUp() {
        XCTAssertEqual(CafePacing.speed(salesPerSec: 0.05), 1.0, accuracy: 0.001)
        XCTAssertEqual(CafePacing.onScreenCap(salesPerSec: 0.05), 4)
    }

    // MARK: busier cafés look busier

    /// The ordering of the two dials, pinned: a modestly busy café puts MORE
    /// PEOPLE in the room while everyone still walks at a normal pace. Sizing
    /// the room as though everyone were already sprinting had it backwards —
    /// a 0.6/sec café hit nearly double speed with only four customers in it.
    func testMoreCustomersArriveBeforeAnyoneStartsHurrying() {
        let modest = 0.6
        XCTAssertGreaterThan(CafePacing.onScreenCap(salesPerSec: modest), CafePacing.baseOnScreen)
        XCTAssertEqual(CafePacing.speed(salesPerSec: modest), 1.0, accuracy: 0.001,
                       "nobody should be hurrying while there is still room to fill")
    }

    /// Only once the room is full does anyone speed up.
    func testHurryingOnlyStartsWhenTheRoomIsFull() {
        let flatOut = 3.0
        XCTAssertEqual(CafePacing.onScreenCap(salesPerSec: flatOut), CafePacing.maxOnScreen)
        XCTAssertGreaterThan(CafePacing.speed(salesPerSec: flatOut), 1.0)
    }

    func testABusyCafeSpeedsUpAndFillsTheRoom() {
        let busy = 2.0
        XCTAssertGreaterThan(CafePacing.speed(salesPerSec: busy), 1.5)
        XCTAssertGreaterThan(CafePacing.onScreenCap(salesPerSec: busy), 4)
    }

    func testPaceRisesWithSales() {
        let rates = [0.1, 0.5, 1.0, 2.0, 4.0]
        let shown = rates.map { CafePacing.shownPerSec(salesPerSec: $0) }
        for (a, b) in zip(shown, shown.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b + 0.0001, "throughput must never fall as sales rise")
        }
    }

    // MARK: the picture stays believable at the top end

    func testNobodyEverSprints() {
        for rate in [10.0, 100.0, 10_000.0] {
            XCTAssertLessThanOrEqual(CafePacing.speed(salesPerSec: rate), CafePacing.maxSpeed)
            XCTAssertLessThanOrEqual(CafePacing.onScreenCap(salesPerSec: rate), CafePacing.maxOnScreen)
        }
    }

    /// An absurd rate must not produce absurd numbers — no NaN, no negatives,
    /// no thousand-strong mob.
    func testExtremeRatesStayFinite() {
        for rate in [-5.0, 0.0, .infinity, 1e12] {
            let speed = CafePacing.speed(salesPerSec: rate)
            let cap = CafePacing.onScreenCap(salesPerSec: rate)
            XCTAssertTrue(speed.isFinite, "speed went non-finite at \(rate)")
            XCTAssertGreaterThanOrEqual(speed, 1)
            XCTAssertLessThanOrEqual(speed, CafePacing.maxSpeed)
            XCTAssertGreaterThanOrEqual(cap, CafePacing.baseOnScreen)
            XCTAssertLessThanOrEqual(cap, CafePacing.maxOnScreen)
        }
    }

    // MARK: legs match the ground they cover

    func testLegsSwingFasterWhenWalkingFaster() {
        let resting = CafePacing.legFrame(speed: 1)
        let hurrying = CafePacing.legFrame(speed: 3)
        XCTAssertLessThan(hurrying, resting, "a faster walk must have a faster leg cycle")
    }

    /// The original 0.45s/frame was 2.2fps — about five leg swaps for the whole
    /// walk across the room, which read as gliding.
    func testRestingCadenceIsAWalkNotAGlide() {
        let fps = 1 / CafePacing.legFrame(speed: 1)
        XCTAssertGreaterThan(fps, 4, "resting leg cycle is \(fps)fps — still a glide")
    }

    func testLegCadenceNeverBecomesABlur() {
        XCTAssertGreaterThanOrEqual(CafePacing.legFrame(speed: 1000), 0.05)
    }

    // MARK: the queue fits in the room

    func testTheLineNeverQueuesOutThroughTheWall() {
        // Counter sits at x=104 and the door at x=14, so the line has ~90pt.
        for i in 0..<50 {
            XCTAssertGreaterThan(104 + CafePacing.queueOffset(i), 0,
                                 "queue position \(i) is off the left edge of the room")
        }
    }

    func testTheLineFormsBackwardFromTheCounter() {
        XCTAssertEqual(CafePacing.queueOffset(0), 0, "the front of the line is at the counter")
        XCTAssertLessThan(CafePacing.queueOffset(1), CafePacing.queueOffset(0))
    }

    // MARK: honesty about the ceiling

    /// Past the top of the curve the café genuinely sells more than the room
    /// can show. That's a real limit and it should be a known one.
    func testThroughputCeilingIsWhatWeThinkItIs() {
        let ceiling = CafePacing.shownPerSec(salesPerSec: 1e6)
        XCTAssertEqual(ceiling,
                       Double(CafePacing.maxOnScreen) * CafePacing.maxSpeed / CafePacing.baseVisitDuration,
                       accuracy: 0.001)
        // ~3.4/sec, an order of magnitude better than the old fixed 0.34.
        XCTAssertGreaterThan(ceiling, 3.0)
    }
}
