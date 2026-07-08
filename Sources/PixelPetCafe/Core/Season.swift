import Foundation

/// Shared contract between the calendar/economy system and the seasonal
/// visual overlays: whatever computes the current season, everything else
/// just reads `GameState.season`. Kept deliberately tiny and stable so the
/// two can be built independently.
enum Season: String, Codable, CaseIterable, Equatable {
    case spring, summer, autumn, winter
}
