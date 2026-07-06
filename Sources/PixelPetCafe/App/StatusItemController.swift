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

    init(controller: GameController) {
        self.controller = controller
        self.scene = CafeScene()
        super.init()

        scene.onGoldenTip = { [weak controller] in controller?.collectGoldenTip() }
        scene.onCleanSpot = { [weak controller] in controller?.cleanSpot() }
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
            }
            .store(in: &cancellables)
        controller.$workBoost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateTitle(self.controller.state)
            }
            .store(in: &cancellables)
        controller.saleEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.scene.playSale(event) }
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
        controller.casinoWin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in
                self?.scene.playCasinoWin(amount)
                self?.happyUntil = Date().addingTimeInterval(3)
                self?.refreshIcon()
            }
            .store(in: &cancellables)
        controller.tipCollected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.happyUntil = Date().addingTimeInterval(4)
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
        if state.barCharacter != "owner", Catalog.staffDef(state.barCharacter) != nil {
            return "barstaff_\(state.barCharacter)"
        }
        return "bar_\(state.owner.species)_\(state.owner.palette)"
    }

    private func reloadIconsIfNeeded(_ state: GameState) {
        let prefix = iconPrefix(state)
        guard prefix != iconCharacterKey else { return }
        iconCharacterKey = prefix
        icons = (0..<5).compactMap { f in
            guard let url = Bundle.module.url(forResource: "\(prefix)_\(f)",
                                              withExtension: "png", subdirectory: "Sprites"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        refreshIcon()
    }

    private func refreshIcon() {
        guard icons.count == 5 else { return }
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

    private func updateTitle(_ state: GameState) {
        let warning = SalesEngine.hasStockOut(state) ? "❗" : ""
        let boost = controller.workBoost > 1.05 ? String(format: " ⚡%.1f×", controller.workBoost) : ""
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " \(warning)\(formatNumber(state.coins))\(boost)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
    }

    // MARK: popover

    private func openPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        scene.configure(with: controller.state)
        scene.setActive(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
        scene.setActive(false)
    }

    private func showMenu() {
        let menu = NSMenu()
        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = controller.state.muted ? .on : .off
        menu.addItem(mute)

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
