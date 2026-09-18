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
        DropRefracted(drop: drop, rows: rows) {
            VStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    row(index)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: {
                            frames[index] = $0
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            if DropScript.isEnabled { DropScript.rows[index] = $0 }
                        }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        }
        .background(alignment: .topLeading) {
            DropGlass(drop: drop, rows: rows, resting: frames[selection], cornerRadius: cornerRadius,
                      size: size, selection: selection)
        }
        // Each row's frame, under the glass rather than in the rows. Drawn in the rows,
        // it went through the lens with them and came out magnified inside the drop.
        // And where the drop is, the frame is not: the chosen row's frame *is* the drop,
        // so a row's frame fades as the drop covers it and comes back as it leaves.
        .background(alignment: .topLeading) {
            DropFrames(drop: drop, rows: rows, selection: selection, cornerRadius: cornerRadius)
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
        if DropScript.isEnabled { DropScript.log("land on \(index)") }
        if index != selection, index < count { withoutImplicitAnimation { selection = index } }
        drop.lift.tune(response: 0.36, dampingFraction: 0.9)
        drop.lift.target = 0
        drop.onSettled = {
            if drop.token == token, !drop.pressing {
                if DropScript.isEnabled { DropScript.log("settled") }
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
    /// The size of the row the drop is on or making for.
    @ObservationIgnored private var goalSize: CGSize = .zero

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
        func box(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
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
            let away = abs(headY.value - goalY)
            let wanted = min(max((away - 6) / 18, 0), 1)
            travel += (wanted - travel) * min(step.dt * 18, 1)
        }

        if DropScript.isEnabled {
            DropScript.log(String(format: "drop head %.1f %.0fx%.0f tail %.1f %.0fx%.0f lift %.2f held %@ target %d",
                                  headY.value, headW.value, headH.value, tailY.value, tailW.value, tailH.value,
                                  lift.value, held.map { String(format: "%.1f", $0) } ?? "-", target))
        }

        // Handed to the next turn of the run loop: they change state, and this runs
        // while the drop's views are being drawn. Arrived once within a point and a
        // half: the rest of a spring's approach is too small to see.
        let still = [headY, tailY, headW, headH, tailW, tailH].allSatisfy { $0.isResting(within: 1.5) }
        if let arrival = onArrival, held == nil, still {
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
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !drop.engaged)) { context in
            content.modifier(GlassDropRefraction(geometry: drop.engaged && !DropScript.off.contains("lens")
                                                     ? drop.geometry(at: context.date, rows: rows) : nil,
                                                 reach: CGSize(width: 48, height: 48)))
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
        if drop.engaged, !DropScript.off.contains("glass") {
            TimelineView(.animation) { context in
                let geometry = drop.geometry(at: context.date, rows: rows)
                let lift = min(geometry.lift, 1)
                // The ends only. The shader melts the bridge between them into a curve
                // no path here follows, and system glass cut to a straight bridge
                // showed as a dark bar across the neck.
                let outline = DropOutline(geometry: geometry, bridged: false)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: size.width, height: size.height)
                        .glassEffect(.regular, in: outline)
                        .opacity(1 - lift)
                    Color.clear
                        .frame(width: size.width, height: size.height)
                        .glassEffect(.clear, in: outline)
                        .opacity(lift)
                }
            }
        } else if let resting {
            platter(resting)
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selection)
        }
    }

    private func platter(_ rect: CGRect) -> some View {
        Color.clear
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// The rows' frames, each faded by how much of it the drop covers - so the drop never
/// sits over a frame of its own shape, and settles into a row by taking its frame's place.
private struct DropFrames: View {
    let drop: DropListState
    let rows: [CGRect]
    let selection: Int
    let cornerRadius: CGFloat

    var body: some View {
        if drop.engaged {
            TimelineView(.animation) { context in
                let bounds = drop.geometry(at: context.date, rows: rows).bounds
                frames { index in 1 - min(Self.coverage(of: rows[index], by: bounds) * 1.4, 1) }
            }
        } else {
            frames { index in index == selection ? 0 : 1 }
        }
    }

    private func frames(_ opacity: @escaping (Int) -> CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, frame in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.ink.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.07), lineWidth: 0.5))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(opacity(index))
            }
        }
    }

    /// The share of `row` inside `drop`, 0...1.
    static func coverage(of row: CGRect, by drop: CGRect) -> CGFloat {
        let overlap = row.intersection(drop)
        guard !overlap.isNull, row.width > 0, row.height > 0 else { return 0 }
        return (overlap.width * overlap.height) / (row.width * row.height)
    }
}

private struct DropLight: View {
    let drop: DropListState
    let rows: [CGRect]
    let size: CGSize

    var body: some View {
        if drop.engaged, !DropScript.off.contains("light") {
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
