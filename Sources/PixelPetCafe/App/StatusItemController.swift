import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Menu bar presence: reactive pet icon + coin count, popover with the game.
/// The icon reflects game state: alert when stock is out, sleeping while the
/// café is closed, a happy bounce on golden tips, blinks and coffee sips idle.
@MainActor
final class StatusItemController: NSObject {
    private let controller: GameController
    private let scene: CafeScene
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var iconTimer: Timer?
    private var iconTick = 0
    private var happyUntil = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var iconCharacterKey = ""
    private var icons: [NSImage] = []   // frames 0..4: normal, blink, happy, sleep, sip
    private var cupIcons: [[NSImage]] = []   // [steamLevel][wiggleFrame]
    private var iconInterval: TimeInterval = 2.0

    /// Draws a menu-bar frame nudged vertically, so the buddy physically
    /// bounces while you type instead of only swapping frames in place.
    /// Every frame goes through here (even at rest, dy = 0) so the icon never
    /// changes size when the bounce starts or stops.
    private func staged(_ image: NSImage, dy: CGFloat) -> NSImage {
        let size = image.size
        let inset: CGFloat = 2.4           // headroom so a bounce can't clip
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(x: inset / 2, y: inset / 2 + dy,
                              width: size.width - inset, height: size.height - inset),
                   from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    /// The bounce itself: taller and quicker the faster you type. Driven by
    /// wall-clock rather than the frame tick so it stays smooth no matter
    /// which animation tier is running.
    private func bounceOffset(wpm: Double) -> CGFloat {
        guard wpm >= 8 else { return 0 }
        let amp = 0.45 + min(1.05, wpm / 55)
        let hz = 1.3 + min(1.0, wpm / 60)
        let t = Date().timeIntervalSinceReferenceDate
        return CGFloat(sin(t * hz * 2 * .pi)) * amp
    }

    init(controller: GameController) {
        self.controller = controller
        self.scene = CafeScene()
        super.init()

        // Render heartbeat for RuntimeHealth: only a scene that is supposed to
        // be drawing can be "stalled", so an off-screen scene reports nil.
        let watched = scene
        controller.renderAgeProvider = { [weak watched] in
            guard let sc = watched, sc.isRenderExpected else { return nil }
            return Date().timeIntervalSince(sc.lastFrameAt)
        }
        scene.onGoldenTip = { [weak controller] in controller?.collectGoldenTip() }
        scene.onCleanSpot = { [weak controller] in controller?.cleanSpot() }
        scene.onMapSelect = { [weak controller] city in controller?.mapSelect(city) }
        scene.isPaused = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 544)
        let host = NSHostingController(rootView: PanelView(controller: controller, scene: scene))
        host.preferredContentSize = NSSize(width: 360, height: 544)
        popover.contentViewController = host

        controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.reloadIconsIfNeeded(state)
                self?.updateTitle(state)
                SoundPlayer.shared.muted = state.muted
            }
            .store(in: &cancellables)
        controller.$workBoost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshIcon()
                self.updateTitle(self.controller.state)
            }
            .store(in: &cancellables)
        // Live typing reaction: the menu-bar energy bar (and brewing face)
        // must redraw as typing SPEED changes — not only when coins or the
        // boost multiplier change. Without this the bar never reacts while
        // typing (and never at all when the tank is empty, since the boost
        // is pinned at crawl and stops changing). keystrokesPerSec republishes
        // every tick, so this drives a genuine per-second live reaction.
        controller.$keystrokesPerSec
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshIcon()
                self.updateTitle(self.controller.state)
            }
            .store(in: &cancellables)
        controller.saleEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.scene.playSale(event)
                if event.bigSpender {
                    SoundPlayer.shared.play("chaching", minGap: 1)
                    self?.happyUntil = Date().addingTimeInterval(2.5)
                    self?.refreshIcon()
                } else {
                    switch event.mood {
                    case .happy, .settled: SoundPlayer.shared.play("coin", minGap: 1.2)
                    case .sadLeave, .noTable: SoundPlayer.shared.play("sad", minGap: 2)
                    case .angry: SoundPlayer.shared.play("angry", minGap: 2)
                    }
                }
            }
            .store(in: &cancellables)
        controller.soundRequest
            .receive(on: DispatchQueue.main)
            .sink { name in SoundPlayer.shared.play(name) }
            .store(in: &cancellables)
        controller.casinoGameChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] game in self?.scene.setCasinoGame(game) }
            .store(in: &cancellables)
        controller.blackjackDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in self?.scene.showBlackjackCards(player: d.player, dealer: d.dealer, hole: d.hole) }
            .store(in: &cancellables)
        controller.rouletteResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.scene.spinRouletteWheel(result: n) }
            .store(in: &cancellables)
        controller.mahjongDiscards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in self?.scene.updateMahjongTable(discards: n) }
            .store(in: &cancellables)
        controller.casinoFocus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] zoom in self?.scene.focusTable(zoom) }
            .store(in: &cancellables)
        controller.mapOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in
                guard let self else { return }
                self.scene.setMode(open ? .map : .cafe)
                self.scene.configure(with: self.controller.state)
            }
            .store(in: &cancellables)
        controller.casinoWin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in
                self?.scene.playCasinoWin(amount)
                self?.happyUntil = Date().addingTimeInterval(3)
                self?.refreshIcon()
                SoundPlayer.shared.play("win")
            }
            .store(in: &cancellables)
        controller.casinoJackpotWon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in
                self?.scene.playCasinoWin(amount, jackpot: true)
                self?.happyUntil = Date().addingTimeInterval(5)
                self?.refreshIcon()
                SoundPlayer.shared.play("fanfare")
            }
            .store(in: &cancellables)
        controller.tipCollected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.happyUntil = Date().addingTimeInterval(4)
                self?.refreshIcon()
                SoundPlayer.shared.play("tip")
            }
            .store(in: &cancellables)
        controller.celebrate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.scene.playCelebration()
                self?.happyUntil = Date().addingTimeInterval(3)
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        reloadIconsIfNeeded(controller.state)
        updateTitle(controller.state)

        let t = Timer(timeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.iconTick += 1
                self?.refreshIcon()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        iconTimer = t

        // dev hook: PPC_OPEN=1 opens the popover on launch (for screenshots)
        if ProcessInfo.processInfo.environment["PPC_OPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openPopover()
            }
        }
    }

    // MARK: icon

    private func iconPrefix(_ state: GameState) -> String {
        if state.barCharacter == "coffee" { return "barcup" }
        if state.barCharacter != "owner", Catalog.staffDef(state.barCharacter) != nil {
            return "barstaff_\(state.barCharacter)"
        }
        return "bar_\(state.owner.species)_\(state.owner.palette)"
    }

    /// Loads a pixel-art PNG and bakes an extra nearest-neighbor 2x pixel
    /// representation alongside the original, so Retina displays render the
    /// crisp blocky pixels instead of smoothing them into a blurry mess —
    /// AppKit picks whichever representation matches the screen's backing
    /// scale automatically.
    /// Decoded sprites, keyed by name+size. Sprite PNGs ship inside the app
    /// bundle and cannot change while the app runs, so decoding one twice is
    /// always wasted work — and this was being decoded SIX TIMES A SECOND on
    /// an idle café.
    ///
    /// `loadIcon` reads a file off disk, runs a full PNG decode through
    /// ImageIO, then allocates a second bitmap and redraws it at 2x. A
    /// `sample` of the idle app (popover closed, nobody typing) caught the
    /// main thread inside exactly that ImageIO decode, reached from
    /// `updateTitle -> iconAttachment -> loadIcon`, because the menu-bar title
    /// is rebuilt on every emission of `@Published var state` — and a struct
    /// republishes on EVERY write, which the sim does many times per tick.
    ///
    /// The cache is bounded by the number of distinct sprites (a few dozen),
    /// so it never grows with uptime.
    private var iconCache: [String: NSImage] = [:]

    private func loadIcon(_ name: String, pointSize: CGFloat = 18) -> NSImage? {
        let cacheKey = "\(name)@\(pointSize)"
        if let hit = iconCache[cacheKey] { return hit }
        let image = decodeIcon(name, pointSize: pointSize)
        // Only successful decodes are cached: a transient read failure must
        // stay retryable rather than poisoning the icon for the whole session.
        if let image { iconCache[cacheKey] = image }
        return image
    }

    private func decodeIcon(_ name: String, pointSize: CGFloat) -> NSImage? {
        // This fires on every icon-refresh tick (menu bar buddy animation,
        // coin/alert swap...) for as long as the app is open — a transient
        // disk read hiccup here must never take the whole app down, so a
        // failed read just skips this one frame instead of crashing
        // (this was a `try!` that force-crashed the whole app on any read
        // failure; a long play session gave it enough ticks to eventually
        // hit one).
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites"),
              let data = try? Data(contentsOf: url),
              let rep1x = NSBitmapImageRep(data: data) else { return nil }
        rep1x.size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep1x)
        let w = rep1x.pixelsWide * 2, h = rep1x.pixelsHigh * 2
        if let rep2x = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep2x)
            NSGraphicsContext.current?.imageInterpolation = .none
            rep1x.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            NSGraphicsContext.restoreGraphicsState()
            rep2x.size = NSSize(width: pointSize, height: pointSize)
            image.addRepresentation(rep2x)
        }
        return image
    }

    private func reloadIconsIfNeeded(_ state: GameState) {
        let prefix = iconPrefix(state)
        guard prefix != iconCharacterKey else { return }
        iconCharacterKey = prefix
        if prefix == "barcup" {
            cupIcons = (0..<3).map { lvl in
                (0..<2).compactMap { f in loadIcon("barcup_\(lvl)_\(f)") }
            }
            icons = []
        } else {
            cupIcons = []
            icons = (0..<7).compactMap { f in loadIcon("\(prefix)_\(f)") }
        }
        refreshIcon()
    }

    private func refreshIcon() {
        // ☕ mode: steam level & wiggle speed follow the typing boost
        if !cupIcons.isEmpty {
            // Steam follows typing SPEED, not workBoost — workBoost is pinned
            // at the crawl value whenever the tank is empty, so the cup could
            // never steam exactly when you were typing hardest to refill it.
            let wpm = controller.wpm
            let level = wpm < 12 ? 0 : (wpm < 40 ? 1 : 2)
            let wanted: TimeInterval = [1.4, 0.5, 0.22][level]
            if wanted != iconInterval { restartIconTimer(interval: wanted) }
            let frame = level == 0 ? cupIcons[0][0] : cupIcons[level][iconTick % 2]
            statusItem.button?.image = staged(frame, dy: bounceOffset(wpm: wpm))
            return
        }
        guard icons.count == 7 else { return }
        // Actively typing: the buddy visibly WORKS — a fast 2-frame
        // brewing cycle (cup + wiggling steam) instead of idling. This is
        // the face of the typing-energy loop in the menu bar.
        // Brew speed scales with real typing speed (WPM tiers), so the menu
        // bar visibly works harder the faster you type — at high speed the
        // buddy alternates brew frames rapidly with happy flashes.
        // Brewing starts the moment you type — a recency check, not a WPM
        // threshold. Speed still sets HOW FAST the buddy brews.
        let wpm = controller.wpm
        if controller.isActivelyTyping, !SalesEngine.isClosed(controller.state), Date() >= happyUntil {
            let interval: TimeInterval = wpm >= 45 ? 0.16 : (wpm >= 25 ? 0.28 : 0.5)
            if iconInterval != interval { restartIconTimer(interval: interval) }
            // Brew, brew, and every so often a burst of personality: a grin
            // when you're flying, a quick sip when you're cruising, the odd
            // blink — so it reads as a working little character rather than
            // a two-frame shuffle.
            var frame = 5 + iconTick % 2
            if wpm >= 45, iconTick % 4 == 3 {
                frame = 2                                  // gleeful grin
            } else if wpm >= 30, iconTick % 9 == 8 {
                frame = 4                                  // quick sip
            } else if iconTick % 13 == 12 {
                frame = 1                                  // blink
            }
            statusItem.button?.image = staged(icons[frame], dy: bounceOffset(wpm: wpm))
            return
        }
        // C: the face reacts to what's happening, not just idle-loops.
        // An exciting event (rush / lucky hour) → gleeful; an empty energy
        // tank (café crawling) → drowsy; otherwise the classic idle life.
        let excited = Events.isActive("rush", controller.state)
            || Events.isActive("lucky_hour", controller.state)
        let drowsy = controller.state.workMode && controller.state.energy <= 0
        let interval: TimeInterval = excited ? 0.6 : 2.0
        if iconInterval != interval { restartIconTimer(interval: interval) }
        let frame: Int
        if Date() < happyUntil {
            frame = 2                                  // happy bounce after a tip
        } else if SalesEngine.isClosed(controller.state) {
            frame = 3                                  // zzz while closed
        } else if excited {
            frame = iconTick % 2 == 0 ? 2 : 0          // bounce between happy & alert
        } else if drowsy {
            frame = iconTick % 6 == 0 ? 1 : 3          // sleepy: mostly zzz, slow blinks
        } else {
            switch iconTick % 8 {                      // idle: blink & sip
            case 3: frame = 1
            case 7: frame = 4
            default: frame = 0
            }
        }
        // an excited buddy bounces too — same motion the typing loop uses
        statusItem.button?.image = staged(icons[frame], dy: excited ? bounceOffset(wpm: 45) : 0)
    }

    /// Small pixel icon (Sprites/icon_<name>.png) as an inline attachment,
    /// baseline-nudged to sit level with the menu bar text — no emoji.
    private func iconAttachment(_ name: String, size: CGFloat = 12) -> NSAttributedString {
        guard let image = loadIcon("icon_\(name)", pointSize: size) else { return NSAttributedString() }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2.5, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    /// A minimalist energy meter drawn as an NSImage: a soft rounded track
    /// with a rounded fill, no emoji, no block characters. Colour is the only
    /// state signal — muted gold when fuelled, amber when low, a restrained
    /// red when empty (the café is crawling). Sized and baseline-nudged to
    /// sit cleanly inline with the coin count.
    private func energyBarAttachment(fuel: Double, speed: Double) -> NSAttributedString {
        let img = Self.energyBarImage(fuel: fuel, speed: speed)
        let attachment = NSTextAttachment()
        attachment.image = img
        attachment.bounds = CGRect(x: 0, y: -1.5, width: img.size.width, height: img.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// Typing speed that fills the bar completely. Deliberately above normal
    /// prose speed: at the old ceiling any ordinary typing pinned the bar at
    /// 100% and it stopped saying anything at all.
    static let speedFullAtWPM = 100.0

    /// The capsule: LENGTH is how fast you're typing right now, COLOUR is how
    /// much fuel is left. One length, one meaning — the previous version drew
    /// the tank as the length AND the speed as an overlay, which is why it
    /// read as ambiguous and looked washed out.
    /// Static so a dev hook (PPC_BARSHOT / PPC_BARFILM) can render the exact
    /// production drawing offscreen for eyeball verification.
    static func energyBarImage(fuel: Double, speed: Double) -> NSImage {
        let w: CGFloat = 24, h: CGFloat = 11, barH: CGFloat = 5
        let y = (h - barH) / 2
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        let track = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: w, height: barH),
                                 xRadius: barH / 2, yRadius: barH / 2)
        NSColor.tertiaryLabelColor.setFill()
        track.fill()

        // Plain rects clipped to the capsule, so everything shares one clean
        // rounded silhouette instead of stacking rounded shapes.
        NSGraphicsContext.saveGraphicsState()
        track.addClip()

        let s = max(0, min(1, speed))
        // COLOUR = fuel: gold while fuelled, amber when low, red when the tank
        // is dry and the café is crawling.
        let base: NSColor = fuel <= 0.001
            ? .systemRed
            : (fuel < 0.25 ? .systemOrange : .systemYellow)
        // A resting pip keeps the fuel colour readable at 0 WPM — an entirely
        // empty capsule would hide the one thing you need at a glance.
        let fillW = max(barH, w * CGFloat(s))
        base.withAlphaComponent(0.45 + 0.55 * CGFloat(s)).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: y, width: fillW, height: barH)).fill()

        // A brighter cap at the tip so the bar reads as a moving wavefront
        // rather than a block that happens to change length.
        if s > 0.04, let hot = base.blended(withFraction: 0.5, of: .white) {
            hot.setFill()
            NSBezierPath(rect: NSRect(x: max(0, fillW - 3), y: y, width: 3, height: barH)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// One icon, one number — the alert state is a color change on the coin
    /// itself rather than a second glyph, and the boost suffix only appears
    /// while a real boost is active instead of reserving space at rest.
    /// Signature of everything the drawn title actually depends on, so an
    /// emission that changes nothing visible costs nothing.
    ///
    /// `GameController.state` is an `@Published` struct, so it republishes on
    /// every single write — measured at 6/sec on an idle, empty café, against
    /// a sim that only ticks once a second. Five of those six rebuilt a title
    /// identical to the one already on screen. Fuel and speed are quantised to
    /// the 24pt capsule's half-pixel because anything finer cannot be seen.
    private var lastTitleKey: String?

    private func updateTitle(_ state: GameState) {
        let style = state.menuBarStyle
        let alert = SalesEngine.hasStockOut(state)
        // fixed-width segment so the menu bar never jitters as digits change
        var num = formatNumber(state.coins)
        while num.count < 6 { num = "\u{2007}" + num }     // figure-space pad
        let fuel = max(0, min(1, state.energy / EnergyEngine.energyCap))
        let speed = max(0, min(1, controller.wpm / Self.speedFullAtWPM))
        // Hidden parts are left OUT of the key, not merely drawn as empty: with
        // coins hidden, a coin count ticking every second must not keep
        // invalidating a title whose visible content never changes.
        let coinKey = style.showsCoins ? "\(alert)|\(num)" : "-"
        let meterKey = (style.showsMeter && state.workMode)
            ? "\((fuel * 48).rounded())|\((speed * 48).rounded())" : "-"
        let key = "\(style.rawValue)|\(coinKey)|\(meterKey)"
        guard key != lastTitleKey else { return }
        lastTitleKey = key

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let out = NSMutableAttributedString(string: " ", attributes: [.font: font])
        if style.showsCoins {
            out.append(iconAttachment(alert ? "coin_alert" : "coin"))
            out.append(NSAttributedString(string: " \(num)", attributes: [.font: font]))
        }
        // A: live energy glance — a minimalist capsule bar drawn as a real
        // image (like the coin icon), not emoji + block glyphs. Reads as a
        // product, not a debug line: a soft translucent track that fills with
        // a single tasteful colour shifting by fuel level.
        if state.workMode, style.showsMeter {
            // No leading gap when the meter is the only thing here, or it sits
            // adrift from the buddy.
            if style.showsCoins {
                out.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            out.append(energyBarAttachment(fuel: fuel, speed: speed))
        }
        statusItem.button?.attributedTitle = out
    }

    private func restartIconTimer(interval: TimeInterval) {
        iconInterval = interval
        iconTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.iconTick += 1
                self?.refreshIcon()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        iconTimer = t
    }

    // MARK: popover

    private var lastPopoverOpenAt = Date()

    private func openPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        // Self-healing: after hours unopened, the NSHostingView/SpriteView
        // stack can go stale and open frozen (observed after ~19h uptime).
        // Rebuilding the popover content from scratch before showing is
        // cheap insurance — same controller, same scene, fresh view stack.
        // Revive the sim/icon timers if they died during long idle (they
        // can stop firing on RunLoop.main). This click path always runs,
        // independent of our timers, so it's a reliable recovery point.
        controller.ensureRunning()
        if iconTimer == nil || iconTimer?.isValid != true { restartIconTimer(interval: iconInterval) }
        controller.bumpViewReload()   // restart the scene's render loop every open
        // NOTE: previously rebuilt the popover's NSHostingController/SpriteView
        // here every 15 min "to self-heal" — but a freshly created SpriteView
        // frequently presents a frozen first frame, so that self-heal became
        // the *cause* of frequent stuck-on-open. Removed: the existing view
        // stack is reused and simply unpaused (setActive), which is the
        // known-good common-case path.
        lastPopoverOpenAt = Date()
        scene.configure(with: controller.state)
        scene.setActive(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        SoundPlayer.shared.enabled = true
        NotificationManager.shared.suppressed = true      // user is looking at the game
        controller.refreshStreakOnInteraction()           // opening the panel counts as playing today
    }

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        popoverWentAway()
    }

    /// Runs on EVERY close, however it happens. The popover is `.transient`,
    /// so clicking anywhere else on screen dismisses it WITHOUT going through
    /// closePopover() — that path used to skip this cleanup entirely, leaving
    /// the ambient music looping, the scene animating, and notifications
    /// suppressed while the game looked closed. NSPopoverDelegate's
    /// popoverDidClose (wired in init) now funnels both paths here;
    /// idempotent, so the explicit-close path calling it twice is harmless.
    private func popoverWentAway() {
        scene.setActive(false)
        SoundPlayer.shared.enabled = false
        NotificationManager.shared.suppressed = false
    }

    @objc private func pickMenuBarStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = MenuBarStyle(rawValue: raw) else { return }
        controller.setMenuBarStyle(style)
        // The key guards against redundant redraws, so it must be cleared or
        // the bar keeps the layout the user just switched away from.
        lastTitleKey = nil
        updateTitle(controller.state)
        refreshIcon()
    }

    private func showMenu() {
        let menu = NSMenu()
        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = controller.state.muted ? .on : .off
        menu.addItem(mute)

        let work = NSMenuItem(title: "Work Mode ⚡ (typing boost)", action: #selector(toggleWork), keyEquivalent: "")
        work.target = self
        work.state = controller.state.workMode ? .on : .off
        menu.addItem(work)

        let barItem = NSMenuItem(title: "Menu Bar Shows", action: nil, keyEquivalent: "")
        let barMenu = NSMenu()
        for style in MenuBarStyle.menuOrder {
            let item = NSMenuItem(title: style.label, action: #selector(pickMenuBarStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = controller.state.menuBarStyle == style ? .on : .off
            barMenu.addItem(item)
        }
        barItem.submenu = barMenu
        menu.addItem(barItem)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pixel Pet Café",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // keep left-click on the popover
    }

    @objc private func toggleMute() { controller.toggleMuted() }

    @objc private func toggleWork() { controller.toggleWorkMode() }

    @objc private func toggleLogin() {
        // Only effective when running from the .app bundle (tools/make_app.sh).
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login unavailable: \(error.localizedDescription)")
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    /// Catches EVERY dismissal — including the .transient auto-close when
    /// the user clicks anywhere else on screen, which never goes through
    /// closePopover(). Without this, ambient music kept playing and the
    /// scene kept animating with the game visually closed.
    func popoverDidClose(_ notification: Notification) {
        popoverWentAway()
    }
}
