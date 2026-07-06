import SpriteKit

/// The animated pixel café. Logical size 180×120, presented .aspectFit into a
/// 360×240 SpriteView. Customers walk in via events from the GameController.
final class CafeScene: SKScene {
    var onGoldenTip: (() -> Void)?
    var onCleanSpot: (() -> Void)?

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
        backgroundColor = NSColor(calibratedRed: 0.16, green: 0.13, blue: 0.15, alpha: 1)
        background.anchorPoint = .zero
        background.position = .zero
        background.zPosition = 0
        addChild(background)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: configuration from game state

    func configure(with state: GameState) {
        configureBackground(state)
        configureStaff(state)
        configureEquipment(state)
        configureOwner(state)
        configureDirt(state)
        configureClosed(SalesEngine.isClosed(state))
    }

    private func configureBackground(_ state: GameState) {
        let tier = min(2, state.stars == 0 ? 0 : (state.stars < 10 ? 1 : 2))
        guard tier != currentBGTier else { return }
        let bgTexture = SpriteLoader.texture("bg_tier\(tier)")
        background.texture = bgTexture
        background.size = CGSize(width: 180, height: 120)
        currentBGTier = tier
        childNode(withName: "counterFront")?.removeFromParent()
        let counterRect = CGRect(x: 96.0 / 180, y: 40.0 / 120, width: 74.0 / 180, height: 28.0 / 120)
        let front = SKSpriteNode(texture: SKTexture(rect: counterRect, in: bgTexture))
        front.name = "counterFront"
        front.anchorPoint = .zero
        front.position = CGPoint(x: 96, y: 40)
        front.size = CGSize(width: 74, height: 28)
        front.zPosition = 8
        addChild(front)
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
                addChild(node)
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
        addChild(node)
        ownerNode = node
        let wander = SKAction.repeatForever(.sequence([
            .moveTo(x: 90, duration: 4.5), .wait(forDuration: 2),
            .moveTo(x: 30, duration: 4.5), .wait(forDuration: 3),
        ]))
        node.run(wander)
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
            addChild(node)
            node.run(.fadeAlpha(to: 0.9, duration: 0.8))
            dirtNodes.append(node)
        }
    }

    private func configureClosed(_ closed: Bool) {
        guard closed != configuredClosed else { return }
        configuredClosed = closed
        if closed {
            let overlay = SKNode()
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
            addChild(overlay)
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
        addChild(node)
        staffNodes[id] = node
        if id == "biscuit" {
            let patrol = SKAction.repeatForever(.sequence([
                .moveTo(x: 42, duration: 2.6), .wait(forDuration: 1.2),
                .moveTo(x: 76, duration: 2.6), .wait(forDuration: 1.2),
            ]))
            node.run(patrol)
        }
    }

    private func animatedSprite(prefix: String) -> SKSpriteNode {
        let frames = [SpriteLoader.texture("\(prefix)_0"), SpriteLoader.texture("\(prefix)_1")]
        let node = SKSpriteNode(texture: frames[0])
        node.size = frames[0].size()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.run(.repeatForever(.animate(with: frames, timePerFrame: 0.45)))
        return node
    }

    // MARK: customer visits (event-driven)

    func playSale(_ event: SaleEvent) {
        guard !isPaused, activeCustomers < 4 else { return }
        activeCustomers += 1
        let customer = animatedSprite(prefix: "customer_\(event.customerSpecies)")
        customer.position = Self.doorPoint
        customer.zPosition = 11
        customer.alpha = 0
        addChild(customer)

        let toCounter = SKAction.sequence([
            .fadeIn(withDuration: 0.3),
            .move(to: Self.counterPoint, duration: 2.2),
        ])
        customer.run(toCounter) { [weak self, weak customer] in
            guard let self, let customer else { return }
            self.showBubble(over: customer, event: event)
            if event.angry {
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
        let bubble = SKSpriteNode(texture: SpriteLoader.texture(event.angry ? "bubble_angry" : "bubble"))
        bubble.size = bubble.texture!.size()
        bubble.position = CGPoint(x: 4, y: 24)
        bubble.zPosition = 2
        if !event.angry {
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
        addChild(node)
        tipNode = node
        node.run(.sequence([.wait(forDuration: 45), .fadeOut(withDuration: 1), .removeFromParent()]))
    }

    override func mouseDown(with event: NSEvent) {
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
