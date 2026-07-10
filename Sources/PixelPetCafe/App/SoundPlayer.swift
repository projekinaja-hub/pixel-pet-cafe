import AVFoundation

/// Plays the generated chiptune SFX. Rate-limited so busy cafés don't spam.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayed: [String: Date] = [:]
    // Ambient loop state — deliberately separate from the SFX `players`
    // cache so looping playback never collides with one-shot playback.
    private var ambientPlayer: AVAudioPlayer?
    private var ambientName: String?
    private var desiredAmbient: String?   // survives mute/close so it can resume
    var muted = false {
        didSet {
            guard muted != oldValue else { return }
            if muted { haltAmbient() } else { resumeAmbientIfWanted() }
        }
    }
    var enabled = true {   // only while the popover is open
        didSet {
            guard enabled != oldValue else { return }
            if enabled { resumeAmbientIfWanted() } else { haltAmbient() }
        }
    }

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

    // MARK: ambient loops

    /// Starts (or switches to) a seamless background loop. No-ops if the
    /// same loop is already playing, and while muted/disabled it only
    /// remembers the request so the loop resumes on unmute/reopen.
    func startAmbient(_ name: String) {
        desiredAmbient = name
        guard !muted, enabled else { return }
        if ambientName == name, ambientPlayer?.isPlaying == true { return }
        haltAmbient()
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0.16
        p.play()
        ambientPlayer = p
        ambientName = name
    }

    /// Stops the ambient loop and forgets the request entirely.
    func stopAmbient() {
        desiredAmbient = nil
        haltAmbient()
    }

    /// Stops playback but keeps `desiredAmbient` so mute/close is reversible.
    private func haltAmbient() {
        ambientPlayer?.stop()
        ambientPlayer = nil
        ambientName = nil
    }

    private func resumeAmbientIfWanted() {
        if let name = desiredAmbient { startAmbient(name) }
    }
}
