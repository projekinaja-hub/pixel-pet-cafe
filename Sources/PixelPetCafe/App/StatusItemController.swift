import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Menu bar presence: animated pet icon + coin count, popover with the game,
/// right-click menu for settings.
@MainActor
final class StatusItemController: NSObject {
    private let controller: GameController
    private let scene: CafeScene
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var iconTimer: Timer?
    private var iconFrame = 0
    private var cancellable: AnyCancellable?
    private var icons: [NSImage] = []

    init(controller: GameController) {
        self.controller = controller
        self.scene = CafeScene()
        super.init()

        scene.onGoldenTip = { [weak controller] in controller?.collectGoldenTip() }
        scene.isPaused = true

        icons = (0..<4).map { i in
            let image = NSImage(byReferencing: Bundle.module.url(
                forResource: "baricon_\(i)", withExtension: "png", subdirectory: "Sprites")!)
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = icons[0]
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

        cancellable = controller.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateTitle(state) }
        updateTitle(controller.state)

        // slow icon animation: blink or sip every ~2s
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceIcon() }
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

    private func openPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        scene.configure(with: controller.state)
        scene.setActive(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func updateTitle(_ state: GameState) {
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " \(formatNumber(state.coins))",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
    }

    private func advanceIcon() {
        // mostly open eyes, sometimes blink, occasionally sip
        iconFrame += 1
        let frame: Int
        switch iconFrame % 8 {
        case 3: frame = 1          // blink
        case 7: frame = 3          // sip
        default: frame = 0
        }
        statusItem.button?.image = icons[frame]
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

    func popoverIsShown() -> Bool { popover.isShown }
}
