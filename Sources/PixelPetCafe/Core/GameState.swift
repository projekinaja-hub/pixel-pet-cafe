import Foundation

/// Entire savable game state. Pure data — all rules live in `EconomyEngine`.
struct GameState: Codable, Equatable {
    var coins: Double = 0
    var lifetimeCoins: Double = 0
    var lifetimeCoinsThisRun: Double = 0
    var staffLevels: [String: Int] = [:]
    var equipmentLevels: [String: Int] = [:]
    var unlockedRecipes: [String] = []
    var stars: Int = 0
    var lastSaved: Date?
    var muted: Bool = false

    static func newGame() -> GameState {
        var s = GameState()
        s.staffLevels["mocha"] = 1
        return s
    }
}
