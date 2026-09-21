import SwiftUI

/// Segmented control whose selection is a drop of glass you can pick up.
///
/// At rest the selection is a glass platter under its label. Press anywhere on the
/// control and the platter lifts into a lens - larger than the track, magnifying
/// what is under it - which follows the pointer, stretches with speed, and on
/// release glides to the nearest segment and settles back into a platter. This is
/// the lens iOS 26 gives its segmented controls and tab bars; macOS gives it only
/// to sliders and switches, and not as anything an app can borrow, so it is built
/// here: system glass for the body, a Metal shader for the refraction, and the
/// light on it painted.
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

    /// The drop: its springs, and whether it is in play. An object rather than
    /// this view's state, so moving it re-draws the lens and not the control.
    @State private var lens = LensState()

    private let space = "GlassSegmented"

    private var selectedIndex: Int { items.firstIndex { $0.value == selection } ?? 0 }
    private var measured: Bool { frames.count == items.count }

    var body: some View {
        // The track's outline goes through the lens with the labels, so the drop
        // bends it where the two cross; its fill stays under the platter.
        LensRefracted(lens: lens, band: band) {
            labels
                .padding(3)
                // The ground goes through the lens with the labels, so the drop bends
                // the track's own edges where its rim crosses them.
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.ink.opacity(0.06))
                )
                .overlay(
                    // A bright top edge, as the system's own track has, which the drop's
                    // bevel draws out into its coloured line.
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Palette.ink.opacity(0.22), Palette.ink.opacity(0.06)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
        }
        .background(alignment: .topLeading) {
            LensBackground(lens: lens, band: band, resting: frames[selectedIndex], selectedIndex: selectedIndex)
        }
        .overlay(alignment: .topLeading) {
            LensOverlay(lens: lens, band: band, rowSize: rowSize)
        }
        .coordinateSpace(.named(space))
        .contentShape(Rectangle())
        .gesture(press)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selection)
    }

    /// The segments' vertical extent, which the lens and platter share.
    private var band: CGRect { frames[selectedIndex] ?? .zero }

    private var rowSize: CGSize {
        CGSize(width: frames.values.map(\.maxX).max() ?? 0,
               height: frames.values.map(\.maxY).max() ?? 0)
    }

    // MARK: Interaction

    /// A press lifts the drop. A click glides it to the clicked segment in one
    /// unbroken move; a drag has it follow the pointer. The choice is made when the
    /// drop arrives, and only then does it settle.
    ///
    /// Choosing waits for arrival because choosing is expensive - picking a screen
    /// builds it, and nothing moves while it builds. Chosen on release, mid-flight,
    /// that stalled the drop a tenth of a second short of its target.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                guard measured else { return }
                let lens = self.lens
                if !lens.pressing {
                    lens.pressing = true
                    lens.dragging = false
                    lens.token += 1
                    lens.onArrival = nil
                    lens.onSettled = nil
                    if !lens.engaged, let frame = frames[selectedIndex] {
                        lens.engage(at: frame)
                    }
                    lens.stretches = !reduceMotion
                    lens.lift.tune(response: reduceMotion ? 0.2 : 0.3, dampingFraction: reduceMotion ? 1 : 0.7)
                    lens.lift.target = 1
                    let pressed = nearest(to: value.location.x)
                    lens.target = pressed
                    glide(to: pressed)
                }

                // Not a drag until the pointer has really moved; until then the
                // glide the press started runs undisturbed.
                if !lens.dragging {
                    guard abs(value.translation.width) > 4 else { return }
                    lens.dragging = true
                    // Close behind the pointer, and stopping where it stops: an
                    // overshoot here reads as the drop sliding past the finger.
                    lens.x.tune(response: 0.2, dampingFraction: 0.9)
                    lens.width.tune(response: 0.2, dampingFraction: 0.9)
                }
                let x = track(value.location.x)
                lens.pointer = value.location.x
                lens.x.target = x
                lens.width.target = width(at: x)
            }
            .onEnded { value in
                let lens = self.lens
                lens.pressing = false
                guard measured else { return }
                if lens.dragging {
                    let target = nearest(to: value.location.x)
                    let frame = frames[target]!
                    lens.target = target
                    // Lands without a bounce: released past a segment's middle it
                    // has to travel back to it, and an overshoot on top of that
                    // looks like it missed twice.
                    lens.x.tune(response: 0.26, dampingFraction: 1)
                    lens.width.tune(response: 0.26, dampingFraction: 1)
                    lens.x.target = frame.midX
                    lens.width.target = frame.width
                }
                // A click's glide may still be under way; either way the drop
                // lands when it gets there.
                let token = lens.token
                let target = lens.target
                lens.onArrival = { land(on: target, token: token) }
                // Springs only step while the lens is drawn. Should it stop being
                // drawn - the panel it sits in closing - the choice still counts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard lens.token == token, let arrival = lens.onArrival else { return }
                    lens.onArrival = nil
                    arrival()
                }
            }
    }

    /// One continuous move to a clicked segment, easing out of where the drop is
    /// and easing into where it is going, a little longer for a longer way.
    private func glide(to index: Int) {
        let frame = frames[index]!
        let distance = abs(frame.midX - lens.x.value)
        let response = reduceMotion ? 0.2 : min(0.22 + distance / 2400, 0.34)
        lens.x.tune(response: response, dampingFraction: 1)
        lens.width.tune(response: response, dampingFraction: 1)
        lens.x.target = frame.midX
        lens.width.target = frame.width
        lens.pointer = frame.midX
    }

    /// Makes the choice, then lets the drop settle back into a platter.
    private func land(on index: Int, token: Int) {
        let lens = self.lens
        guard lens.token == token, !lens.pressing else { return }
        if items[index].value != selection {
            withoutImplicitAnimation { selection = items[index].value }
        }
        lens.lift.tune(response: 0.36, dampingFraction: 0.9)
        lens.lift.target = 0
        lens.onSettled = {
            if lens.token == token, !lens.pressing { withoutImplicitAnimation { lens.engaged = false } }
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
    /// From the press until the drop has settled. Only then is the lens drawn and
    /// its springs stepped; the rest of the time it does not exist.
    var engaged = false

    @ObservationIgnored var x = LensSpring()
    @ObservationIgnored var width = LensSpring()
    @ObservationIgnored var lift = LensSpring()
    @ObservationIgnored var stretch = LensSpring()
    /// Where the pointer is along the row. The glow inside the lens sits here, so
    /// it leads the lens as the lens catches up with the pointer.
    @ObservationIgnored var pointer: CGFloat = 0
    @ObservationIgnored var stretches = true

    @ObservationIgnored var pressing = false
    @ObservationIgnored var dragging = false
    /// The segment the drop is headed for.
    @ObservationIgnored var target = 0
    /// Bumped by every press, so that a landing or settling left over from an
    /// earlier one leaves the current one alone.
    @ObservationIgnored var token = 0
    @ObservationIgnored var onArrival: (() -> Void)?
    @ObservationIgnored var onSettled: (() -> Void)?
    @ObservationIgnored private var clock = FrameClock()

    init() {
        stretch.tune(response: 0.26, dampingFraction: 0.5)
    }

    /// Lifts off from a platter sitting on `frame`.
    func engage(at frame: CGRect) {
        x.jump(to: frame.midX)
        width.jump(to: frame.width)
        lift.jump(to: 0)
        stretch.jump(to: 0)
        pointer = frame.midX
        clock.reset()
        engaged = true
    }

    func geometry(at date: Date, band: CGRect) -> LensGeometry {
        advance(to: date.timeIntervalSinceReferenceDate)
        return LensGeometry(centreX: x.value, width: width.value, lift: max(lift.value, 0),
                            stretch: stretch.value, grow: CGSize(width: LensTuning.shared.growX, height: LensTuning.shared.growY),
                            motion: min(max(x.velocity / 1200, -1), 1), band: band)
    }

    /// Brings the springs up to `time`, once a frame - see `FrameClock`.
    private func advance(to time: TimeInterval) {
        guard let step = clock.advance(to: time) else { return }
        let dt = step.dt
        for _ in 0..<step.count {
            x.step(dt)
            width.step(dt)
            lift.step(dt)
            // Drawn out along the way it moves, in proportion to its speed.
            stretch.target = stretches ? min(abs(x.velocity) / 2600, 0.14) : 0
            stretch.step(dt)
        }

        // Handed to the next turn of the run loop: they change state, and this
        // runs while the lens's views are being drawn.
        // Arrived once over the middle half of the segment it is making for: the choice
        // is plain by then, and what is left of the glide - a tenth of a second or more
        // of a spring's approach - was being waited out before anything changed. The
        // drop finishes its glide and settles after the choice, not before it.
        if let arrival = onArrival, abs(x.value - x.target) <= max(width.target / 4, 1.5) {
            onArrival = nil
            DispatchQueue.main.async(execute: arrival)
        }
        if let settled = onSettled, lift.target == 0, lift.isResting(within: 0.004),
           stretch.isResting(within: 0.004) {
            onSettled = nil
            DispatchQueue.main.async(execute: settled)
        }
    }
}

/// The labels, refracted where the lens is. A view of its own so that the lens
/// moving re-draws this and not the labels inside it.
private struct LensRefracted<Content: View>: View {
    let lens: LensState
    let band: CGRect
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !lens.engaged)) { context in
            content.modifier(GlassDropRefraction(geometry: lens.engaged ? lens.geometry(at: context.date, band: band).drop : nil))
        }
    }
}

/// Under the labels: the platter, and the drop's own glass. System glass laid over
/// the labels frosts them, where a lens has to show them sharp.
///
/// The platter sits under the selected label at rest. Once the drop is in play it
/// rides with the drop and fades as the drop lifts out of it, so the two are never
/// in different places.
private struct LensBackground: View {
    let lens: LensState
    let band: CGRect
    let resting: CGRect?
    let selectedIndex: Int

    var body: some View {
        if lens.engaged {
            TimelineView(.animation) { context in
                let geometry = lens.geometry(at: context.date, band: band)
                let base = geometry.base
                let rect = geometry.rect
                // The platter fades as the drop lifts out of it: under Apple's lifted
                // drop there is only the ground and the rim.
                platter(base).opacity(1 - min(geometry.lift, 1))
            }
        } else if let resting {
            platter(resting)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedIndex)
        }
    }

    private func platter(_ rect: CGRect) -> some View {
        Color.clear
            .glassEffect(.regular, in: .rect(cornerRadius: 9, style: .continuous))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

private struct LensOverlay: View {
    let lens: LensState
    let band: CGRect
    let rowSize: CGSize

    var body: some View {
        if lens.engaged {
            TimelineView(.animation) { context in
                let geometry = lens.geometry(at: context.date, band: band)
                GlassDropLight(geometry: geometry.drop,
                               pointer: CGPoint(x: lens.pointer, y: geometry.rect.midY),
                               size: rowSize)
            }
        }
    }
}

/// Where the lens is and how far it has lifted, in the row's coordinates.
struct LensGeometry: Equatable {
    var centreX: CGFloat
    var width: CGFloat
    var lift: CGFloat
    var stretch: CGFloat
    /// How far past the platter the drop stands when up: 4pt past the track.
    var grow = CGSize(width: 12, height: 10)
    /// Horizontal speed, -1...1: the light on the glass swings with it and its
    /// colours part further.
    var motion: CGFloat = 0
    /// The segments' vertical extent: the platter's top and height.
    var band: CGRect

    /// Platter-sized, at the lens's position.
    var base: CGRect {
        CGRect(x: centreX - width / 2, y: band.minY, width: width, height: band.height)
    }

    /// The lens itself: grown past the track as it lifts, drawn out as it moves.
    var rect: CGRect {
        // Past the track by 4pt, as Apple's drop stands past its track; the base is
        // the platter, 3pt inside the track.
        let grown = base.insetBy(dx: -grow.width * lift, dy: -grow.height * lift)
        let w = grown.width * (1 + stretch), h = grown.height * (1 - stretch * 0.5)
        return CGRect(x: grown.midX - w / 2, y: grown.midY - h / 2, width: w, height: h)
    }

    /// The lens as the shared glass draws it: a capsule.
    var drop: DropGeometry { .capsule(rect, lift: lift, motion: motion) }
}

// MARK: - Previews

extension GlassSegmented {
    /// Holds the lens up at `x`, for previews: a canvas cannot press it.
    fileprivate init(items: [Item], selection: Binding<Value>, segmentWidth: CGFloat?, heldAt x: CGFloat, width: CGFloat) {
        self.items = items
        self._selection = selection
        self.segmentWidth = segmentWidth
        let lens = LensState()
        lens.x.jump(to: x)
        lens.width.jump(to: width)
        lens.lift.jump(to: 1)
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

