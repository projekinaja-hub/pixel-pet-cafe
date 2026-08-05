import XCTest
import SpriteKit
@testable import PixelPetCafe

/// The frozen picture, finally explained.
///
/// `PanelView` calls `scene.configure(with:)` from `.onChange(of:
/// controller.state)`, which fires whenever coins tick — and the popover's
/// hosting controller lives for the whole session, so it kept firing with the
/// café closed and the scene paused. `applyTimeOfDay` restarted its tint
/// animation on every one of those calls, because the `lastTimePhase` guard
/// was assigned but never compared.
///
/// A paused SKScene doesn't advance actions, so none of them ever completed or
/// were released. Measured on a real 45-hour session: 238,000 each of
/// SKColorize, SKFade and SKGroup — ~152 MB of actions, a 228 MB process with
/// 200 MB swapped out. Drawing a frame meant paging that back off disk.
@MainActor
final class SceneActionLeakTests: XCTestCase {

    private func busyState() -> GameState {
        GameState.newGame().normalized()
    }

    /// The regression itself: the café closed, coins ticking, the scene paused.
    func testRepeatedConfigureDoesNotRestartTheTintOnAPausedScene() {
        let scene = CafeScene()
        scene.setActive(false)              // popover closed — actions frozen
        var state = busyState()

        scene.configure(with: state)
        let afterFirst = scene.timeTintRestarts

        // 500 coin ticks, which is what a few minutes of play emits
        for _ in 0..<500 {
            state.coins += 1
            scene.configure(with: state)
        }

        XCTAssertEqual(scene.timeTintRestarts, afterFirst,
                       "the tint restarted \(scene.timeTintRestarts - afterFirst) extra times; "
                       + "on a paused scene every restart is an SKAction that can never complete")
    }

    /// Same thing with the café open — the scene is live, but the tint still
    /// has no business restarting when the hour hasn't changed.
    func testRepeatedConfigureDoesNotRestartTheTintOnALiveScene() {
        let scene = CafeScene()
        scene.setActive(true)
        var state = busyState()

        scene.configure(with: state)
        let afterFirst = scene.timeTintRestarts
        for _ in 0..<200 {
            state.coins += 1
            scene.configure(with: state)
        }
        XCTAssertEqual(scene.timeTintRestarts, afterFirst)
    }

    /// The tint must still be applied once, or the guard would have "fixed"
    /// the leak by disabling the feature.
    func testTheTintIsStillAppliedOnTheFirstConfigure() {
        let scene = CafeScene()
        scene.setActive(false)
        scene.configure(with: busyState())
        XCTAssertEqual(scene.timeTintRestarts, 1,
                       "the time-of-day tint must run once on the first configure")
    }

    /// Every tint animation must be KEYED. SpriteKit replaces a keyed action
    /// with the same key rather than adding a second one, so keying is what
    /// structurally caps a node at one tint action no matter who calls in.
    /// The guard above is the fix; this is what stops it recurring.
    func testEveryTintAnimationIsKeyed() {
        let scene = CafeScene()
        scene.setActive(false)
        var state = busyState()
        state.season = .winter          // force the seasonal tint to run too
        for _ in 0..<300 {
            state.coins += 1
            scene.configure(with: state)
        }
        for (node, key) in scene.tintNodesForTesting {
            XCTAssertNotNil(node.action(forKey: key),
                            "\(key) is not keyed — repeated runs would stack on this node")
        }
    }
}
