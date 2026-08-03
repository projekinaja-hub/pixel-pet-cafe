import XCTest
@testable import PixelPetCafe

/// `offlineSim` runs SYNCHRONOUSLY ON THE MAIN THREAD from two paths the
/// player triggers directly: app launch (`GameController.init`) and the
/// menu-bar click after being away (`ensureRunning`). Every millisecond it
/// spends is a millisecond the whole app is frozen — so its cost is a
/// user-facing property, not an implementation detail.
final class OfflineSimPerfTests: XCTestCase {

    /// A wealthy café with a manager: the manager keeps refilling stock from a
    /// deep wallet, so the serve loop never runs dry and runs to its safety cap.
    private func richState(cafes: Int) -> GameState {
        var s = GameState.newGame().normalized()
        s.coins = 1e15
        s.lifetimeCoins = 1e15
        s.storageLevel = 8
        s.staffLevels["marble"] = 5
        s.staffLevels["mocha"] = 5
        s.menuEnabled = MenuCatalog.items.map(\.id)
        let cap = EconomyEngine.storageCap(s)
        for ing in MenuCatalog.ingredients { s.stock[ing.id] = cap }
        let one = s.cafes[0]
        while s.cafes.count < cafes { s.cafes.append(one) }
        return s
    }

    private func time(_ label: String, _ body: () -> Void) -> Double {
        let t0 = Date()
        body()
        let ms = Date().timeIntervalSince(t0) * 1000
        print("PERF \(label): \(String(format: "%.1f", ms)) ms")
        return ms
    }

    func testOfflineSimCostForOneCafe() {
        var s = richState(cafes: 1)
        let ms = time("offlineSim 8h, 1 cafe") {
            _ = SalesEngine.offlineSim(&s, elapsed: 8 * 3600)
        }
        XCTAssertLessThan(ms, 250, "one café's away-sim must not freeze the UI")
    }

    func testOfflineSimCostForAFullCityChain() {
        var s = richState(cafes: 10)
        let ms = time("offlineSim 8h, 10 cafes") {
            _ = SalesEngine.offlineSim(&s, elapsed: 8 * 3600)
        }
        XCTAssertLessThan(ms, 500, "a 10-city chain's away-sim must not freeze the UI")
    }

    /// The real shape of the complaint: away overnight, then click the icon.
    func testOfflineSimCostAfterAWholeNight() {
        var s = richState(cafes: 10)
        let ms = time("offlineSim 12h, 10 cafes") {
            _ = SalesEngine.offlineSim(&s, elapsed: 12 * 3600)
        }
        XCTAssertLessThan(ms, 500, "clicking the icon after a night away must stay responsive")
    }
}
