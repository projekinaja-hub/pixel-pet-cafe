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

    init(controller: GameController) {
        self.controller = controller
        self.scene = CafeScene()
        super.init()

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

        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
    private func loadIcon(_ name: String, pointSize: CGFloat = 18) -> NSImage? {
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
            let boost = controller.workBoost
            let level = boost < 1.05 ? 0 : (boost < 1.7 ? 1 : 2)
            let wanted: TimeInterval = [1.4, 0.8, 0.4][level]
            if wanted != iconInterval { restartIconTimer(interval: wanted) }
            if level == 0 {
                statusItem.button?.image = cupIcons[0][0]
            } else {
                statusItem.button?.image = cupIcons[level][iconTick % 2]
            }
            return
        }
        guard icons.count == 7 else { return }
        // Actively typing: the buddy visibly WORKS — a fast 2-frame
        // brewing cycle (cup + wiggling steam) instead of idling. This is
        // the face of the typing-energy loop in the menu bar.
        // Brew speed scales with real typing speed (WPM tiers), so the menu
        // bar visibly works harder the faster you type — at high speed the
        // buddy alternates brew frames rapidly with happy flashes.
        let wpm = controller.wpm
        if wpm >= 12, !SalesEngine.isClosed(controller.state), Date() >= happyUntil {
            let interval: TimeInterval = wpm >= 50 ? 0.18 : (wpm >= 30 ? 0.3 : 0.55)
            if iconInterval != interval { restartIconTimer(interval: interval) }
            // top tier: every 4th flip flashes the happy face — reads as
            // gleeful frantic brewing rather than a subtle 2-frame shuffle
            let frame = (wpm >= 50 && iconTick % 4 == 3) ? 2 : 5 + iconTick % 2
            statusItem.button?.image = icons[frame]
            return
        }
        if iconInterval != 2.0 { restartIconTimer(interval: 2.0) }
        let frame: Int
        if Date() < happyUntil {
            frame = 2                                  // happy bounce after a tip
        } else if SalesEngine.isClosed(controller.state) {
            frame = 3                                  // zzz while closed
        } else {
            switch iconTick % 8 {                      // idle: blink & sip
            case 3: frame = 1
            case 7: frame = 4
            default: frame = 0
            }
        }
        statusItem.button?.image = icons[frame]
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

    /// One icon, one number — the alert state is a color change on the coin
    /// itself rather than a second glyph, and the boost suffix only appears
    /// while a real boost is active instead of reserving space at rest.
    private func updateTitle(_ state: GameState) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let out = NSMutableAttributedString(string: " ", attributes: [.font: font])
        out.append(iconAttachment(SalesEngine.hasStockOut(state) ? "coin_alert" : "coin"))
        // fixed-width segment so the menu bar never jitters as digits change
        var num = formatNumber(state.coins)
        while num.count < 6 { num = "\u{2007}" + num }     // figure-space pad
        out.append(NSAttributedString(string: " \(num)", attributes: [.font: font]))
        if state.workMode, controller.workBoost > 1.1 {
            out.append(NSAttributedString(
                string: String(format: "  %.1f×", controller.workBoost),
                attributes: [.font: font, .foregroundColor: NSColor.systemYellow]))
        }
        statusItem.button?.attributedTitle = out
    }

    private func restartIconTimer(interval: TimeInterval) {
        iconInterval = interval
        iconTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
        if Date().timeIntervalSince(lastPopoverOpenAt) > 3 * 3600 {
            let host = NSHostingController(rootView: PanelView(controller: controller, scene: scene))
            host.preferredContentSize = NSSize(width: 360, height: 544)
            popover.contentViewController = host
        }
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
