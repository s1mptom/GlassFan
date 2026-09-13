import SwiftUI

/// Segmented control whose selection is a drop of glass you can pick up.
///
/// At rest the selection is a glass platter under its label. Press anywhere on the
/// control and the platter lifts into a lens - larger than the track, magnifying
/// what is under it - which follows the pointer, stretches with speed, and on
/// release glides to the nearest segment and settles back into a platter. This is
/// the lens iOS 26 gives its segmented controls and tab bars; macOS gives it only
/// to sliders and switches, and not as anything an app can borrow, so it is drawn
/// here from public parts.
///
/// Every segment keeps the same width whatever is selected, and the label weight
/// never changes with selection - both used to resize the control under the pointer.
struct GlassSegmented<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
    }

    let items: [Item]
    @Binding var selection: Value
    /// nil lets each segment size to its own label, as in the design.
    var segmentWidth: CGFloat? = 96
    var fontSize: CGFloat = 12.5
    /// Segments share the available width equally, so the control fills the row
    /// it sits in - the menu bar panel's mode switch spans the panel this way.
    var fills = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Segment frames in the row's own space, measured by the labels themselves.
    @State private var frames: [Int: CGRect] = [:]

    /// The lens lives in an observable object rather than in this view's state.
    /// A drag writes to it sixty times a second, and as state here every write
    /// re-evaluated the whole control - labels, measurements and all - when only
    /// the lens and the hole it cuts need to follow.
    @State private var lens = LensState()

    private let space = "GlassSegmented"

    private var selectedIndex: Int { items.firstIndex { $0.value == selection } ?? 0 }
    private var measured: Bool { frames.count == items.count }

    var body: some View {
        LensCutout(lens: lens, band: band) { labels }
            .background(alignment: .topLeading) {
                LensPlatter(lens: lens, band: band, resting: frames[selectedIndex], selectedIndex: selectedIndex)
            }
            .overlay(alignment: .topLeading) {
                LensOverlay(lens: lens, band: band, titles: items.map(\.title), frames: frames,
                            fontSize: fontSize, rowSize: rowSize)
            }
            .coordinateSpace(.named(space))
            .contentShape(Rectangle())
            .gesture(press)
            .onChange(of: frames[selectedIndex]) { _, frame in park(on: frame) }
            .onChange(of: selection) { park(on: frames[selectedIndex]) }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Palette.ink.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .accessibilityElement(children: .contain)
    }

    // MARK: Parts

    private var labels: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let isSelected = index == selectedIndex

                Text(item.title)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.ink.opacity(0.55))
                    .frame(width: fills ? nil : segmentWidth)
                    .frame(maxWidth: fills ? .infinity : nil)
                    .padding(.horizontal, (segmentWidth == nil && !fills) ? 16 : 0)
                    .padding(.vertical, 6)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: {
                        frames[index] = $0
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = item.value }
            }
        }
        // The glide belongs to the value, not to the click that happened to cause
        // it, so Command-1..4 and the menu bar's mode switch slide as well.
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: selection)
    }

    /// The segments' vertical extent, which the lens and platter share.
    private var band: CGRect { frames[selectedIndex] ?? .zero }

    private var rowSize: CGSize {
        CGSize(width: frames.values.map(\.maxX).max() ?? 0,
               height: frames.values.map(\.maxY).max() ?? 0)
    }

    // MARK: Interaction

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                guard measured else { return }
                let lens = self.lens
                if !lens.pressing {
                    lens.pressing = true
                    lens.pressedAt = Date()
                    if !lens.engaged {
                        // Starts from the platter it lifts out of, wherever the
                        // lens was left last time.
                        park(on: frames[selectedIndex])
                        lens.engaged = true
                    }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                                               : .spring(response: 0.3, dampingFraction: 0.6)) {
                        lens.lift = 1
                    }
                }

                let x = track(value.location.x)
                lens.pointer = value.location.x
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                    lens.x = x
                    lens.width = width(at: x)
                }

                guard !reduceMotion else { return }
                // Stretches along the way it is going, in proportion to speed, and
                // springs back once the pointer stops.
                let stretch = min(abs(value.velocity.width) / 4000, 0.14)
                if abs(stretch - lens.stretch) > 0.004 {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { lens.stretch = stretch }
                }
                lens.lastMove = Date()
                if lens.relax == nil {
                    // One watcher per gesture, not a task per mouse event.
                    lens.relax = Task { @MainActor in
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(40))
                            if lens.stretch > 0, Date().timeIntervalSince(lens.lastMove) > 0.06 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { lens.stretch = 0 }
                            }
                        }
                    }
                }
            }
            .onEnded { value in
                let lens = self.lens
                lens.relax?.cancel()
                lens.relax = nil
                lens.pressing = false
                guard measured else { return }
                let target = nearest(to: value.location.x)
                let frame = frames[target]!
                selection = items[target].value

                withAnimation(.spring(response: 0.36, dampingFraction: 0.76)) {
                    lens.x = frame.midX
                    lens.width = frame.width
                    lens.stretch = 0
                }
                // A quick click still shows the drop lift and land; a long hold
                // settles as soon as it arrives.
                let brief = Date().timeIntervalSince(lens.pressedAt) < 0.18
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(brief ? 0.16 : 0.06)) {
                    lens.lift = 0
                } completion: {
                    if !lens.pressing { lens.engaged = false }
                }
            }
    }

    /// Puts the resting lens on a segment without animating, so the next press
    /// lifts it from the right place.
    private func park(on frame: CGRect?) {
        guard !lens.engaged, let frame else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            lens.x = frame.midX
            lens.width = frame.width
        }
    }

    private var centres: [CGFloat] { (0..<items.count).compactMap { frames[$0]?.midX } }

    /// The pointer's x, held to the first and last segment with some give past them.
    private func track(_ x: CGFloat) -> CGFloat {
        guard let first = centres.first, let last = centres.last else { return x }
        if x < first { return first - min((first - x) * 0.2, 8) }
        if x > last { return last + min((x - last) * 0.2, 8) }
        return x
    }

    /// Lens width at `x`: between two segments of different widths, a blend of both.
    private func width(at x: CGFloat) -> CGFloat {
        let centres = self.centres
        guard centres.count > 1 else { return frames[0]?.width ?? 0 }
        let x = min(max(x, centres.first!), centres.last!)
        var lower = 0
        while lower < centres.count - 2 && x > centres[lower + 1] { lower += 1 }
        let span = centres[lower + 1] - centres[lower]
        let t = span > 0 ? (x - centres[lower]) / span : 0
        return frames[lower]!.width + (frames[lower + 1]!.width - frames[lower]!.width) * t
    }

    private func nearest(to x: CGFloat) -> Int {
        let centres = self.centres
        return centres.indices.min { abs(centres[$0] - x) < abs(centres[$1] - x) } ?? selectedIndex
    }
}

// MARK: - Lens

@Observable
final class LensState {
    var x: CGFloat = 0
    var width: CGFloat = 0
    var lift: CGFloat = 0
    var stretch: CGFloat = 0
    /// From the press until the lens has settled. While engaged the platter rides
    /// with the lens instead of sitting under the selection.
    var engaged = false
    /// Where the pointer is along the row. The glow inside the lens sits here, so
    /// it leads the lens as the lens catches up with the pointer.
    var pointer: CGFloat = 0

    @ObservationIgnored var pressing = false
    @ObservationIgnored var pressedAt = Date.distantPast
    @ObservationIgnored var lastMove = Date.distantPast
    @ObservationIgnored var relax: Task<Void, Never>?

    func geometry(band: CGRect) -> LensGeometry {
        LensGeometry(centreX: x, width: width, lift: lift, stretch: stretch, band: band)
    }
}

/// The labels with the lens's hole cut in them. A view of its own so that the
/// lens moving re-evaluates this and not the labels inside it.
private struct LensCutout<Content: View>: View {
    let lens: LensState
    let band: CGRect
    @ViewBuilder let content: Content

    var body: some View {
        content.modifier(LensHole(geometry: lens.geometry(band: band), active: lens.engaged))
    }
}

/// The glass under the selected label. It fades as the lens lifts out of it and
/// returns as the lens settles, riding with the lens in between so the two are
/// never in different places.
private struct LensPlatter: View {
    let lens: LensState
    let band: CGRect
    let resting: CGRect?
    let selectedIndex: Int

    var body: some View {
        if let rect = lens.engaged ? lens.geometry(band: band).base : resting {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 9, style: .continuous))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .opacity(1 - lens.lift)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: selectedIndex)
        }
    }
}

private struct LensOverlay: View {
    let lens: LensState
    let band: CGRect
    let titles: [String]
    let frames: [Int: CGRect]
    let fontSize: CGFloat
    let rowSize: CGSize

    var body: some View {
        Lens(geometry: lens.geometry(band: band), pointer: lens.pointer, titles: titles, frames: frames,
             fontSize: fontSize, rowSize: rowSize)
    }
}

/// Where the lens is and how far it has lifted, in the row's coordinates.
struct LensGeometry: Equatable {
    var centreX: CGFloat
    var width: CGFloat
    var lift: CGFloat
    var stretch: CGFloat
    /// The segments' vertical extent: the platter's top and height.
    var band: CGRect

    /// Platter-sized, at the lens's position.
    var base: CGRect {
        CGRect(x: centreX - width / 2, y: band.minY, width: width, height: band.height)
    }

    /// The lens itself: grown past the track as it lifts, squashed as it stretches.
    var rect: CGRect {
        let grown = base.insetBy(dx: -4 * lift, dy: -5 * lift)
        let w = grown.width * (1 + stretch), h = grown.height * (1 - stretch * 0.5)
        return CGRect(x: grown.midX - w / 2, y: grown.midY - h / 2, width: w, height: h)
    }

    static let maxMagnification: CGFloat = 1.3
    var magnification: CGFloat { 1 + (Self.maxMagnification - 1) * lift }
    var isVisible: Bool { lift > 0.002 }

    typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    var animatableData: AnimatableData {
        get { .init(.init(centreX, width), .init(lift, stretch)) }
        set {
            centreX = newValue.first.first
            width = newValue.first.second
            lift = newValue.second.first
            stretch = newValue.second.second
        }
    }
}

/// Cuts the labels away where the lens is. The lens shows them itself, magnified;
/// the originals showing through its clear glass would be a double image.
///
/// Animatable, so the hole moves frame by frame with the lens rather than jumping
/// to where the lens is going.
private struct LensHole: ViewModifier, Animatable {
    var geometry: LensGeometry
    let active: Bool

    var animatableData: LensGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        // Only masked while the lens is in play: a mask is an offscreen pass on
        // every redraw, and a resting control has no business paying for one.
        if active {
            content.mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().padding(-40)
                    if geometry.isVisible {
                        let rect = geometry.rect
                        Capsule()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
        } else {
            content
        }
    }
}

/// The lifted drop: shadow, clear glass, the labels seen through it, its glow
/// and its rim.
///
/// An `Animatable` view, so SwiftUI hands it every in-between geometry of an
/// animation and the refracted labels are redrawn in step with the glass around
/// them. Drawn only while lifted; at rest it is nothing.
///
/// Everything but the glass itself is painted in one `Canvas`. As views - a
/// shadow, masks, a dozen strokes - the lens was rebuilt as a view tree on every
/// frame of every animation, and that, not the drawing, was what a drag cost.
private struct Lens: View, Animatable {
    @Environment(\.colorScheme) private var colorScheme
    var geometry: LensGeometry
    let pointer: CGFloat
    let titles: [String]
    let frames: [Int: CGRect]
    let fontSize: CGFloat
    let rowSize: CGSize

    var animatableData: LensGeometry.AnimatableData {
        get { geometry.animatableData }
        set { geometry.animatableData = newValue }
    }

    /// Room around the row for what reaches past it: the lifted lens, its shadow.
    private let margin: CGFloat = 16

    var body: some View {
        if geometry.isVisible {
            let rect = geometry.rect
            ZStack(alignment: .topLeading) {
                Color.clear
                    .glassEffect(.clear, in: Capsule())
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(geometry.lift)

                Canvas { context, _ in
                    context.translateBy(x: margin, y: margin)
                    paint(in: &context, lens: rect)
                } symbols: {
                    // Each label rasterised once, at the lens's full magnification
                    // so it stays sharp when drawn larger, then only scaled and
                    // clipped per frame. Drawing the text itself in every strip
                    // meant typesetting it dozens of times a frame.
                    ForEach(titles.indices, id: \.self) { index in
                        Text(titles[index])
                            .font(.system(size: fontSize * LensGeometry.maxMagnification, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .fixedSize()
                            .tag(index)
                    }
                }
                .frame(width: rowSize.width + margin * 2, height: rowSize.height + margin * 2)
                .offset(x: -margin, y: -margin)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func paint(in context: inout GraphicsContext, lens: CGRect) {
        // Edges fade faster than the glass shrinks, so the landing lens and the
        // platter it becomes never show as two outlines.
        let edges = geometry.lift * geometry.lift
        let outline = Capsule().path(in: lens)

        paintShadow(in: &context, lens: lens, outline: outline, opacity: edges)

        context.drawLayer { layer in
            layer.clip(to: outline)
            paintRefracted(in: &layer, lens: lens)
        }

        context.drawLayer { layer in
            layer.opacity = edges
            layer.clip(to: outline)
            paintGlow(in: &layer, lens: lens)
        }

        context.drawLayer { layer in
            layer.opacity = edges
            paintRim(in: &layer, lens: lens)
        }
    }

    /// Cast on the track below, and kept off the inside of the lens: seen through
    /// clear glass, a shadow underneath reads as a smudge.
    private func paintShadow(in context: inout GraphicsContext, lens: CGRect, outline: Path, opacity: CGFloat) {
        context.drawLayer { layer in
            layer.opacity = opacity
            var outside = Path(CGRect(x: -margin, y: -margin,
                                      width: rowSize.width + margin * 2, height: rowSize.height + margin * 2))
            outside.addPath(outline)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            let box = lens.insetBy(dx: -7, dy: -6).offsetBy(dx: 0, dy: 3)
            let radius = box.height / 2
            layer.translateBy(x: box.midX, y: box.midY)
            layer.scaleBy(x: box.width / box.height, y: 1)
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                                                    location: 0.6),
                                                              .init(color: .black.opacity(0), location: 1)]),
                                             center: .zero, startRadius: 0, endRadius: radius))
        }
    }

    /// The inside of the drop lit up: its inner edge glows the way thick glass
    /// gathers light at its rim, and a soft bloom sits under the pointer - the
    /// response system glass gives to a touch.
    private func paintGlow(in context: inout GraphicsContext, lens: CGRect) {
        // Added light on a dark ground; on a light one, adding light only turns the
        // glass milky, so there it is a much fainter wash.
        let dark = colorScheme == .dark
        context.blendMode = dark ? .plusLighter : .normal

        for step in 0..<3 {
            let inset = 0.75 + CGFloat(step) * 1.5
            context.stroke(Capsule().path(in: lens.insetBy(dx: inset, dy: inset)),
                           with: .color(.white.opacity((dark ? 0.10 : 0.26) * (1 - CGFloat(step) * 0.33))),
                           lineWidth: 1.5)
        }

        let radius = lens.height * 0.8
        let bloomX = min(max(pointer, lens.minX + lens.height * 0.3), lens.maxX - lens.height * 0.3)
        context.fill(Path(ellipseIn: CGRect(x: bloomX - radius, y: lens.midY - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.09 : 0.18), .white.opacity(0)]),
                                           center: CGPoint(x: bloomX, y: lens.midY),
                                           startRadius: 0, endRadius: radius))
    }

    /// The rim: a hairline where the glass meets the track, specular highlights
    /// where light from above-left catches the top-left and bottom-right curves,
    /// and a trace of colour fringing where the edge splits the light.
    private func paintRim(in context: inout GraphicsContext, lens: CGRect) {
        func ring(_ inset: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> Path {
            Capsule().path(in: lens.insetBy(dx: inset, dy: inset).offsetBy(dx: dx, dy: dy))
        }

        // Colour fringe, just outside the rim.
        context.stroke(ring(-1.7, dx: -0.4, dy: -0.3),
                       with: .color(Color(red: 1, green: 0.35, blue: 0.55).opacity(0.22)), lineWidth: 1)
        context.stroke(ring(-1.7, dx: 0.4, dy: 0.3),
                       with: .color(Color(red: 0.3, green: 0.75, blue: 1).opacity(0.22)), lineWidth: 1)

        context.stroke(ring(-0.25), with: .color(.black.opacity(0.32)), lineWidth: 0.5)

        let specular = GraphicsContext.Shading.conicGradient(Gradient(stops: [
            .init(color: .white.opacity(0.15), location: 0.00),   // right
            .init(color: .white.opacity(0.55), location: 0.10),   // lower right
            .init(color: .white.opacity(0.10), location: 0.25),   // bottom
            .init(color: .white.opacity(0.05), location: 0.40),
            .init(color: .white.opacity(0.35), location: 0.50),   // left
            .init(color: .white.opacity(0.95), location: 0.62),   // upper left
            .init(color: .white.opacity(0.70), location: 0.75),   // top
            .init(color: .white.opacity(0.15), location: 0.90),
            .init(color: .white.opacity(0.15), location: 1.00),
        ]), center: CGPoint(x: lens.midX, y: lens.midY))

        // The highlight twice: once broad and faint, as the glow off the curve,
        // once sharp, as the curve itself.
        context.drawLayer { broad in
            broad.opacity = 0.35
            broad.stroke(ring(1.2), with: specular, lineWidth: 2.4)
        }
        context.stroke(ring(0.45), with: specular, lineWidth: 0.9)
    }

    /// Draws the labels as a lens shows them: magnified in the middle, squeezed
    /// towards the rim so that at the rim they meet the labels outside exactly.
    /// A plain magnification would push the letters near the edge out of the lens
    /// and leave a gap in the word.
    ///
    /// No shader: SwiftUI takes Metal shaders only from a compiled library, and
    /// this package builds without the Metal toolchain. The lens is cut into
    /// vertical strips instead, each a straight piece of the same curve - fine
    /// enough that the joins do not show.
    private func paintRefracted(in context: inout GraphicsContext, lens: CGRect) {
        let shrink = 1 / LensGeometry.maxMagnification
        let labels: [(GraphicsContext.ResolvedSymbol, CGRect)] = titles.indices.compactMap { index in
            guard let frame = frames[index], let symbol = context.resolveSymbol(id: index) else { return nil }
            return (symbol, frame)
        }
        func draw(_ context: inout GraphicsContext, from minX: CGFloat, to maxX: CGFloat) {
            for (symbol, frame) in labels where frame.maxX >= minX - 4 && frame.minX <= maxX + 4 {
                let size = CGSize(width: symbol.size.width * shrink, height: symbol.size.height * shrink)
                context.draw(symbol, in: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                                width: size.width, height: size.height))
            }
        }

        let m = geometry.magnification
        guard lens.width > 0, m > 1.001 else {
            draw(&context, from: -.infinity, to: .infinity)
            return
        }
        // Position across the lens, -1...1, to the position it shows.
        func source(_ x: CGFloat) -> CGFloat { x / m + (1 - 1 / m) * x * x * x }
        func slope(_ x: CGFloat) -> CGFloat { 1 / m + 3 * (1 - 1 / m) * x * x }

        let strips = 18
        let half = lens.width / 2
        for strip in 0..<strips {
            let a = -1 + 2 * CGFloat(strip) / CGFloat(strips)
            let b = -1 + 2 * CGFloat(strip + 1) / CGFloat(strips)
            let outX = lens.midX + a * half, outWidth = (b - a) * half
            let srcX = lens.midX + source(a) * half, srcWidth = (source(b) - source(a)) * half
            let scaleX = outWidth / srcWidth
            let scaleY = min(1 / slope((a + b) / 2), m)
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: outX - 0.25, y: lens.minY,
                                           width: outWidth + 0.5, height: lens.height)))
                layer.translateBy(x: outX, y: lens.midY)
                layer.scaleBy(x: scaleX, y: scaleY)
                layer.translateBy(x: -srcX, y: -lens.midY)
                draw(&layer, from: srcX, to: srcX + srcWidth)
            }
        }
    }
}

// MARK: - Previews

extension GlassSegmented {
    /// Holds the lens up at `x`, for previews: a canvas cannot press it.
    fileprivate init(items: [Item], selection: Binding<Value>, segmentWidth: CGFloat?, heldAt x: CGFloat, width: CGFloat) {
        self.items = items
        self._selection = selection
        self.segmentWidth = segmentWidth
        let lens = LensState()
        lens.x = x
        lens.width = width
        lens.lift = 1
        lens.pointer = x
        lens.engaged = true
        self._lens = State(initialValue: lens)
    }
}

#Preview("Segmented lens") {
    let items: [GlassSegmented<Int>.Item] = ["Обзор", "Вентиляторы", "Датчики", "Настройки"]
        .enumerated().map { .init(value: $0.offset, title: $0.element) }
    func rows(_ scheme: ColorScheme, ground: Color) -> some View {
        VStack(spacing: 22) {
            GlassSegmented(items: items, selection: .constant(1), segmentWidth: nil)
            GlassSegmented(items: items, selection: .constant(1), segmentWidth: nil, heldAt: 150, width: 128)
            GlassSegmented(items: items, selection: .constant(1), segmentWidth: nil, heldAt: 215, width: 120)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ground)
        .environment(\.colorScheme, scheme)
    }
    return VStack(spacing: 0) {
        rows(.dark, ground: Color(red: 0.12, green: 0.14, blue: 0.19))
        rows(.light, ground: Color(red: 0.9, green: 0.92, blue: 0.96))
    }
    .frame(width: 520)
}
