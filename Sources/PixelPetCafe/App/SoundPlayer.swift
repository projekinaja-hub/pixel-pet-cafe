import AVFoundation

/// Plays the generated chiptune SFX. Rate-limited so busy cafés don't spam.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayed: [String: Date] = [:]
    var muted = false
    var enabled = true   // only while the popover is open

    func play(_ name: String, minGap: TimeInterval = 0.25) {
        guard !muted, enabled else { return }
        if let last = lastPlayed[name], Date().timeIntervalSince(last) < minGap { return }
        lastPlayed[name] = Date()
        if let p = players[name] {
            p.currentTime = 0
            p.play()
            return
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 0.5
        players[name] = p
        p.play()
    }
}
