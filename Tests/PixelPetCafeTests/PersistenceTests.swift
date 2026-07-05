import XCTest
@testable import PixelPetCafe

final class PersistenceTests: XCTestCase {
    var dir: URL!
    var persistence: Persistence!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixelPetCafeTests-\(UUID().uuidString)")
        persistence = Persistence(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTrip() throws {
        var s = GameState.newGame()
        s.coins = 123.5
        s.staffLevels["poppy"] = 7
        s.stars = 3
        try persistence.save(s)
        var loaded = persistence.load()
        XCTAssertNotNil(loaded.lastSaved)          // save stamps timestamp
        loaded.lastSaved = nil
        s.lastSaved = nil
        XCTAssertEqual(loaded, s)
    }

    func testMissingFileGivesNewGame() {
        XCTAssertEqual(persistence.load(), GameState.newGame())
    }

    func testCorruptFileBacksUpAndGivesNewGame() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json{{{".utf8).write(to: dir.appendingPathComponent("save.json"))
        XCTAssertEqual(persistence.load(), GameState.newGame())
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("save.corrupt-") }
        XCTAssertEqual(backups.count, 1)
    }
}
