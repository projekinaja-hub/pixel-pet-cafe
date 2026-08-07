import Foundation

/// What the menu bar actually shows, beyond the character itself.
///
/// The bar had grown to three things at once — buddy, coin count, power meter
/// — which is a lot of noise to sit permanently in a menu bar you are trying
/// to work in. The coin number is the loudest part: it changes every second by
/// design, so it never settles.
///
/// The character is never optional. It IS the app: hiding it would leave a
/// nameless number in the menu bar with no way back to the game.
enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    /// Buddy, coins, power meter.
    case full
    /// Buddy and the power meter — no running coin count.
    case meterOnly
    /// Buddy and coins — no meter.
    case coinsOnly
    /// Just the buddy.
    case characterOnly

    var showsCoins: Bool {
        switch self {
        case .full, .coinsOnly: return true
        case .meterOnly, .characterOnly: return false
        }
    }

    /// The power meter also depends on Work Mode being on — there is no speed
    /// to show when nothing is being counted. This is only the preference.
    var showsMeter: Bool {
        switch self {
        case .full, .meterOnly: return true
        case .coinsOnly, .characterOnly: return false
        }
    }

    var label: String {
        switch self {
        case .full:          return "Character, Coins & Power"
        case .meterOnly:     return "Character & Power"
        case .coinsOnly:     return "Character & Coins"
        case .characterOnly: return "Character Only"
        }
    }

    /// Menu order, widest first, so the list reads as progressively quieter.
    static let menuOrder: [MenuBarStyle] = [.full, .meterOnly, .coinsOnly, .characterOnly]
}

/// How the menu-bar art is rendered.
///
/// Native menu-bar icons are *template* images: macOS discards their colour
/// and redraws them in whatever the menu bar currently needs — dark ink on a
/// light bar, light ink on a dark one, dimmed when the app isn't frontmost,
/// inverted while the menu is open. A full-colour pixel sprite does none of
/// that, which is exactly why it reads as pasted on top of the menu bar rather
/// than belonging to it.
enum MenuBarAppearance: String, Codable, CaseIterable, Sendable {
    /// The pixel art in full colour.
    case colorful
    /// Monochrome, following the menu bar the way system icons do.
    case subtle

    var isTemplate: Bool { self == .subtle }

    var label: String {
        switch self {
        case .colorful: return "Colourful"
        case .subtle:   return "Subtle (match menu bar)"
        }
    }

    static let menuOrder: [MenuBarAppearance] = [.colorful, .subtle]
}
