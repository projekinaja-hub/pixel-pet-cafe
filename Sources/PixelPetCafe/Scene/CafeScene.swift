import SpriteKit

/// The animated pixel café. Logical size 180×120, presented .aspectFit into a
/// 360×240 SpriteView. Customers walk in via events from the GameController.
enum SceneMode { case cafe, casino, map }
enum CasinoGame { case slots, blackjack, roulette, mahjong }

final class CafeScene: SKScene {
    var onGoldenTip: (() -> Void)?
    var onCleanSpot: (() -> Void)?
    var onMapSelect: ((String) -> Void)?

    private(set) var mode: SceneMode = .cafe
    private let cafeLayer = SKNode()
    private let casinoLayer = SKNode()
    private let mapLayer = SKNode()
    private let gameFocus = SKNode()
    private var casinoBuilt = false
    private var casinoGame: CasinoGame = .slots
    private var wheelNode: SKSpriteNode?
    private var dealerNode: SKSpriteNode?
    private var background = SKSpriteNode()
    private var staffNodes: [String: SKSpriteNode] = [:]
    private var ownerNode: SKSpriteNode?
    private var equipNodes: [String: SKSpriteNode] = [:]
    private var dirtNodes: [SKSpriteNode] = []
    private var closedOverlay: SKNode?
    private var tipNode: SKSpriteNode?
    private var nextTipAt: Date = .distantFuture
    private var activeCustomers = 0

    private var currentBGTier = -1
    private var configuredStaff: Set<String> = []
    private var configuredEquipTiers: [String: Int] = [:]
    private var configuredOwnerKey = ""
    private var configuredDirt = -1
    private var configuredClosed = false

    private static let doorPoint = CGPoint(x: 14, y: 32)
    private static let counterPoint = CGPoint(x: 104, y: 42)
    private static let seatPoints = [CGPoint(x: 44, y: 34), CGPoint(x: 74, y: 34), CGPoint(x: 96, y: 22)]
    private static let dirtSpots: [CGPoint] = [
        CGPoint(x: 52, y: 12), CGPoint(x: 92, y: 8), CGPoint(x: 34, y: 26),
        CGPoint(x: 120, y: 16), CGPoint(x: 70, y: 40),
    ]

    private static let staffSpots: [String: CGPoint] = [
        "mocha": CGPoint(x: 132, y: 58),
        "juno":  CGPoint(x: 148, y: 58),
        "bo":    CGPoint(x: 162, y: 58),
        "earl":  CGPoint(x: 118, y: 58),
        "poppy": CGPoint(x: 88, y: 46),
        "biscuit": CGPoint(x: 62, y: 24),
    ]
    private static let equipSpots: [String: (CGPoint, CGFloat)] = [
        "espresso": (CGPoint(x: 104, y: 68), 9),
        "grinder":  (CGPoint(x: 118, y: 68), 9),
        "oven":     (CGPoint(x: 80, y: 52), 2),
        "decor":    (CGPoint(x: 30, y: 6), 6),
        "sound":    (CGPoint(x: 170, y: 82), 2),
    ]

    override init() {
        super.init(size: CGSize(width: 180, height: 120))
        scaleMode = .aspectFit
        backgroundColor = NSColor(calibratedRed: 0.22, green: 0.19, blue: 0.20, alpha: 1)
        background.anchorPoint = .zero
        background.position = .zero
        background.zPosition = 0
        addChild(background)
        cafeLayer.zPosition = 1
        addChild(cafeLayer)
        // ambient glow pooling over the counter, where the espresso machine lives
        let counterGlow = SKSpriteNode(texture: SpriteLoader.texture("glow"))
        counterGlow.position = CGPoint(x: 128, y: 66)
        counterGlow.setScale(1.15)
        counterGlow.zPosition = 3
        counterGlow.blendMode = .add
        counterGlow.alpha = 0.22
        counterGlow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.14, duration: 2.4), .fadeAlpha(to: 0.26, duration: 2.4),
        ])))
        cafeLayer.addChild(counterGlow)
        casinoLayer.zPosition = 1
        casinoLayer.isHidden = true
        addChild(casinoLayer)
        mapLayer.zPosition = 1
        mapLayer.isHidden = true
        addChild(mapLayer)
        let cam = SKCameraNode()
        cam.position = CGPoint(x: 90, y: 60)
        addChild(cam)
        camera = cam

        // drifting dust motes
        for i in 0..<7 {
            let mote = SKSpriteNode(color: NSColor(calibratedWhite: 1, alpha: 0.35),
                                    size: CGSize(width: 1, height: 1))
            mote.position = CGPoint(x: CGFloat.random(in: 10...170), y: CGFloat.random(in: 20...110))
            mote.zPosition = 35
            addChild(mote)
            let drift = SKAction.repeatForever(.sequence([
                .group([.moveBy(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: -8...4),
                                duration: 6 + Double(i)),
                        .sequence([.fadeAlpha(to: 0.08, duration: 3), .fadeAlpha(to: 0.4, duration: 3)])]),
                .group([.moveBy(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: -4...8),
                                duration: 6 + Double(i))]),
            ]))
            mote.run(drift)
        }
    }

    // MARK: scene mode (café ⇄ casino room)

    func setMode(_ newMode: SceneMode) {
        guard newMode != mode else { return }
        mode = newMode
        cafeLayer.isHidden = mode != .cafe
        casinoLayer.isHidden = mode != .casino
        mapLayer.isHidden = mode != .map
        if mode != .casino { focusTable(false) }
        currentBGKey = ""              // force background swap
        if mode == .casino { buildCasinoIfNeeded() }
        lastState.map { configure(with: $0) }
    }

    /// World map: pins for all cities — gold owned, green affordable, grey locked.
    static let mapSpots: [String: CGPoint] = [   // scene coords (y-up)
        "home": CGPoint(x: 28, y: 68), "sakura": CGPoint(x: 58, y: 88),
        "neon": CGPoint(x: 94, y: 98), "seaside": CGPoint(x: 22, y: 32),
        "forest": CGPoint(x: 58, y: 54), "desert": CGPoint(x: 94, y: 38),
        "snowy": CGPoint(x: 128, y: 78), "sunset": CGPoint(x: 124, y: 28),
        "ember": CGPoint(x: 152, y: 50), "royal": CGPoint(x: 104, y: 68),
        "cloud": CGPoint(x: 148, y: 102), "moon": CGPoint(x: 168, y: 112),
    ]

    private func rebuildMap(_ state: GameState) {
        mapLayer.removeAllChildren()
        for city in Cities.all {
            guard let pos = Self.mapSpots[city.id] else { continue }
            let owned = state.ownsCity(city.id)
            let kind = owned ? "own" : (state.coins >= city.cost ? "buy" : "lock")
            let pin = SKSpriteNode(texture: SpriteLoader.texture("pin_\(kind)"))
            pin.size = pin.texture!.size()
            pin.name = "map:\(city.id)"
            pin.position = CGPoint(x: pos.x, y: pos.y + 5)
            pin.zPosition = 5
            mapLayer.addChild(pin)
            if kind == "buy" {
                pin.run(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 2, duration: 0.45),
                    .moveBy(x: 0, y: -2, duration: 0.45),
                ])))
            }
            if owned, state.cafe.city == city.id {
                let here = SKSpriteNode(texture: SpriteLoader.texture("glow"))
                here.position = pos
                here.zPosition = 4
                here.blendMode = .add
                here.setScale(0.8)
                here.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.3, duration: 0.7), .fadeAlpha(to: 0.8, duration: 0.7),
                ])))
                mapLayer.addChild(here)
            }
            let label = SKLabelNode(text: owned || state.coins >= city.cost
                                    ? city.name : "🪙\(formatNumber(city.cost))")
            label.fontName = "Menlo-Bold"
            label.fontSize = 5
            label.fontColor = owned ? .white : NSColor(calibratedWhite: 1, alpha: 0.75)
            label.position = CGPoint(x: pos.x, y: pos.y - 8)
            label.zPosition = 5
            mapLayer.addChild(label)
        }
    }

    private func buildCasinoIfNeeded() {
        guard !casinoBuilt else { return }
        casinoBuilt = true
        for i in 0..<3 {
            let slot = SKSpriteNode(texture: SpriteLoader.texture("slot_\(i)"))
            slot.size = slot.texture!.size()
            slot.anchorPoint = CGPoint(x: 0.5, y: 0)
            slot.position = CGPoint(x: 32 + CGFloat(i) * 22, y: 46)
            slot.zPosition = 5
            casinoLayer.addChild(slot)
            let g = SKSpriteNode(texture: SpriteLoader.texture("glow"))
            g.position = CGPoint(x: slot.position.x, y: 62)
            g.zPosition = 6
            g.blendMode = .add
            g.alpha = 0.55
            g.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.3, duration: 0.9 + Double(i) * 0.2),
                .fadeAlpha(to: 0.6, duration: 0.9 + Double(i) * 0.2),
            ])))
            casinoLayer.addChild(g)
        }
        let dealer = animatedSprite(prefix: "dealer")
        dealer.position = CGPoint(x: 133, y: 44)
        dealer.zPosition = 4
        casinoLayer.addChild(dealer)
        dealerNode = dealer
        gameFocus.zPosition = 14
        casinoLayer.addChild(gameFocus)
        // chandelier + sign glows
        for (pos, scale, alpha) in [(CGPoint(x: 30, y: 112), 1.6, 0.6),
                                    (CGPoint(x: 90, y: 98), 2.2, 0.35),
                                    (CGPoint(x: 133, y: 34), 1.8, 0.3)] {
            let g = SKSpriteNode(texture: SpriteLoader.texture("glow"))
            g.position = pos
            g.setScale(scale)
            g.zPosition = 12
            g.blendMode = .add
            g.alpha = alpha
            casinoLayer.addChild(g)
        }
    }

    // MARK: per-game table displays

    func setCasinoGame(_ game: CasinoGame) {
        casinoGame = game
        buildCasinoIfNeeded()
        gameFocus.removeAllChildren()
        wheelNode = nil
        switch game {
        case .slots:
            break
        case .blackjack:
            break   // cards arrive via showBlackjackCards
        case .roulette:
            let wheel = SKSpriteNode(texture: SpriteLoader.texture("wheel"))
            wheel.size = wheel.texture!.size()
            wheel.position = CGPoint(x: 133, y: 30)
            gameFocus.addChild(wheel)
            wheelNode = wheel
        case .mahjong:
            // three animal opponents seated around the felt
            let seats = [CGPoint(x: 104, y: 44), CGPoint(x: 133, y: 48), CGPoint(x: 162, y: 44)]
            for (i, pos) in seats.enumerated() {
                let ai = animatedSprite(prefix: "customer_\(i)")
                ai.position = pos
                gameFocus.addChild(ai)
            }
            dealerNode?.isHidden = true
        }
        if game != .mahjong { dealerNode?.isHidden = false }
    }

    /// Mirrors the real blackjack hands onto the felt.
    func showBlackjackCards(player: [(String, Bool)], dealer: [(String, Bool)], hole: Bool) {
        guard casinoGame == .blackjack else { return }
        gameFocus.removeAllChildren()
        func draw(_ cards: [(String, Bool)], y: CGFloat, hole: Bool) {
            for (i, card) in cards.enumerated() {
                let node = SKSpriteNode(color: .white, size: CGSize(width: 9, height: 12))
                node.position = CGPoint(x: 112 + CGFloat(i) * 11, y: y)
                let label = SKLabelNode(text: card.0)
                label.fontName = "Menlo-Bold"
                label.fontSize = 6
                label.fontColor = card.1 ? NSColor(calibratedRed: 0.75, green: 0.15, blue: 0.15, alpha: 1) : .black
                label.verticalAlignmentMode = .center
                node.addChild(label)
                gameFocus.addChild(node)
            }
            if hole {
                let back = SKSpriteNode(color: NSColor(calibratedRed: 0.35, green: 0.25, blue: 0.5, alpha: 1),
                                        size: CGSize(width: 9, height: 12))
                back.position = CGPoint(x: 112 + CGFloat(cards.count) * 11, y: y)
                gameFocus.addChild(back)
            }
        }
        draw(dealer, y: 36, hole: hole)
        draw(player, y: 22, hole: false)
    }

    /// Spins the wheel and settles on the result.
    func spinRouletteWheel(result: Int) {
        guard let wheel = wheelNode else { return }
        wheel.removeAllActions()
        gameFocus.childNode(withName: "resultChip")?.removeFromParent()
        let spin = SKAction.rotate(byAngle: .pi * 8 + CGFloat.random(in: 0...(2 * .pi)), duration: 1.6)
        spin.timingMode = .easeOut
        wheel.run(spin) { [weak self] in
            guard let self else { return }
            let chip = SKSpriteNode(color: result == 0
                ? NSColor(calibratedRed: 0.15, green: 0.5, blue: 0.3, alpha: 1)
                : (CasinoEngine.redNumbers.contains(result)
                    ? NSColor(calibratedRed: 0.75, green: 0.2, blue: 0.2, alpha: 1)
                    : NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.15, alpha: 1)),
                size: CGSize(width: 14, height: 10))
            chip.name = "resultChip"
            chip.position = CGPoint(x: 155, y: 30)
            let label = SKLabelNode(text: "\(result)")
            label.fontName = "Menlo-Bold"
            label.fontSize = 7
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            chip.addChild(label)
            self.gameFocus.addChild(chip)
        }
    }

    /// Sprinkles the mahjong discard pool onto the felt.
    func updateMahjongTable(discards: Int) {
        guard casinoGame == .mahjong else { return }
        gameFocus.childNode(withName: "mjPool")?.removeFromParent()
        let pool = SKNode()
        pool.name = "mjPool"
        for i in 0..<min(discards, 21) {
            let tile = SKSpriteNode(color: .white, size: CGSize(width: 4, height: 6))
            tile.position = CGPoint(x: 110 + CGFloat(i % 7) * 6, y: 34 - CGFloat(i / 7) * 7)
            pool.addChild(tile)
        }
        gameFocus.addChild(pool)
    }

    /// Glides the camera into the game table (and back out).
    func focusTable(_ zoomIn: Bool) {
        guard let cam = camera else { return }
        cam.removeAllActions()
        let move: SKAction
        if zoomIn {
            let target: CGPoint
            switch casinoGame {
            case .slots: target = CGPoint(x: 57, y: 58)       // the slot machines
            default: target = CGPoint(x: 122, y: 42)          // the felt table
            }
            move = .group([.move(to: target, duration: 0.7),
                           .scale(to: 0.62, duration: 0.7)])
        } else {
            move = .group([.move(to: CGPoint(x: 90, y: 60), duration: 0.6),
                           .scale(to: 1.0, duration: 0.6)])
        }
        move.timingMode = .easeInEaseOut
        cam.run(move)
    }

    /// Coin shower over the table when the player wins at the casino.
    func playCasinoWin(_ amount: Double) {
        guard mode == .casino, !isPaused else { return }
        let n = min(14, 5 + Int(amount / 100))
        for i in 0..<n {
            let coin = SKSpriteNode(texture: SpriteLoader.texture("tip"))
            coin.size = coin.texture!.size()
            coin.position = CGPoint(x: 110 + CGFloat.random(in: 0...50), y: 120)
            coin.zPosition = 25
            casinoLayer.addChild(coin)
            let fall = SKAction.sequence([
                .wait(forDuration: Double(i) * 0.08),
                .group([.moveTo(y: CGFloat.random(in: 24...40), duration: 0.7),
                        .rotate(byAngle: .pi * 2, duration: 0.7)]),
                .wait(forDuration: 0.6),
                .fadeOut(withDuration: 0.4),
                .removeFromParent(),
            ])
            fall.timingMode = .easeIn
            coin.run(fall)
        }
        sparkle(at: CGPoint(x: 133, y: 40), color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.5, alpha: 1))
    }

    private var lastState: GameState?

    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: configuration from game state

    func configure(with state: GameState) {
        lastState = state
        configureBackground(state)
        if mode == .map { rebuildMap(state) }
        guard mode == .cafe else { return }
        configureStaff(state)
        configureEquipment(state)
        configureOwner(state)
        configureDirt(state)
        configureClosed(SalesEngine.isClosed(state))
        applyTimeOfDay()
        updateWeather(state)
    }

    // MARK: real-world day/night cycle

    private lazy var timeTint: SKSpriteNode = {
        let n = SKSpriteNode(color: .clear, size: CGSize(width: 180, height: 120))
        n.anchorPoint = .zero
        n.position = .zero
        n.zPosition = 25
        n.blendMode = .alpha
        cafeLayer.addChild(n)
        return n
    }()

    /// Window pane, y-up scene coords matching the door/window baked into the
    /// background art (image rect x30-64, row12-50 → scene y 70-108).
    private lazy var windowTint: SKSpriteNode = {
        let n = SKSpriteNode(color: .clear, size: CGSize(width: 32, height: 36))
        n.position = CGPoint(x: 47, y: 89)
        n.zPosition = 3
        n.blendMode = .alpha
        cafeLayer.addChild(n)
        return n
    }()

    private var lastTimePhase = ""

    private func applyTimeOfDay() {
        let hour = Calendar.current.component(.hour, from: Date())
        let phase: String
        let tint: NSColor
        let alpha: CGFloat
        let windowColor: NSColor
        switch hour {
        case 5..<7:
            phase = "dawn"; tint = NSColor(calibratedRed: 1, green: 0.65, blue: 0.55, alpha: 1)
            alpha = 0.16; windowColor = NSColor(calibratedRed: 1, green: 0.72, blue: 0.5, alpha: 0.35)
        case 7..<17:
            phase = "day"; tint = .clear; alpha = 0; windowColor = .clear
        case 17..<20:
            phase = "dusk"; tint = NSColor(calibratedRed: 0.85, green: 0.42, blue: 0.55, alpha: 1)
            alpha = 0.22; windowColor = NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.5, alpha: 0.4)
        default:
            phase = "night"; tint = NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.42, alpha: 1)
            alpha = 0.42; windowColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.22, alpha: 0.65)
        }
        lastTimePhase = phase
        timeTint.run(.group([.colorize(with: tint, colorBlendFactor: 1, duration: 2.5),
                             .fadeAlpha(to: alpha, duration: 2.5)]))
        windowTint.run(.group([.colorize(with: windowColor, colorBlendFactor: 1, duration: 2.5),
                              .fadeAlpha(to: windowColor == .clear ? 0 : 1, duration: 2.5)]))
    }

    // MARK: weather (rain event)

    private var rainNodes: [SKSpriteNode] = []
    private var rainActive = false

    private func updateWeather(_ state: GameState) {
        let shouldRain = Events.isActive("rain", state)
        guard shouldRain != rainActive else { return }
        rainActive = shouldRain
        if shouldRain {
            for _ in 0..<18 {
                let drop = SKSpriteNode(color: NSColor(calibratedRed: 0.75, green: 0.85, blue: 1, alpha: 0.55),
                                        size: CGSize(width: 1, height: 5))
                drop.position = CGPoint(x: CGFloat.random(in: 0...180), y: CGFloat.random(in: 0...120))
                drop.zPosition = 26
                let dropHeight = CGFloat.random(in: 90...130)
                let fall = SKAction.repeatForever(.sequence([
                    .moveBy(x: 0, y: -dropHeight, duration: Double.random(in: 0.7...1.1)),
                    .moveBy(x: 0, y: dropHeight, duration: 0),
                ]))
                drop.run(fall)
                cafeLayer.addChild(drop)
                rainNodes.append(drop)
            }
        } else {
            rainNodes.forEach { $0.removeFromParent() }
            rainNodes.removeAll()
        }
    }

    private var currentBGKey = ""

    private func configureBackground(_ state: GameState) {
        let tier = min(2, state.stars == 0 ? 0 : (state.stars < 10 ? 1 : 2))
        let key = mode == .casino ? "bg_casino"
            : mode == .map ? "worldmap"
            : "bg_\(state.cafe.city)_tier\(tier)"
        guard key != currentBGKey else { return }
        currentBGKey = key
        let bgTexture = SpriteLoader.texture(key)
        background.texture = bgTexture
        background.size = CGSize(width: 180, height: 120)
        guard mode == .cafe else { return }
        cafeLayer.childNode(withName: "counterFront")?.removeFromParent()
        cafeLayer.childNode(withName: "lightShaft")?.removeFromParent()
        if state.cafe.city != "neon" {
            let shaft = SKSpriteNode(texture: SpriteLoader.texture("shaft"))
            shaft.name = "lightShaft"
            shaft.size = shaft.texture!.size()
            shaft.anchorPoint = CGPoint(x: 0, y: 1)
            shaft.position = CGPoint(x: 26, y: 106)
            shaft.zPosition = 22
            shaft.blendMode = .add
            shaft.setScale(1.3)
            shaft.alpha = 0.8
            shaft.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.55, duration: 4),
                .fadeAlpha(to: 0.85, duration: 4),
            ])))
            cafeLayer.addChild(shaft)
        }
        let counterRect = CGRect(x: 96.0 / 180, y: 40.0 / 120, width: 74.0 / 180, height: 28.0 / 120)
        let front = SKSpriteNode(texture: SKTexture(rect: counterRect, in: bgTexture))
        front.name = "counterFront"
        front.anchorPoint = .zero
        front.position = CGPoint(x: 96, y: 40)
        front.size = CGSize(width: 74, height: 28)
        front.zPosition = 8
        cafeLayer.addChild(front)
    }

    private func configureStaff(_ state: GameState) {
        let hired = Set(state.staffLevels.filter { $0.value > 0 }.keys)
        guard hired != configuredStaff else { return }
        for id in hired.subtracting(configuredStaff) { addStaff(id) }
        for id in configuredStaff.subtracting(hired) {
            staffNodes[id]?.removeFromParent()
            staffNodes[id] = nil
        }
        configuredStaff = hired
    }

    private func configureEquipment(_ state: GameState) {
        for (id, level) in state.equipmentLevels where level > 0 {
            let visTier = min(2, (level - 1) / 5)
            if configuredEquipTiers[id] != visTier {
                equipNodes[id]?.removeFromParent()
                let node = SKSpriteNode(texture: SpriteLoader.texture("equip_\(id)_\(visTier)"))
                node.texture.map { node.size = $0.size() }
                if let (pos, z) = Self.equipSpots[id] {
                    node.anchorPoint = CGPoint(x: 0.5, y: 0)
                    node.position = pos
                    node.zPosition = z
                }
                cafeLayer.addChild(node)
                equipNodes[id] = node
                configuredEquipTiers[id] = visTier
            }
        }
    }

    private func configureOwner(_ state: GameState) {
        let key = "\(state.owner.species)-\(state.owner.palette)-\(state.owner.accessory)"
        guard key != configuredOwnerKey else { return }
        configuredOwnerKey = key
        ownerNode?.removeFromParent()
        let prefix = "owner_\(state.owner.species)_\(state.owner.palette)"
        let node = animatedSprite(prefix: prefix)
        if state.owner.accessory != "none" {
            let acc = SKSpriteNode(texture: SpriteLoader.texture("acc_\(state.owner.accessory)"))
            acc.size = acc.texture!.size()
            acc.anchorPoint = CGPoint(x: 0.5, y: 0)
            acc.position = .zero
            acc.zPosition = 1
            node.addChild(acc)
        }
        node.position = CGPoint(x: 40, y: 42)
        node.zPosition = 10
        cafeLayer.addChild(node)
        ownerNode = node
        let wander = SKAction.repeatForever(.sequence([
            .moveTo(x: 90, duration: 4.5), .wait(forDuration: 2),
            .moveTo(x: 30, duration: 4.5), .wait(forDuration: 3),
        ]))
        node.run(wander)
        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 0.4), .moveBy(x: 0, y: -2, duration: 0.4),
        ]))
        node.run(bob)
    }

    private func configureDirt(_ state: GameState) {
        let count = SalesEngine.dirtSpots(state)
        guard count != configuredDirt else { return }
        configuredDirt = count
        while dirtNodes.count > count {
            dirtNodes.removeLast().removeFromParent()
        }
        while dirtNodes.count < count {
            let i = dirtNodes.count
            let node = SKSpriteNode(texture: SpriteLoader.texture(i % 2 == 0 ? "dirt_stain" : "dirt_cup"))
            node.size = node.texture!.size()
            node.name = "dirt"
            node.position = Self.dirtSpots[i % Self.dirtSpots.count]
            node.zPosition = 4
            node.alpha = 0
            cafeLayer.addChild(node)
            node.run(.fadeAlpha(to: 0.9, duration: 0.8))
            dirtNodes.append(node)
        }
    }

    private func configureClosed(_ closed: Bool) {
        if !closed {
            // always force-clear stray overlays, even if bookkeeping is stale
            cafeLayer.childNode(withName: "closedOverlay")?.removeFromParent()
        }
        guard closed != configuredClosed else { return }
        configuredClosed = closed
        if closed {
            let overlay = SKNode()
            overlay.name = "closedOverlay"
            overlay.zPosition = 30
            let dim = SKSpriteNode(color: NSColor(calibratedRed: 0.05, green: 0.04, blue: 0.09, alpha: 0.45),
                                   size: CGSize(width: 180, height: 120))
            dim.anchorPoint = .zero
            overlay.addChild(dim)
            let sign = SKSpriteNode(texture: SpriteLoader.texture("closed_sign"))
            sign.size = sign.texture!.size()
            sign.position = CGPoint(x: 14, y: 74)      // on the door
            overlay.addChild(sign)
            for (i, p) in [CGPoint(x: 7, y: 113), CGPoint(x: 173, y: 113)].enumerated() {
                let web = SKSpriteNode(texture: SpriteLoader.texture("cobweb"))
                web.size = web.texture!.size()
                web.position = p
                web.xScale = i == 0 ? 1 : -1
                overlay.addChild(web)
            }
            overlay.alpha = 0
            cafeLayer.addChild(overlay)
            overlay.run(.fadeIn(withDuration: 1.5))
            closedOverlay = overlay
        } else {
            let node = closedOverlay
            closedOverlay = nil
            node?.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
        }
    }

    private func addStaff(_ id: String) {
        let node = animatedSprite(prefix: "staff_\(id)")
        node.position = Self.staffSpots[id] ?? CGPoint(x: 90, y: 30)
        node.zPosition = id == "biscuit" ? 10 : 6
        cafeLayer.addChild(node)
        staffNodes[id] = node
        if id == "biscuit" {
            let patrol = SKAction.repeatForever(.sequence([
                .moveTo(x: 42, duration: 2.6), .wait(forDuration: 1.2),
                .moveTo(x: 76, duration: 2.6), .wait(forDuration: 1.2),
            ]))
            node.run(patrol)
        } else {
            // stationed staff: a visible "at work" bob + lean at the counter/station,
            // so they read as busy even when no customer is currently being served.
            let work = SKAction.repeatForever(.sequence([
                .group([.moveBy(x: 0, y: 2.5, duration: 0.35), .scaleX(to: 1.04, y: 0.96, duration: 0.35)]),
                .group([.moveBy(x: 0, y: -2.5, duration: 0.35), .scaleX(to: 1, y: 1, duration: 0.35)]),
                .wait(forDuration: Double.random(in: 0.3...0.9)),
            ]))
            node.run(.sequence([.wait(forDuration: Double.random(in: 0...0.8)), work]))
        }
    }

    private func animatedSprite(prefix: String) -> SKSpriteNode {
        let frames = [SpriteLoader.texture("\(prefix)_0"), SpriteLoader.texture("\(prefix)_1")]
        let node = SKSpriteNode(texture: frames[0])
        node.size = frames[0].size()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.run(.repeatForever(.animate(with: frames, timePerFrame: 0.45)))
        let shadow = SKSpriteNode(texture: SpriteLoader.texture("shadow"))
        shadow.size = shadow.texture!.size()
        shadow.position = CGPoint(x: 0, y: 0)
        shadow.zPosition = -1
        node.addChild(shadow)
        return node
    }

    // MARK: customer visits (event-driven)

    func playSale(_ event: SaleEvent) {
        guard !isPaused, mode == .cafe, activeCustomers < 4 else { return }
        activeCustomers += 1
        let customer = animatedSprite(prefix: "customer_\(event.customerSpecies)")
        customer.position = Self.doorPoint
        customer.zPosition = 11
        customer.alpha = 0
        cafeLayer.addChild(customer)

        let toCounter = SKAction.sequence([
            .fadeIn(withDuration: 0.3),
            .move(to: Self.counterPoint, duration: 2.2),
        ])
        customer.run(toCounter) { [weak self, weak customer] in
            guard let self, let customer else { return }
            self.showBubble(over: customer, event: event)
            if event.bigSpender {
                self.sparkle(at: customer.position, color: NSColor(calibratedRed: 1, green: 0.85, blue: 0.4, alpha: 1))
            }
            if event.mood == .angry || event.mood == .sadLeave || event.mood == .noTable || !event.dineIn {
                customer.run(.sequence([
                    .wait(forDuration: 1.4),
                    .move(to: Self.doorPoint, duration: 1.6),
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent(),
                ])) { [weak self] in self?.activeCustomers -= 1 }
            } else {
                let seat = Self.seatPoints[Int.random(in: 0..<Self.seatPoints.count)]
                customer.run(.sequence([
                    .wait(forDuration: 1.6),
                    .move(to: seat, duration: 1.8),
                    .wait(forDuration: 3.5),
                    .move(to: Self.doorPoint, duration: 2.2),
                    .fadeOut(withDuration: 0.3),
                    .removeFromParent(),
                ])) { [weak self] in self?.activeCustomers -= 1 }
            }
        }
    }

    private func showBubble(over node: SKSpriteNode, event: SaleEvent) {
        let texName: String
        switch event.mood {
        case .angry: texName = "bubble_angry"
        case .sadLeave, .settled, .noTable: texName = "bubble_sad"
        case .happy: texName = "bubble"
        }
        let bubble = SKSpriteNode(texture: SpriteLoader.texture(texName))
        bubble.size = bubble.texture!.size()
        bubble.position = CGPoint(x: 4, y: 24)
        bubble.zPosition = 2
        if event.mood == .happy {
            let icon = SKSpriteNode(texture: SpriteLoader.texture("item_\(event.itemIcon)"))
            icon.size = icon.texture!.size()
            icon.position = CGPoint(x: -1, y: 2)
            bubble.addChild(icon)
        }
        bubble.alpha = 0
        node.addChild(bubble)
        bubble.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 1.6),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: golden tips

    func scheduleNextTip() {
        nextTipAt = Date().addingTimeInterval(Double.random(in: 120...300))
    }

    override func update(_ currentTime: TimeInterval) {
        guard mode == .cafe else { return }
        if tipNode == nil, Date() >= nextTipAt {
            spawnTip()
        }
    }

    private func spawnTip() {
        let node = SKSpriteNode(texture: SpriteLoader.texture("tip"))
        node.size = node.texture!.size()
        node.name = "tip"
        node.position = CGPoint(x: CGFloat.random(in: 34...86), y: CGFloat.random(in: 10...34))
        node.zPosition = 20
        node.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.5),
            .moveBy(x: 0, y: -3, duration: 0.5),
        ])))
        cafeLayer.addChild(node)
        tipNode = node
        node.run(.sequence([.wait(forDuration: 45), .fadeOut(withDuration: 1), .removeFromParent()]))
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .map {
            let p = event.location(in: self)
            for node in mapLayer.children {
                if let name = node.name, name.hasPrefix("map:"),
                   node.frame.insetBy(dx: -6, dy: -6).contains(p) {
                    onMapSelect?(String(name.dropFirst(4)))
                    return
                }
            }
            return
        }
        guard mode == .cafe else { return }
        let p = event.location(in: self)
        if let tip = tipNode, tip.parent != nil, tip.frame.insetBy(dx: -6, dy: -6).contains(p) {
            collectTip(tip)
            return
        }
        for dirt in dirtNodes where dirt.parent != nil && dirt.frame.insetBy(dx: -4, dy: -4).contains(p) {
            cleanDirt(dirt)
            return
        }
    }

    private func cleanDirt(_ node: SKSpriteNode) {
        dirtNodes.removeAll { $0 === node }
        configuredDirt = dirtNodes.count
        onCleanSpot?()
        sparkle(at: node.position, color: NSColor(calibratedRed: 0.75, green: 0.95, blue: 1, alpha: 1))
        node.removeFromParent()
    }

    private func collectTip(_ tip: SKSpriteNode) {
        tipNode = nil
        onGoldenTip?()
        scheduleNextTip()
        tip.removeAllActions()
        tip.run(.group([.moveBy(x: 0, y: 22, duration: 0.4), .fadeOut(withDuration: 0.4)]))
        tip.run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
        sparkle(at: tip.position, color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.5, alpha: 1))
    }

    private func sparkle(at position: CGPoint, color: NSColor) {
        for i in 0..<5 {
            let s = SKSpriteNode(color: color, size: CGSize(width: 2, height: 2))
            s.position = position
            s.zPosition = 21
            addChild(s)
            let angle = Double(i) / 5 * 2 * .pi
            s.run(.sequence([
                .group([.moveBy(x: 12 * cos(angle), y: 12 * sin(angle), duration: 0.5),
                        .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Called by the popover owner: animate + spawn tips only while visible.
    func setActive(_ active: Bool) {
        isPaused = !active
        if active {
            if tipNode?.parent == nil { tipNode = nil }
            if tipNode == nil { scheduleNextTip() }
        }
    }
}
