import Foundation

/// Compact idle-game formatting: 950, 1.2K, 56.8M, 3.2B, 7.5T.
func formatNumber(_ v: Double) -> String {
    let n = abs(v)
    let units: [(Double, String)] = [(1e18, "Qi"), (1e15, "Qa"), (1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
    for (scale, suffix) in units where n >= scale {
        let scaled = (v / scale * 10).rounded() / 10
        return scaled.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f%@", scaled, suffix)
            : String(format: "%.1f%@", scaled, suffix)
    }
    return String(format: "%.0f", v.rounded(.down))
}
