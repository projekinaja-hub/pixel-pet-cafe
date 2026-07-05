import Foundation

/// Atomic JSON save/load. Corrupt saves are moved aside, never destroyed.
struct Persistence {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PixelPetCafe")
    }

    private var saveURL: URL { directory.appendingPathComponent("save.json") }

    func load() -> GameState {
        guard let data = try? Data(contentsOf: saveURL) else { return .newGame() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let state = try? decoder.decode(GameState.self, from: data) {
            return state
        }
        // corrupt: back it up aside and start fresh
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(
            at: saveURL,
            to: directory.appendingPathComponent("save.corrupt-\(stamp).json"))
        return .newGame()
    }

    func save(_ state: GameState) throws {
        var stamped = state
        stamped.lastSaved = Date()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stamped).write(to: saveURL, options: .atomic)
    }
}
