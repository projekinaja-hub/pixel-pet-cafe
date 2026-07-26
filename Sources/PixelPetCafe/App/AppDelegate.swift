import AppKit
import SpriteKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var game: GameController!
    private var statusController: StatusItemController!
    private var snapshotWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // dev hook: PPC_AXCHECK=1 prints whether macOS considers this binary
        // Accessibility-trusted (the thing global key counting hinges on).
        if ProcessInfo.processInfo.environment["PPC_AXCHECK"] == "1" {
            print("AXTRUSTED=\(AXIsProcessTrusted())")
            exit(0)
        }
        game = GameController(persistence: Persistence())
        game.start()
        statusController = StatusItemController(controller: game)

        // dev hook: PPC_KEYTEST=N watches the live typing pipeline from INSIDE
        // the app bundle for N seconds and prints what it sees each second.
        // This is the decisive test for "typing counts nothing": if the OS-wide
        // counter advances here while you type in any other app, detection
        // works — no permission, no monitors, nothing that can go stale.
        if let raw = ProcessInfo.processInfo.environment["PPC_KEYTEST"] {
            let seconds = max(1, Int(raw) ?? 10)
            let start = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
            print("KEYTEST start counter=\(start) workMode=\(game.state.workMode)")
            for i in 1...seconds {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [weak self] in
                    guard let g = self?.game else { exit(1) }
                    let now = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
                    print(String(format: "t=%02ds counter=%d (+%d) wpm=%.1f energy=%.0f lifetimeKeys=%.0f samples=%d",
                                 i, now, Int(now) - Int(start), g.wpm, g.state.energy,
                                 g.state.lifetimeKeystrokes, g.keySamplesTaken))
                    if i == seconds { exit(0) }
                }
            }
        }

        // dev hook: PPC_BARSHOT=/path.png renders the menu-bar energy capsule
        // at a range of typing speeds so the live crest can be eyeballed
        // without having to watch the real menu bar while typing.
        if let path = ProcessInfo.processInfo.environment["PPC_BARSHOT"] {
            let speeds: [Double] = [0, 0.15, 0.35, 0.6, 0.85, 1.0]
            let scale: CGFloat = 6, pad: CGFloat = 6
            let one = StatusItemController.energyBarImage(fraction: 0.49, typing: 0, phase: 0).size
            let out = NSImage(size: NSSize(width: (one.width * scale + pad) * CGFloat(speeds.count) + pad,
                                           height: one.height * scale + pad * 2))
            out.lockFocus()
            NSColor.black.setFill()
            NSRect(origin: .zero, size: out.size).fill()
            NSGraphicsContext.current?.imageInterpolation = .none
            for (i, t) in speeds.enumerated() {
                let img = StatusItemController.energyBarImage(fraction: 0.49, typing: t, phase: 3)
                img.draw(in: NSRect(x: pad + (one.width * scale + pad) * CGFloat(i), y: pad,
                                    width: one.width * scale, height: one.height * scale))
            }
            out.unlockFocus()
            if let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }

        // dev hook: PPC_SNAPSHOT=/path.png renders the panel offscreen and exits
        if let path = ProcessInfo.processInfo.environment["PPC_SNAPSHOT"] {
            runSnapshot(to: path)
        }
        // dev hook: PPC_SCENESHOT=/path.png renders the SpriteKit scene and exits
        if let path = ProcessInfo.processInfo.environment["PPC_SCENESHOT"] {
            runSceneShot(to: path)
        }
    }

    @MainActor
    private func runSceneShot(to path: String) {
        let scene = CafeScene()
        var demo = game.state
        demo.staffLevels = ["mocha": 3, "biscuit": 2, "poppy": 1, "juno": 1, "marble": 1]
        demo.equipmentLevels = ["espresso": 6, "grinder": 1, "oven": 1, "decor": 1, "sound": 1]
        demo.stars = 12
        demo.cleanliness = 55
        demo.owner.species = "fox"
        demo.owner.palette = "cream"
        demo.owner.accessory = "cap"
        if ProcessInfo.processInfo.environment["PPC_STAFF_COLOR"] == "1" {
            demo.staffColors["mocha"] = StaffColorPair(body: StaffColor(r: 40, g: 200, b: 210),
                                                         clothes: StaffColor(r: 230, g: 40, b: 190))
        }
        if ProcessInfo.processInfo.environment["PPC_STAFF_PAINT_DEMO"] == "1" {
            var art = PixelArt.blank()
            for y in 2..<18 {
                for x in 2..<14 { art.set(x: x, y: y, color: .packRGBA(r: 233, g: 158, b: 160)) }
            }
            for (x, y) in [(5, 8), (10, 8)] { art.set(x: x, y: y, color: .packRGBA(r: 52, g: 34, b: 41)) }
            for x in 5...10 { art.set(x: x, y: 13, color: .packRGBA(r: 52, g: 34, b: 41)) }
            demo.staffPaint["poppy"] = art
        }
        if let city = ProcessInfo.processInfo.environment["PPC_CITY"] {
            demo.cafe.city = city
        }
        // dev hook: PPC_SEASON=winter forces a season for seasonal-overlay screenshots
        if let seasonRaw = ProcessInfo.processInfo.environment["PPC_SEASON"],
           let season = Season(rawValue: seasonRaw) {
            demo.season = season
        }
        if ProcessInfo.processInfo.environment["PPC_MODE"] == "casino" {
            scene.setMode(.casino)
            if ProcessInfo.processInfo.environment["PPC_GAME"] == "map" {
                scene.setMode(.map)
            }
            switch ProcessInfo.processInfo.environment["PPC_GAME"] {
            case "mahjong":
                scene.setCasinoGame(.mahjong)
                scene.updateMahjongTable(discards: 9)
            case "roulette":
                scene.setCasinoGame(.roulette)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak scene] in
                    scene?.spinRouletteWheel(result: 17)
                }
            default: break
            }
        }
        scene.configure(with: demo)
        scene.setActive(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak scene] in
            if scene?.mode == .casino { scene?.playCasinoWin(500) }
            // dev hook: PPC_CELEBRATE=1 fires the confetti burst mid-fall for
            // sceneshot verification (snapshot lands ~2.9s after this).
            if ProcessInfo.processInfo.environment["PPC_CELEBRATE"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { scene?.playCelebration() }
            }
            scene?.playSale(SaleEvent(itemIcon: "latte", itemName: "Latte", price: 15,
                                      mood: .happy, customerSpecies: 0))
            scene?.playSale(SaleEvent(itemIcon: "", itemName: "", price: 0,
                                      mood: .angry, customerSpecies: 1))
        }
        let skView = SKView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        skView.presentScene(scene)
        let window = NSWindow(contentRect: skView.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = skView
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.orderBack(nil)
        snapshotWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard let tex = skView.texture(from: scene) else { exit(1) }
            let rep = NSBitmapImageRep(cgImage: tex.cgImage())
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    @MainActor
    private func runSnapshot(to path: String) {
        let scene = CafeScene()
        // dev hook: PPC_STAFF=1 hires a demo staff roster so panels that are
        // otherwise empty on a fresh save (Style's staff-colors section,
        // Staff tab) have something to screenshot.
        if ProcessInfo.processInfo.environment["PPC_STAFF"] == "1" {
            game.debugSeedStaff()
        }
        if ProcessInfo.processInfo.environment["PPC_STAFF_COLOR"] == "1" {
            game.debugTintMocha()
        }
        if ProcessInfo.processInfo.environment["PPC_STAFF_MAXED"] == "1" {
            game.debugMaxChip()
        }
        if ProcessInfo.processInfo.environment["PPC_STAFF_PAINT_DEMO"] == "1" {
            game.debugPaintPoppy()
        }
        scene.configure(with: game.state)
        scene.setActive(true)
        let host = NSHostingController(rootView: PanelView(controller: game, scene: scene))
        let window = NSWindow(contentViewController: host)
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderBack(nil)
        snapshotWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let id = CGWindowID(window.windowNumber)
            guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, []) else { exit(1) }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        game.saveNow()
    }
}
