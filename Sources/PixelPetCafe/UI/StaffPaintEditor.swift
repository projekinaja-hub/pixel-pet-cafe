import SwiftUI

/// Freehand pixel-art editor: tap/drag to paint the same 16×20 canvas every
/// generated staff sprite uses, with a small curated palette plus a free
/// ColorPicker swatch, an eraser, one-step undo, and reset-to-blank (which
/// falls back to the ordinary color-mixed look — see EconomyEngine.
/// setStaffPaint). Changes only commit on Apply; the scrim/X/Cancel discard.
struct StaffPaintEditorSheet: View {
    let id: String
    let name: String
    @ObservedObject var controller: GameController
    let dismiss: () -> Void

    @State private var art: PixelArt
    @State private var undoStack: [PixelArt] = []
    @State private var customColor: Color = .black
    @State private var selectedColor: UInt32
    @State private var erasing = false
    @State private var strokeStarted = false

    private static let cellSize: CGFloat = 10
    private static let palette: [UInt32] = [
        .packRGBA(r: 52, g: 34, b: 41),      // ink
        .packRGBA(r: 252, g: 250, b: 244),   // white
        .packRGBA(r: 247, g: 233, b: 205),   // cream
        .packRGBA(r: 249, g: 185, b: 24),    // gold
        .packRGBA(r: 203, g: 82, b: 74),     // red
        .packRGBA(r: 96, g: 153, b: 92),     // green
        .packRGBA(r: 94, g: 129, b: 181),    // blue
        .packRGBA(r: 233, g: 158, b: 160),   // pink
        .packRGBA(r: 166, g: 110, b: 62),    // wood/brown
        .packRGBA(r: 150, g: 102, b: 66),    // fur brown
        .packRGBA(r: 88, g: 60, b: 42),      // dark brown
        .packRGBA(r: 120, g: 120, b: 130),   // gray
    ]

    init(id: String, name: String, controller: GameController, dismiss: @escaping () -> Void) {
        self.id = id
        self.name = name
        self.controller = controller
        self.dismiss = dismiss
        _art = State(initialValue: (controller.state.staffPaint[id] ?? .blank()))
        _selectedColor = State(initialValue: Self.palette[0])
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 8) {
                HStack {
                    Text("🖌️ Draw \(name)")
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

                canvasView

                paletteRow

                HStack(spacing: 8) {
                    toolButton(icon: "arrow.uturn.backward", label: "Undo", enabled: !undoStack.isEmpty) {
                        if let last = undoStack.popLast() { art = last }
                    }
                    toolButton(icon: "eraser", label: "Erase", enabled: true, active: erasing) {
                        erasing.toggle()
                    }
                    toolButton(icon: "trash", label: "Clear", enabled: !art.isBlank) {
                        undoStack.append(art)
                        art = .blank()
                    }
                }

                HStack(spacing: 8) {
                    Button("Reset to default") {
                        controller.resetStaffPaint(id)
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
                        controller.setStaffPaint(id, art)
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
            .frame(width: 320)
            .background(Theme.bg)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        }
        .frame(width: 360, height: 544)
        .transition(.opacity)
    }

    private var canvasWidth: CGFloat { CGFloat(PixelArt.width) * Self.cellSize }
    private var canvasHeight: CGFloat { CGFloat(PixelArt.height) * Self.cellSize }

    private var canvasView: some View {
        Canvas { context, _ in
            for y in 0..<PixelArt.height {
                for x in 0..<PixelArt.width {
                    let rect = CGRect(x: CGFloat(x) * Self.cellSize, y: CGFloat(y) * Self.cellSize,
                                       width: Self.cellSize, height: Self.cellSize)
                    let checker = (x + y).isMultiple(of: 2)
                    context.fill(Path(rect), with: .color(checker ? Color.white.opacity(0.06) : Color.clear))
                    let c = art.color(x: x, y: y)
                    if c != 0 {
                        let comp = c.rgbaComponents
                        context.fill(Path(rect), with: .color(Color(red: comp.r, green: comp.g, blue: comp.b)))
                    }
                }
            }
            // grid lines
            for x in 0...PixelArt.width {
                let px = CGFloat(x) * Self.cellSize
                context.stroke(Path { $0.move(to: CGPoint(x: px, y: 0)); $0.addLine(to: CGPoint(x: px, y: canvasHeight)) },
                                with: .color(Theme.dim.opacity(0.15)), lineWidth: 0.5)
            }
            for y in 0...PixelArt.height {
                let py = CGFloat(y) * Self.cellSize
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: py)); $0.addLine(to: CGPoint(x: canvasWidth, y: py)) },
                                with: .color(Theme.dim.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(Theme.card)
        .cornerRadius(4)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !strokeStarted {
                        strokeStarted = true
                        undoStack.append(art)
                        if undoStack.count > 10 { undoStack.removeFirst() }
                    }
                    paint(at: value.location)
                }
                .onEnded { _ in strokeStarted = false }
        )
    }

    private func paint(at point: CGPoint) {
        let x = Int(point.x / Self.cellSize)
        let y = Int(point.y / Self.cellSize)
        guard x >= 0, x < PixelArt.width, y >= 0, y < PixelArt.height else { return }
        art.set(x: x, y: y, color: erasing ? 0 : selectedColor)
    }

    private var paletteRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Self.palette, id: \.self) { c in
                    let comp = c.rgbaComponents
                    Circle()
                        .fill(Color(red: comp.r, green: comp.g, blue: comp.b))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Theme.gold, lineWidth: selectedColor == c && !erasing ? 2 : 0))
                        .onTapGesture { selectedColor = c; erasing = false }
                }
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 20)
                    .onChange(of: customColor) { newColor in
                        selectedColor = StaffColor(color: newColor).packed
                        erasing = false
                    }
            }
        }
    }

    private func toolButton(icon: String, label: String, enabled: Bool, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundColor(active ? Theme.bg : (enabled ? Theme.cream : Theme.dim.opacity(0.4)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? Theme.gold : Theme.card)
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private extension StaffColor {
    var packed: UInt32 { .packRGBA(r: Int(r), g: Int(g), b: Int(b)) }
}
