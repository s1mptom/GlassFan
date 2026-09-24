import SwiftUI

/// A vertical list whose selection is a drop of glass: the segmented control's drop
/// turned on end, with a tail. Click a row and the drop flows to it - the head goes
/// first and thins with speed, the tail follows on a softer spring, and between two
/// rows the pair necks; on arrival it spreads to the row's full size and settles into
/// a platter. Pick it up and it follows the pointer, sticking to the row it is over.
///
/// The glass is the segmented control's own: the same shader, light and springs.
/// The list draws each row's frame; rows bring only their content.
struct GlassDropList<Row: View>: View {
    let count: Int
    @Binding var selection: Int
    var spacing: CGFloat = 8
    var cornerRadius: CGFloat = 14
    @ViewBuilder let row: (Int) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [Int: CGRect] = [:]
    @State private var size: CGSize = .zero
    @State private var drop = DropListState()
    private let space = "GlassDropList"

    private var rows: [CGRect] { (0..<count).compactMap { frames[$0] } }
    private var measured: Bool { count > 0 && rows.count == count }

    var body: some View {
        DropRefracted(drop: drop, rows: rows, cornerRadius: cornerRadius) {
            VStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    row(index)
                        // Each row's card goes through the glass with it, as a segmented
                        // control's track does: the drop pulls the card's lit edge into
                        // its rim and shows the band inside it. The chosen row is lit
                        // from under, by the platter.
                        .background { RowCard(cornerRadius: cornerRadius) }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: {
                            frames[index] = $0
                        }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        }
        .background(alignment: .topLeading) {
            DropGlass(drop: drop, rows: rows, resting: frames[selection], cornerRadius: cornerRadius,
                      size: size, selection: selection)
        }
        .overlay(alignment: .topLeading) {
            DropLight(drop: drop, rows: rows, size: size)
        }
        .coordinateSpace(.named(space))
        .simultaneousGesture(press)
        .onChange(of: count) { frames = frames.filter { $0.key < count } }
        // Chosen from elsewhere - a number on the plot - it flows there as well.
        .onChange(of: selection) { old, new in
            guard measured, !drop.engaged, let from = frames[old], new < count else { return }
            flow(from: from, to: new)
        }
        .onAppear { drop.rowRadius = cornerRadius }
    }

    // MARK: Interaction

    /// A press lifts the drop. A click sends it to the clicked row; a drag on the
    /// selected row picks it up. The choice is made when the drop arrives.
    ///
    /// Choosing waits for arrival for the segmented control's reason: choosing
    /// re-draws what depends on it, and nothing moves while that happens.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                guard measured, let current = frames[selection] else { return }
                let rows = self.rows
                if !drop.pressing {
                    begin(from: current)
                    drop.pressing = true
                    drop.target = DropListMath.owner(of: value.startLocation.y, in: rows)
                    drop.grabOffset = value.startLocation.y - drop.headY.value
                }
                drop.pointer = value.location
                if !drop.dragging {
                    // Only the drop itself is picked up; a drag that starts on another
                    // row is a click on that row.
                    guard abs(value.translation.height) > 4,
                          DropListMath.owner(of: value.startLocation.y, in: rows) == selection else { return }
                    drop.dragging = true
                }
                drop.held = value.location.y - drop.grabOffset
            }
            .onEnded { _ in
                drop.pressing = false
                guard measured else {
                    // The rows changed under the press - a curve removed by its own
                    // button. There is nowhere to land; put the drop down.
                    drop.held = nil
                    drop.dragging = false
                    drop.onArrival = nil
                    drop.engaged = false
                    return
                }
                if drop.dragging {
                    drop.target = DropListMath.owner(of: drop.headY.value, in: rows)
                    drop.held = nil
                    drop.dragging = false
                }
                arrive()
            }
    }

    private func begin(from frame: CGRect) {
        drop.dragging = false
        drop.held = nil
        drop.token += 1
        drop.onArrival = nil
        drop.onSettled = nil
        if !drop.engaged { drop.engage(at: frame) }
        drop.lift.tune(response: reduceMotion ? 0.2 : 0.3, dampingFraction: reduceMotion ? 1 : 0.7)
        drop.lift.target = 1
    }

    private func flow(from frame: CGRect, to index: Int) {
        begin(from: frame)
        drop.target = index
        drop.pointer = CGPoint(x: frame.midX, y: frames[index]?.midY ?? frame.midY)
        arrive()
    }

    private func arrive() {
        let drop = self.drop
        let token = drop.token, target = drop.target
        drop.onArrival = { land(on: target, token: token) }
        // Springs only step while the drop is drawn. Should it stop being drawn, the
        // choice still counts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard drop.token == token, let arrival = drop.onArrival else { return }
            drop.onArrival = nil
            arrival()
        }
    }

    /// Makes the choice, then lets the drop settle back into a platter.
    private func land(on index: Int, token: Int) {
        let drop = self.drop
        guard drop.token == token, !drop.pressing else { return }
        if index != selection, index < count { withoutImplicitAnimation { selection = index } }
        // Down fast and without a bounce: Apple's drop is back in its platter some
        // 60 ms after it is let go; ours took half a second, and read as sinking.
        drop.lift.tune(response: 0.12, dampingFraction: 1)
        drop.lift.target = 0
        drop.onSettled = {
            if drop.token == token, !drop.pressing {
                withoutImplicitAnimation { drop.engaged = false }
            }
        }
    }
}

// MARK: - State

/// The drop's springs: a head and a tail, each with a position and a size, and the lift.
@Observable
final class DropListState {
    /// From the press until the drop has settled. Only then is it drawn and stepped.
    var engaged = false

    @ObservationIgnored var headY = LensSpring()
    @ObservationIgnored var headW = LensSpring()
    @ObservationIgnored var headH = LensSpring()
    @ObservationIgnored var tailY = LensSpring()
    @ObservationIgnored var tailW = LensSpring()
    @ObservationIgnored var tailH = LensSpring()
    @ObservationIgnored var lift = LensSpring()
    @ObservationIgnored var x: CGFloat = 0
    @ObservationIgnored var rowRadius: CGFloat = 14

    @ObservationIgnored var pressing = false
    @ObservationIgnored var dragging = false
    /// Where the pointer holds the head, while it is held.
    @ObservationIgnored var held: CGFloat?
    @ObservationIgnored var grabOffset: CGFloat = 0
    @ObservationIgnored var pointer: CGPoint = .zero
    /// The row the drop is headed for.
    @ObservationIgnored var target = 0
    /// Bumped by every press, so that a landing or settling left over from an
    /// earlier one leaves the current one alone.
    @ObservationIgnored var token = 0
    @ObservationIgnored var onArrival: (() -> Void)?
    @ObservationIgnored var onSettled: (() -> Void)?
    @ObservationIgnored private var clock = FrameClock()
    /// Held still where it was put, for previews: a canvas cannot press it.
    @ObservationIgnored var frozen = false
    /// 0 while the drop sits on its row, 1 while it travels to another. Thinning, the
    /// tail and the rounding belong to travel only: applied to a drop merely leaning
    /// towards the pointer on its own row, a narrower head over a lagging, wider tail
    /// came out as a rectangle with lumps on top and bottom.
    @ObservationIgnored private(set) var travel: CGFloat = 0
    /// The size and middle of the row the drop is on or making for.
    @ObservationIgnored private var goalSize: CGSize = .zero
    @ObservationIgnored private var goalMid: CGFloat = 0

    init() {
        // The head leaves first and a little lively; the tail chases it, softer.
        headY.tune(response: 0.35, dampingFraction: 0.78)
        tailY.tune(response: 0.51, dampingFraction: 0.95)
        headW.tune(response: 0.24, dampingFraction: 0.9)
        headH.tune(response: 0.28, dampingFraction: 0.8)
        tailW.tune(response: 0.28, dampingFraction: 0.9)
        tailH.tune(response: 0.31, dampingFraction: 0.85)
    }

    /// Lifts off from a platter sitting on `frame`.
    func engage(at frame: CGRect) {
        x = frame.midX
        goalSize = frame.size
        travel = 0
        headY.jump(to: frame.midY)
        tailY.jump(to: frame.midY)
        headW.jump(to: frame.width)
        tailW.jump(to: frame.width)
        headH.jump(to: frame.height)
        tailH.jump(to: frame.height)
        lift.jump(to: 0)
        pointer = CGPoint(x: frame.midX, y: frame.midY)
        clock.reset()
        engaged = true
    }

    /// How far the drop stands past its row on every side once it is up.
    static let grow: CGFloat = 6

    /// `now` is the process's uptime, for the frame clock; tests pass their own.
    func geometry(at date: Date, rows: [CGRect],
                  now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> DropGeometry {
        advance(to: date.timeIntervalSinceReferenceDate, rows: rows, now: now)
        let up = max(lift.value, 0)
        let t = travel
        // At rest on its row the drop is the row's shape, whole; travelling, it takes
        // the springs' thinner, drawn-out shape. Blended, so neither switch is seen.
        func size(_ spring: LensSpring, _ whole: CGFloat) -> CGFloat {
            whole + (spring.value - whole) * t
        }
        // The row's own size, not grown past it as the segmented drop grows past its
        // track: grown, it read as a drop over a frame rather than the frame lifting.
        // Grown as it lifts: a drop of glass stands past the platter it rose from.
        let grow = Self.grow * min(up, 1)
        func box(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x - w / 2 - grow, y: y - h / 2 - grow, width: w + grow * 2, height: h + grow * 2)
        }
        let head = box(headY.value, size(headW, goalSize.width), size(headH, goalSize.height))
        let tail = box(headY.value + (tailY.value - headY.value) * t,
                       size(tailW, goalSize.width), size(tailH, goalSize.height))
        let speed = max(abs(headY.velocity), abs(tailY.velocity))
        // The bridge is cut from the drop's thickness, not its width. From the width it
        // came out fatter than a short row is tall, and stood out above and below the
        // drop as two round lumps.
        let thickness = min(head.width, head.height, tail.width, tail.height)
        return DropGeometry(
            head: head,
            tail: tail,
            cornerRadius: rowRadius + (DropListMath.cornerRadius(rest: rowRadius, speed: speed) - rowRadius) * t,
            neck: abs(head.midY - tail.midY) > 2 ? thickness * 0.3 : 0,
            lift: up,
            motion: min(max(headY.velocity / 1200, -1), 1),
            maxMagnification: 1.08)
    }

    /// Brings the springs up to `time`, once a frame - see `FrameClock`.
    private func advance(to time: TimeInterval, rows: [CGRect], now: TimeInterval) {
        guard !frozen, !rows.isEmpty, let step = clock.advance(to: time, now: now) else { return }
        for _ in 0..<step.count {
            let goalY: CGFloat
            let goal: CGRect
            if let held {
                let clamped = min(max(held, rows.first!.midY), rows.last!.midY)
                goalY = DropListMath.stick(clamped, in: rows)
                goal = rows[DropListMath.owner(of: clamped, in: rows)]
            } else {
                goal = rows[min(target, rows.count - 1)]
                goalY = goal.midY
            }
            headY.target = goalY
            headY.step(step.dt)
            // The tail chases the head, never the goal: that lag is the stretch.
            tailY.target = headY.value
            tailY.step(step.dt)
            let head = DropListMath.thinned(goal.size, speed: headY.velocity,
                                            gapness: DropListMath.gapness(at: headY.value, in: rows))
            let tail = DropListMath.thinned(goal.size, speed: tailY.velocity,
                                            gapness: DropListMath.gapness(at: tailY.value, in: rows))
            headW.target = head.width
            headH.target = head.height
            tailW.target = tail.width
            tailH.target = tail.height
            headW.step(step.dt)
            headH.step(step.dt)
            tailW.step(step.dt)
            tailH.step(step.dt)
            lift.step(step.dt)

            // Travelling once the head is more than a few points off where it is going.
            goalSize = goal.size
            goalMid = goal.midY
            let away = abs(headY.value - goalY)
            let wanted = min(max((away - 6) / 18, 0), 1)
            travel += (wanted - travel) * min(step.dt * 18, 1)
            // Home is home: an easing that only approaches left the tail a hair off its
            // head for a second after every move, and the drop's light read that as
            // drawn out.
            if wanted == 0, travel < 0.01 { travel = 0 }
        }

        // Handed to the next turn of the run loop: they change state, and this runs
        // while the drop's views are being drawn. Arrived once within a point and a
        // half: the rest of a spring's approach is too small to see.
        let still = [headY, tailY, headW, headH, tailW, tailH].allSatisfy { $0.isResting(within: 1.5) }
        // Arrived once its head is over the middle half of the row it is making for. It
        // used to wait for every spring to come to rest - the lazy tail's included - and
        // the choice changed most of a second after the click; the drop finishes
        // flowing and settles after the choice, not before it.
        if let arrival = onArrival, held == nil, abs(headY.value - goalMid) <= max(goalSize.height / 4, 1.5) {
            onArrival = nil
            DispatchQueue.main.async(execute: arrival)
        }
        if let settled = onSettled, lift.target == 0, lift.isResting(within: 0.004), still {
            onSettled = nil
            DispatchQueue.main.async(execute: settled)
        }
    }
}

// MARK: - Parts

/// The rows, refracted where the drop is. A view of its own so that the drop moving
/// re-draws this and not the rows inside it.
private struct DropRefracted<Content: View>: View {
    let drop: DropListState
    let rows: [CGRect]
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !drop.engaged)) { context in
            // A row's text starts at its left, so it grows from there: grown about the
            // drop's middle it slid a few points into the card's edge, where the glass
            // stops growing anything so that the card's corners stay round, and was cut.
            content.modifier(GlassDropRefraction(geometry: drop.engaged
                                                     ? drop.geometry(at: context.date, rows: rows) : nil,
                                                 reach: CGSize(width: 48, height: 48),
                                                 tracks: rows, trackRadius: cornerRadius,
                                                 anchors: rows.first.map { [$0.minX] } ?? []))
        }
    }
}

/// Under the rows: the platter on the selected row at rest, and in play the drop's own
/// glass - one body. The platter does not ride along under the drop as a shape of its
/// own: it *is* the drop, the same outline, its glass going from the platter's frosted
/// kind to the lens's clear kind as it lifts and back as it lands. At rest the drop's
/// outline is the row's own, so it lifts out of the platter and settles into the next
/// one rather than carrying a frame about underneath it.
private struct DropGlass: View {
    let drop: DropListState
    let rows: [CGRect]
    let resting: CGRect?
    let cornerRadius: CGFloat
    let size: CGSize
    let selection: Int

    var body: some View {
        if drop.engaged {
            TimelineView(.animation) { context in
                let geometry = drop.geometry(at: context.date, rows: rows)
                let lift = min(geometry.lift, 1)
                // The ends only. The shader melts the bridge between them into a curve
                // no path here follows, and system glass cut to a straight bridge
                // showed as a dark bar across the neck.
                // The row's platter fades as the drop lifts out of it; what is under a
                // lifted drop is the ground and the rim.
                let platter = DropOutline(geometry: geometry.insetBy(DropListState.grow * lift), bridged: false)
                RowHighlight(shape: platter)
                    .frame(width: size.width, height: size.height)
                    .opacity(1 - lift)
            }
        } else if let resting {
            platter(resting)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selection)
        }
    }

    private func platter(_ rect: CGRect) -> some View {
        RowHighlight(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// What lights the chosen row from under its card: its own light, not system glass.
/// Glass takes its tone from whatever is behind the window, and on another Mac's
/// wallpaper the chosen row came out darker than the rest instead of lighter.
private struct RowHighlight<S: Shape>: View {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S

    var body: some View {
        shape.fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.55))
    }
}

/// A row's card. On dark ground it is a segmented control's track as Apple draws it,
/// in white over the window, a fifth darker: filled at 10%, its top edge lit (30%, 21%,
/// 14%, falling to the fill over some 3pt), a glow along the bottom and the bottom edge
/// at 31%, and down its sides a dark hairline - what the drop's rim is made of. On light
/// ground, as Apple's track is there: a faint grey inside and an outline of 5% black.
private struct RowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    /// The top edge and the bottom, every half point from the edge in, as levels over
    /// a ground of 38 - read off Activity Monitor's track.
    private static let top: [Double] = [119, 94, 77, 74, 72, 70, 69, 68, 68, 67]
    private static let bottom: [Double] = [123, 96, 79, 76, 74, 72, 71, 70, 70, 69, 69, 68]
    private static let fill: Double = 66.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if colorScheme == .dark {
            GeometryReader { geometry in
                shape.fill(LinearGradient(stops: Self.stops(height: geometry.size.height),
                                          startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(stops: [
                        .init(color: .clear, location: 0.06),
                        .init(color: .black.opacity(0.35), location: 0.3),
                        .init(color: .black.opacity(0.4), location: 0.5),
                        .init(color: .black.opacity(0.35), location: 0.7),
                        .init(color: .clear, location: 0.94),
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
            }
        } else {
            // The track in the light appearance: a faint grey inside, an outline of 5%.
            shape.fill(Color.black.opacity(0.012))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.045), .black.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
        }
    }

    /// A row a fifth darker than Apple's track, so the chosen one can be lighter.
    private static let tone = 0.8

    private static func white(_ level: Double) -> Color { .white.opacity((level - 38) / (255 - 38) * tone) }

    private static func stops(height: CGFloat) -> [Gradient.Stop] {
        let h = max(Double(height), 12)
        var stops: [Gradient.Stop] = []
        for (i, level) in top.enumerated() {
            stops.append(.init(color: white(level), location: (Double(i) * 0.5 + 0.25) / h))
        }
        stops.append(.init(color: white(fill), location: min(6 / h, 0.45)))
        stops.append(.init(color: white(fill), location: max(1 - 7 / h, 0.55)))
        for (i, level) in bottom.enumerated().reversed() {
            stops.append(.init(color: white(level), location: 1 - (Double(i) * 0.5 + 0.25) / h))
        }
        return stops
    }
}

private struct DropLight: View {
    let drop: DropListState
    let rows: [CGRect]
    let size: CGSize

    var body: some View {
        if drop.engaged {
            TimelineView(.animation) { context in
                let geometry = drop.geometry(at: context.date, rows: rows)
                GlassDropLight(geometry: geometry, pointer: drop.pointer, size: size)
            }
        }
    }
}

// MARK: - Preview

extension GlassDropList {
    /// Holds the drop mid-flight from `from` towards `to`, for previews.
    fileprivate init(count: Int, selection: Binding<Int>, midFlightFrom from: CGRect, to: CGRect,
                     @ViewBuilder row: @escaping (Int) -> Row) {
        self.count = count
        self._selection = selection
        self.row = row
        let drop = DropListState()
        drop.engage(at: from)
        drop.headY.jump(to: to.midY - 6)
        drop.tailY.jump(to: from.midY + 10)
        drop.headW.jump(to: to.width * 0.34)
        drop.headH.jump(to: to.height * 0.7)
        drop.tailW.jump(to: from.width * 0.5)
        drop.tailH.jump(to: from.height * 0.7)
        drop.lift.jump(to: 1)
        drop.headY.velocity = 600
        drop.tailY.velocity = 380
        drop.pointer = CGPoint(x: to.midX, y: to.midY)
        drop.frozen = true
        self._drop = State(initialValue: drop)
    }
}

private struct DropListPreviewRow: View {
    let index: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Group \(index + 1)").font(.system(size: 12, weight: .medium))
            Text(index == 0 ? "Palm rest L · Palm rest R" : index == 1 ? "CPU P-cores · CPU E-cores" : "GPU")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: index == 0 ? 60 : 44, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

#Preview("Glass drop list · in flight") {
    func column(_ scheme: ColorScheme, ground: Color) -> some View {
        HStack(alignment: .top, spacing: 24) {
            GlassDropList(count: 3, selection: .constant(0)) { DropListPreviewRow(index: $0) }
            GlassDropList(count: 3, selection: .constant(0),
                          midFlightFrom: CGRect(x: 0, y: 0, width: 200, height: 60),
                          to: CGRect(x: 0, y: 68, width: 200, height: 44)) { DropListPreviewRow(index: $0) }
        }
        .frame(width: 424)
        .padding(24)
        .background(ground)
        .environment(\.colorScheme, scheme)
    }
    return VStack(spacing: 0) {
        column(.dark, ground: Color(red: 0.12, green: 0.14, blue: 0.19))
        column(.light, ground: Color(red: 0.9, green: 0.92, blue: 0.96))
    }
}

#Preview("Glass drop list") {
    @Previewable @State var selection = 0
    GlassDropList(count: 3, selection: $selection) { index in
        Text("Group \(index + 1)")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: index == 0 ? 64 : 40, alignment: .leading)
            .padding(.horizontal, 10)
    }
    .frame(width: 184)
    .padding(24)
    .background(Color(red: 0.12, green: 0.14, blue: 0.19))
}
