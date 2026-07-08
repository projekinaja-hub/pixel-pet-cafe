import Foundation

/// A pure RGB tint (0...255 per channel, matching tools/generate_sprites.py's
/// raw palette tuples so defaults line up exactly) — no SwiftUI/AppKit
/// dependency here so Core stays framework-free and testable; the UI and
/// Scene layers each add their own `Color`/`NSColor` conversion extensions.
struct StaffColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    /// Same darkening the generator's own equipment shading uses
    /// (`max(0, v - 40)`) — gives any chosen tint a consistent "shadow"
    /// shade for the fur_d layer, instead of needing a second hand-picked
    /// color per staff.
    var darkened: StaffColor {
        StaffColor(r: max(0, r - 40), g: max(0, g - 40), b: max(0, b - 40))
    }
}

struct StaffColorPair: Codable, Equatable {
    var body: StaffColor
    var clothes: StaffColor
}

/// Default fur/apron colors per staff id — mirrors tools/generate_sprites.py's
/// STAFF tuple exactly, so an uncustomized staff member renders pixel-identical
/// to the original flat art.
enum StaffPalette {
    static let defaults: [String: StaffColorPair] = [
        "mocha":   StaffColorPair(body: StaffColor(r: 150, g: 102, b: 66),  clothes: StaffColor(r: 206, g: 106, b: 76)),
        "biscuit": StaffColorPair(body: StaffColor(r: 222, g: 158, b: 90),  clothes: StaffColor(r: 96,  g: 129, b: 171)),
        "chip":    StaffColorPair(body: StaffColor(r: 196, g: 168, b: 132), clothes: StaffColor(r: 140, g: 190, b: 200)),
        "poppy":   StaffColorPair(body: StaffColor(r: 228, g: 214, b: 202), clothes: StaffColor(r: 233, g: 158, b: 160)),
        "juno":    StaffColorPair(body: StaffColor(r: 212, g: 110, b: 58),  clothes: StaffColor(r: 74,  g: 110, b: 88)),
        "bo":      StaffColorPair(body: StaffColor(r: 122, g: 88,  b: 62),  clothes: StaffColor(r: 150, g: 68,  b: 60)),
        "earl":    StaffColorPair(body: StaffColor(r: 138, g: 120, b: 150), clothes: StaffColor(r: 46,  g: 58,  b: 92)),
        "marble":  StaffColorPair(body: StaffColor(r: 172, g: 168, b: 178), clothes: StaffColor(r: 90,  g: 74,  b: 52)),
    ]

    static func pair(for id: String, in state: GameState) -> StaffColorPair {
        state.staffColors[id] ?? defaults[id] ?? StaffColorPair(body: StaffColor(r: 200, g: 200, b: 200),
                                                                  clothes: StaffColor(r: 150, g: 150, b: 150))
    }
}
