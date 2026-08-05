import XCTest
@testable import PixelPetCafe

/// The menu bar carried the buddy, a per-second coin count and the power meter
/// all at once — a lot of motion to park permanently in a menu bar you're
/// trying to work in. This makes it choosable.
final class MenuBarStyleTests: XCTestCase {

    // MARK: what each style shows

    func testTheRequestedStyleIsCharacterAndPowerWithoutCoins() {
        XCTAssertFalse(MenuBarStyle.meterOnly.showsCoins)
        XCTAssertTrue(MenuBarStyle.meterOnly.showsMeter)
    }

    func testFullShowsEverything() {
        XCTAssertTrue(MenuBarStyle.full.showsCoins)
        XCTAssertTrue(MenuBarStyle.full.showsMeter)
    }

    func testCharacterOnlyShowsNeither() {
        XCTAssertFalse(MenuBarStyle.characterOnly.showsCoins)
        XCTAssertFalse(MenuBarStyle.characterOnly.showsMeter)
    }

    /// Every style must keep the buddy: it is the only thing that identifies
    /// the app in the menu bar and the only way back into the game.
    func testEveryStyleIsOfferedInTheMenuAndIsDistinct() {
        XCTAssertEqual(Set(MenuBarStyle.menuOrder), Set(MenuBarStyle.allCases),
                       "a style exists that the menu never offers")
        XCTAssertEqual(MenuBarStyle.menuOrder.count, MenuBarStyle.allCases.count)
        let labels = MenuBarStyle.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "two styles share a label")
        XCTAssertFalse(labels.contains { $0.isEmpty })
    }

    // MARK: persistence

    func testDefaultIsTheHistoricLayout() {
        XCTAssertEqual(GameState.newGame().menuBarStyle, .full,
                       "an existing player's menu bar must not change on upgrade")
    }

    func testChoiceSurvivesEncodeDecode() throws {
        var s = GameState.newGame()
        s.menuBarStyle = .meterOnly
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back.menuBarStyle, .meterOnly)
    }

    /// A save written before this setting existed has no such key.
    func testOldSaveWithoutTheKeyDecodesToFull() throws {
        let json = #"{"coins": 100, "cafes": [{"city": "home"}]}"#
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(s.menuBarStyle, .full)
    }

    /// A save from a NEWER build naming a style this one doesn't know must
    /// still open, at the default, rather than refusing to decode and sending
    /// the player back to a brand-new café.
    func testUnknownStyleFallsBackInsteadOfThrowing() throws {
        let json = #"{"coins": 100, "menuBarStyle": "hologram", "cafes": [{"city": "home"}]}"#
        let s = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(s.menuBarStyle, .full)
    }

    func testStyleIsPartOfEquality() {
        var a = GameState.newGame()
        var b = a
        XCTAssertEqual(a, b)
        a.menuBarStyle = .meterOnly
        XCTAssertNotEqual(a, b, "the menu bar wouldn't refresh when the style changed")
        b.menuBarStyle = .meterOnly
        XCTAssertEqual(a, b)
    }
}
