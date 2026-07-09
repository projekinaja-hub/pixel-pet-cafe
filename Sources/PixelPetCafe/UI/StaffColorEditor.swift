import SwiftUI

extension StaffColor {
    var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        self.init(r: Double(ns.redComponent) * 255, g: Double(ns.greenComponent) * 255, b: Double(ns.blueComponent) * 255)
    }
}

/// Composited staff portrait matching CafeScene's own bodylight/bodydark/
/// clothes/detail layering (see split_staff_layers in generate_sprites.py) —
/// `.colorMultiply` on a pure-white mask reproduces the same full-replace
/// tint SpriteKit gets from `colorBlendFactor = 1`, so this preview always
/// matches what's on stage.
struct StaffLayeredIcon: View {
    let id: String
    let pair: StaffColorPair
    /// A freehand-painted portrait, if this staff member has one — takes
    /// over entirely (see PixelArtRenderer), same "paint replaces tint"
    /// rule CafeScene follows.
    var paint: PixelArt? = nil
    var scale: CGFloat = 1.4

    var body: some View {
        if let paint {
            Image(nsImage: PixelArtRenderer.nsImage(paint))
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(PixelArt.width) * scale, height: CGFloat(PixelArt.height) * scale)
        } else {
            ZStack {
                PixelImage(name: "staff_\(id)_bodylight_0", scale: scale).colorMultiply(pair.body.color)
                PixelImage(name: "staff_\(id)_bodydark_0", scale: scale).colorMultiply(pair.body.darkened.color)
                PixelImage(name: "staff_\(id)_clothes_0", scale: scale).colorMultiply(pair.clothes.color)
                PixelImage(name: "staff_\(id)_detail_0", scale: scale)
            }
        }
    }
}

/// Tap-to-edit sheet: two free-mix color pickers (Body, Clothes) with a live
/// preview, Apply, and Reset-to-default. Global per-role, free, and purely
/// cosmetic — see StaffPalette for the shipped defaults every staff member
/// starts at.
struct StaffColorEditorSheet: View {
    let id: String
    let name: String
    @ObservedObject var controller: GameController
    let dismiss: () -> Void

    @State private var body_: Color
    @State private var clothes: Color

    init(id: String, name: String, controller: GameController, dismiss: @escaping () -> Void) {
        self.id = id
        self.name = name
        self.controller = controller
        self.dismiss = dismiss
        let pair = StaffPalette.pair(for: id, in: controller.state)
        _body_ = State(initialValue: pair.body.color)
        _clothes = State(initialValue: pair.clothes.color)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 10) {
                HStack {
                    Text("🎨 Recolor \(name)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.cream)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }

                StaffLayeredIcon(id: id, pair: StaffColorPair(body: StaffColor(color: body_), clothes: StaffColor(color: clothes)), scale: 4)
                    .frame(width: 72, height: 90)
                    .background(Theme.bg.opacity(0.6))
                    .cornerRadius(9)

                ColorPicker("Body / fur", selection: $body_, supportsOpacity: false)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cream)
                ColorPicker("Clothes / apron", selection: $clothes, supportsOpacity: false)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cream)

                HStack(spacing: 8) {
                    Button("Reset to default") {
                        controller.resetStaffColor(id)
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.dim)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.card)
                    .cornerRadius(7)

                    Spacer()

                    Button("Apply") {
                        controller.setStaffColor(id, body: StaffColor(color: body_), clothes: StaffColor(color: clothes))
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.bg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.gold)
                    .cornerRadius(7)
                }
            }
            .padding(12)
            .frame(width: 300)
            .background(Theme.bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
        .frame(width: 360, height: 544)
        .transition(.opacity)
    }
}
