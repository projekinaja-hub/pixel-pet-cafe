import SpriteKit

/// The animated pixel café. Logical size 180×120 (matches background art),
/// presented with .aspectFit into a 360×240 SpriteView.
final class CafeScene: SKScene {
    var onGoldenTip: (() -> Void)?

    private var background = SKSpriteNode()
    private var staffNodes: [String: SKSpriteNode] = [:]
    private var customerNodes: [SKSpriteNode] = []
    private var equipNodes: [String: SKSpriteNode] = [:]
    private var recipeBubble: SKSpriteNode?
    private var tipNode: SKSpriteNode?
    private var nextTipAt: Date = .distantFuture

    private var currentBGTier = -1
    private var configuredStaff: Set<String> = []
    private var configuredEquipTiers: [String: Int] = [:]
    private var configuredRecipe: String?

    // scene positions (y-up). Staff behind the counter; biscuit waits tables.
    private static let staffSpots: [String: CGPoint] = [
        "mocha": CGPoint(x: 132, y: 58),
        "juno":  CGPoint(x: 148, y: 58),
        "bo":    CGPoint(x: 162, y: 58),
        "earl":  CGPoint(x: 118, y: 58),
        "poppy": CGPoint(x: 88, y: 46),
        "biscuit": CGPoint(x: 62, y: 24),
    ]
    private static let equipSpots: [String: (CGPoint, CGFloat)] = [   // position, zPosition
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
        let tier = min(2, state.stars == 0 ? 0 : (state.stars < 10 ? 1 : 2))
        if tier != currentBGTier {
            let bgTexture = SpriteLoader.texture("bg_tier\(tier)")
            background.texture = bgTexture
            background.size = CGSize(width: 180, height: 120)
            currentBGTier = tier
            // counter front, cropped from the background, occludes staff behind it
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

        let hired = Set(state.staffLevels.filter { $0.value > 0 }.keys)
        if hired != configuredStaff {
            for id in hired.subtracting(configuredStaff) { addStaff(id) }
            for id in configuredStaff.subtracting(hired) {
                staffNodes[id]?.removeFromParent()
                staffNodes[id] = nil
            }
            configuredStaff = hired
            syncCustomers(count: min(3, max(1, hired.count - 1)))
        }

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

        if let newest = state.unlockedRecipes.last, newest != configuredRecipe {
            configuredRecipe = newest
            showRecipeBubble()
        }
    }

    private func addStaff(_ id: String) {
        let node = animatedSprite(prefix: "staff_\(id)")
        node.position = Self.staffSpots[id] ?? CGPoint(x: 90, y: 30)
        node.zPosition = id == "biscuit" ? 10 : 6
        addChild(node)
        staffNodes[id] = node
        if id == "biscuit" {  // waiter patrols between the tables
            let patrol = SKAction.repeatForever(.sequence([
                .moveTo(x: 42, duration: 2.6), .wait(forDuration: 1.2),
                .moveTo(x: 76, duration: 2.6), .wait(forDuration: 1.2),
            ]))
            node.run(patrol)
        }
    }

    private func syncCustomers(count: Int) {
        while customerNodes.count < count {
            let i = customerNodes.count
            let node = animatedSprite(prefix: "customer_\(i)")
            node.position = CGPoint(x: 40 + 26 * CGFloat(i), y: 30 - 6 * CGFloat(i))
            node.zPosition = 8
            addChild(node)
            let wander = SKAction.repeatForever(.sequence([
                .moveBy(x: 14, y: 0, duration: 3.0 + Double(i)),
                .wait(forDuration: 2 + Double(i)),
                .moveBy(x: -14, y: 0, duration: 3.0 + Double(i)),
                .wait(forDuration: 1.5),
            ]))
            node.run(wander)
            customerNodes.append(node)
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

    private func showRecipeBubble() {
        recipeBubble?.removeFromParent()
        let bubble = SKSpriteNode(texture: SpriteLoader.texture("recipe_bubble"))
        bubble.size = bubble.texture!.size()
        bubble.position = CGPoint(x: 118, y: 78)
        bubble.zPosition = 12
        addChild(bubble)
        recipeBubble = bubble
        bubble.alpha = 0
        bubble.run(.sequence([
            .fadeIn(withDuration: 0.3),
            .wait(forDuration: 6),
            .fadeOut(withDuration: 0.5),
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
        // vanish if ignored for 45s
        node.run(.sequence([.wait(forDuration: 45), .fadeOut(withDuration: 1), .removeFromParent()]))
        run(.sequence([.wait(forDuration: 46)]), withKey: "tipExpiry")
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if let tip = tipNode, tip.parent != nil, tip.frame.insetBy(dx: -6, dy: -6).contains(p) {
            collectTip(tip)
        }
    }

    private func collectTip(_ tip: SKSpriteNode) {
        tipNode = nil
        onGoldenTip?()
        scheduleNextTip()
        tip.removeAllActions()
        tip.run(.group([
            .moveBy(x: 0, y: 22, duration: 0.4),
            .fadeOut(withDuration: 0.4),
        ]))
        tip.run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
        for i in 0..<5 {  // sparkle burst
            let s = SKSpriteNode(color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.5, alpha: 1),
                                 size: CGSize(width: 2, height: 2))
            s.position = tip.position
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
