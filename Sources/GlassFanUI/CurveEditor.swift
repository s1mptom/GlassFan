import SwiftUI
import FanKit

/// Drag-to-edit fan curves. Swift Charts cannot do this, so the plot is drawn by hand.
///
/// X is temperature, Y is rpm. A live marker shows where the fan is sitting right now.
/// With several curves all are drawn and one is edited: it is blue and has handles,
/// the one driving the fan is orange, the rest grey. Their numbers sit at their ends.
struct CurveEditor: View {
    @Binding var curves: [CurveRule]
    /// The curve whose points take drags and double-clicks.
    @Binding var editing: Int
    /// The curve setting the fan's speed right now, when that is known.
    var driving: Int? = nil
    /// Each curve's own temperature: the hottest sensor of its group. The live marker
    /// is the driving curve's; the others are drawn where they each stand, so a marker
    /// on one curve is not read against another's line.
    var curveTemps: [Double?] = []
    let limits: FanLimits
    let currentTemp: Double?
    let currentRPM: Double?
    /// The slowest this fan has been watched actually turning, where that is known.
    /// Drawn instead of the SMC's advertised minimum, because it is the one a curve
    /// drawn below is really going to meet.
    var learnedFloor: Double? = nil
    var onCommit: () -> Void

    /// For previews: a point to show the readout for, as if the pointer were on it.
    var highlighted: Int? = nil

    private let tempRange: ClosedRange<Double> = 30...100

    /// The edited curve. Read and written through `curves`, so everything that shaped
    /// the one curve this editor used to have now shapes whichever is chosen.
    private var curve: FanCurve {
        get { curves.indices.contains(editing) ? curves[editing].curve : FanCurve(points: []) }
        nonmutating set {
            guard curves.indices.contains(editing) else { return }
            curves[editing].curve = newValue
        }
    }

    private var numbered: Bool { curves.count > 1 }
    @State private var dragging: Int?
    @State private var hovered: Int?
    @State private var readoutSize = CGSize(width: 150, height: 40)

    /// The point whose values are on show: the one being dragged, or else the one
    /// under the pointer.
    private var inspected: Int? {
        guard let index = dragging ?? hovered ?? highlighted, curve.points.indices.contains(index) else { return nil }
        return index
    }

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(x: 34, y: 8,
                              width: max(geometry.size.width - 44 - (numbered ? 26 : 0), 10),
                              height: max(geometry.size.height - 52, 10))

            ZStack(alignment: .topLeading) {
                grid(in: plot)
                minimumGuide(in: plot)
                curveShape(in: plot)
                guides(in: plot)
                curvePositions(in: plot)
                liveMarker(in: plot)
                handles(in: plot)
                curveNumbers(in: plot)
                axisLabels(in: plot)
                readout(in: plot)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                guard plot.contains(location) else { return }
                curve.addPoint(point(from: location, in: plot))
                onCommit()
            }
        }
    }

    // MARK: Geometry

    private func position(_ point: CurvePoint, in plot: CGRect) -> CGPoint {
        let x = plot.minX + plot.width *
            (point.temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
        let y = plot.maxY - plot.height * point.rpm / max(limits.maxRPM, 1)
        return CGPoint(x: x, y: y)
    }

    private func point(from location: CGPoint, in plot: CGRect) -> CurvePoint {
        let ratioX = min(max((location.x - plot.minX) / plot.width, 0), 1)
        let ratioY = min(max((plot.maxY - location.y) / plot.height, 0), 1)
        return CurvePoint(
            temperature: (tempRange.lowerBound + ratioX * (tempRange.upperBound - tempRange.lowerBound)).rounded(),
            rpm: (ratioY * limits.maxRPM).rounded()
        )
    }

    // MARK: Layers

    private func grid(in plot: CGRect) -> some View {
        Canvas { context, _ in
            let line = Palette.ink.opacity(0.05)
            for temperature in stride(from: 40.0, through: 100.0, by: 20.0) {
                let x = position(CurvePoint(temperature: temperature, rpm: limits.minRPM), in: plot).x
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY))
                                      $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                               with: .color(line), lineWidth: 1)
            }
            for fraction in stride(from: 0.0, through: 1.0, by: 0.25) {
                let y = plot.maxY - plot.height * fraction
                context.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: y))
                                      $0.addLine(to: CGPoint(x: plot.maxX, y: y)) },
                               with: .color(line), lineWidth: 1)
            }
        }
    }

    /// Where the SMC says the fan's minimum is. It is advice, not a floor - the
    /// hardware was asked for 1000, 500 and 0 and did as it was told - so the
    /// scale runs to zero and this line just says where "minimum" would have
    /// been. Below it the fan runs slow and, at zero, stops.
    private func minimumGuide(in plot: CGRect) -> some View {
        // The measured floor where there is one. The SMC's own figure is advice - a fan
        // asked for less keeps going - so a line drawn at it marks a place nothing
        // actually happens, while the speed the fan will not go below goes unmarked.
        let shown = learnedFloor ?? limits.minRPM
        let y = position(CurvePoint(temperature: tempRange.lowerBound, rpm: shown), in: plot).y
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            .stroke(Palette.ink.opacity(learnedFloor == nil ? 0.18 : 0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            Text(learnedFloor == nil
                 ? L10n.t("\(Format.rpm(shown)) · минимум SMC", "\(Format.rpm(shown)) · SMC minimum")
                 : L10n.t("\(Format.rpm(shown)) · ниже не крутит", "\(Format.rpm(shown)) · will not go below"))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.32))
                .position(x: plot.maxX - 58, y: y - 9)
        }
        .allowsHitTesting(false)
    }

    /// A curve as drawn: flat from the plot's left edge to its first point, through
    /// its points, and flat on to the right edge - which is what the fan does past them.
    private func line(_ curve: FanCurve, in plot: CGRect) -> Path {
        var path = Path()
        guard let first = curve.points.first, let last = curve.points.last else { return path }
        path.move(to: CGPoint(x: plot.minX, y: position(first, in: plot).y))
        for point in curve.points { path.addLine(to: position(point, in: plot)) }
        path.addLine(to: CGPoint(x: plot.maxX, y: position(last, in: plot).y))
        return path
    }

    /// The other curves under the one being edited: the driving one orange, the rest
    /// grey and dashed. Only the edited one is filled and has handles.
    private func curveShape(in plot: CGRect) -> some View {
        Canvas { context, _ in
            for index in curves.indices where index != editing {
                let path = line(curves[index].curve, in: plot)
                if index == driving {
                    context.stroke(path, with: .color(Palette.heat), lineWidth: 2)
                } else {
                    context.stroke(path, with: .color(Palette.ink.opacity(0.28)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            guard !curve.points.isEmpty else { return }
            let path = line(curve, in: plot)
            var fill = path
            fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [Palette.calm.opacity(0.32), Palette.calm.opacity(0.02)]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)))
            context.stroke(path, with: .color(Palette.calm), lineWidth: 2.5)
        }
    }

    /// Each curve's number at its right-hand end, in the margin; clicking one edits it.
    private func curveNumbers(in plot: CGRect) -> some View {
        Group {
            if numbered {
                let ends = curves.map { rule -> CGFloat in
                    let rpm = rule.curve.points.last?.rpm ?? 0
                    return position(CurvePoint(temperature: tempRange.upperBound, rpm: rpm), in: plot).y
                }
                let placed = CurveNumberLayout.place(ends: ends, editing: editing, within: plot.minY...plot.maxY)
                let x = plot.maxX + 16
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for number in placed {
                            let role = CurveRole.of(number.index, editing: editing, driving: driving)
                            var leader = Path()
                            leader.move(to: CGPoint(x: plot.maxX, y: number.lineY))
                            leader.addLine(to: CGPoint(x: plot.maxX + 4, y: number.lineY))
                            leader.addLine(to: CGPoint(x: x - 9, y: number.y))
                            context.stroke(leader, with: .color(role.colour.opacity(0.6)), lineWidth: 1)
                        }
                    }
                    .allowsHitTesting(false)
                    ForEach(placed, id: \.index) { number in
                        Button { editing = number.index } label: {
                            CurveNumber(number: number.index + 1,
                                        role: CurveRole.of(number.index, editing: editing, driving: driving),
                                        size: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("Править кривую \(number.index + 1)", "Edit curve \(number.index + 1)"))
                        .accessibilityLabel(L10n.t("Кривая \(number.index + 1)", "Curve \(number.index + 1)"))
                        .position(x: x, y: number.y)
                    }
                }
            }
        }
    }

    private func handles(in plot: CGRect) -> some View {
        ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
            Circle()
                .fill(Palette.surface)
                .overlay(Circle().strokeBorder(Palette.calm, lineWidth: 2.5))
                .frame(width: 13, height: 13)
                .scaleEffect(dragging == index ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                // Drawn at thirteen points, aimed at as twenty-six. A miss does not do
                // nothing here - it falls through to the editor's own double-click and
                // *adds* a point, so a hand that was a few pixels off removing one ends
                // up with two. The circle is unchanged; only the target around it grows.
                .frame(width: 26, height: 26)
                .contentShape(Circle())
                // Before `.position`, not after. A positioned view takes all the space
                // its parent offers - only its drawing is at the point - so a hover
                // attached afterwards covers the whole plot. Every handle then claimed
                // every pointer position, the last one round the loop won, and moving
                // onto the chart anywhere read out the rightmost point.
                .onHover { inside in
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
                // Removing sits here for the same reason, and before the drag besides.
                // The drag used to begin at zero distance, so it recognised on
                // mouse-down and swallowed the click before any tap could form: double
                // -clicking a handle never removed it, and the editor's own
                // double-click added a point on top of the one being aimed at. Two
                // points of travel is still nothing to the hand and leaves a stationary
                // click alone.
                .onTapGesture(count: 2) {
                    curve.removePoint(at: index)
                    hovered = nil
                    onCommit()
                }
                .position(position(point, in: plot))
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let current = dragging ?? index
                            let moved = self.point(from: value.location, in: plot)
                            curve.movePoint(at: current, to: moved)
                            // The points are kept in temperature order, so dragging
                            // one past a neighbour changes its place in the list.
                            // Holding on to the old place moved the neighbour instead.
                            dragging = curve.points.firstIndex(of: moved) ?? current
                        }
                        .onEnded { _ in
                            dragging = nil
                            onCommit()
                        }
                )
                .accessibilityLabel(L10n.t("Точка кривой", "Curve point"))
                .accessibilityValue(L10n.t("\(Int(point.temperature)) градусов, \(Int(point.rpm)) оборотов в минуту",
                                           "\(Int(point.temperature)) degrees, \(Int(point.rpm)) rpm"))
        }
    }

    /// Where each curve other than the driving one stands: at its own sensors'
    /// temperature, asking for its own speed. The x axis is a different sensor for
    /// each curve, so without these the one live marker - the driving curve's - sat
    /// under the other curves' lines as if they were being ignored.
    private func curvePositions(in plot: CGRect) -> some View {
        Canvas { context, _ in
            guard numbered else { return }
            for index in curves.indices where index != driving {
                guard curveTemps.indices.contains(index), let temp = curveTemps[index],
                      let rpm = curves[index].curve.rpm(at: temp) else { continue }
                let role = CurveRole.of(index, editing: editing, driving: driving)
                let raw = position(CurvePoint(temperature: temp, rpm: rpm), in: plot)
                let at = CGPoint(x: min(max(raw.x, plot.minX), plot.maxX), y: min(max(raw.y, plot.minY), plot.maxY))
                // Solid, as the live marker is: a ring here reads as a handle to drag.
                let halo = Path(ellipseIn: CGRect(x: at.x - 6, y: at.y - 6, width: 12, height: 12))
                let dot = Path(ellipseIn: CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7))
                context.fill(halo, with: .color(role.colour.opacity(0.22)))
                context.fill(dot, with: .color(role == .idle ? Palette.ink.opacity(0.6) : role.colour))
                let label = context.resolve(Text(Format.temperature(temp))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(role == .idle ? Palette.ink.opacity(0.45) : role.colour))
                context.draw(label, at: CGPoint(x: at.x + 9, y: at.y - 9), anchor: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    private func liveMarker(in plot: CGRect) -> some View {
        Group {
            if let currentTemp, let currentRPM {
                // Kept inside the plot. The plot's floor is the fan's SMC minimum,
                // but on Apple silicon a fan at rest reads 0 rpm - below that
                // floor - and the marker flew off the bottom of the editor. It
                // sits on the floor line instead, and the label says what the
                // fan is really doing.
                let raw = position(CurvePoint(temperature: currentTemp, rpm: currentRPM), in: plot)
                let marker = CGPoint(x: min(max(raw.x, plot.minX), plot.maxX),
                                     y: min(max(raw.y, plot.minY), plot.maxY))
                let nearFloor = marker.y > plot.maxY - 22
                Circle()
                    .fill(Palette.heat)
                    .frame(width: 11, height: 11)
                    // The halo was a live shadow on a dot that moves every second,
                    // which is an offscreen blur pass for something a ring draws
                    // just as well.
                    .overlay(Circle().strokeBorder(Palette.heat.opacity(0.25), lineWidth: 4))
                    .overlay(Circle().strokeBorder(Palette.heat.opacity(0.12), lineWidth: 9))
                    .position(marker)
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)

                Text(String(format: "%.0f° · %.0f", currentTemp, currentRPM))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    // A plain capsule, not a glass surface. This label moves with
                    // every reading, and re-rendering a Liquid Glass material on
                    // something that is in motion a second out of every second is
                    // the most expensive thing on the screen for the least gain -
                    // it is a tooltip the size of a postage stamp.
                    .background(
                        Capsule()
                            .fill(Palette.surface.opacity(0.82))
                            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12),
                                                            lineWidth: 0.5))
                    )
                    .position(x: min(marker.x + 52, plot.maxX - 46),
                              y: nearFloor ? marker.y - 20
                                           : min(max(marker.y, plot.minY + 12), plot.maxY - 12))
                    .animation(.easeInOut(duration: 0.8), value: currentTemp)
                    // Out of the way of the point being set, which is what matters then.
                    .opacity(inspected == nil ? 1 : 0.25)
                    .animation(.easeOut(duration: 0.15), value: inspected)
            }
        }
        // Decoration, and it takes no clicks. Both the dot and its label are
        // `.position`ed, and a positioned view fills the space its parent offers - so
        // this layer covers the whole plot however small the thing drawn on it is.
        .allowsHitTesting(false)
    }

    /// Dashed lines from the inspected point down to the temperature axis and across
    /// to the speed axis, so its place on both scales can be read off.
    private func guides(in plot: CGRect) -> some View {
        Group {
            if let index = inspected {
                let at = position(curve.points[index], in: plot)
                Path { path in
                    path.move(to: CGPoint(x: at.x, y: plot.maxY))
                    path.addLine(to: at)
                    path.addLine(to: CGPoint(x: plot.minX, y: at.y))
                }
                .stroke(Palette.calm.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .allowsHitTesting(false)
    }

    /// The inspected point's values beside it: its temperature and the speed the fan
    /// is set to there, and what that speed means when it is not an ordinary one.
    ///
    /// Above the point, or below it when there is no room above, and kept inside
    /// the plot. It follows the point exactly - an animation here would trail
    /// behind the pointer it is labelling.
    private func readout(in plot: CGRect) -> some View {
        Group {
            if let index = inspected {
                let point = curve.points[index]
                let at = position(point, in: plot)
                let gap: CGFloat = 16
                let above = at.y - gap - readoutSize.height / 2
                let fitsAbove = above - readoutSize.height / 2 >= plot.minY - 6
                let x = min(max(at.x, plot.minX + readoutSize.width / 2),
                            plot.maxX - readoutSize.width / 2 + 8)
                CurveReadout(point: point, limits: limits)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { readoutSize = $0 }
                    .position(x: x, y: fitsAbove ? above : at.y + gap + readoutSize.height / 2)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: inspected)
        .allowsHitTesting(false)
    }

    private func axisLabels(in plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Adding and removing points is a double click on nothing in
            // particular - undiscoverable unless it is said. It was a hover
            // tooltip, which was small, floated over the axis labels and looked
            // like it was trying to squeeze into the interface. A caption under
            // the plot is always there and in nobody's way.
            // Both halves say "double", because the short form did not and was read
            // as "click a point to remove it" - which does nothing, and looks broken.
            Text(L10n.t("Двойной клик: по пустому месту — добавить точку, по точке — убрать её",
                        "Double-click empty space to add a point, double-click a point to remove it"))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink.opacity(0.35))
                .fixedSize()
                .offset(x: plot.minX, y: plot.maxY + 28)
            ForEach([40.0, 60.0, 80.0, 100.0], id: \.self) { temperature in
                Text("\(Int(temperature))°")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink.opacity(0.3))
                    .position(x: position(CurvePoint(temperature: temperature, rpm: limits.minRPM), in: plot).x,
                              y: plot.maxY + 13)
            }
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                Text(Format.rpm(fraction * limits.maxRPM))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.3))
                    .position(x: plot.minX - 20, y: plot.maxY - plot.height * fraction)
            }
        }
        // Labels take no clicks. Each is `.position`ed, and a positioned view fills the
        // space its parent offers, so this layer covered the whole plot - and it is
        // drawn after the handles, so it covered those too. Double-clicking a point
        // landed on an axis label instead of the point, fell through to the editor's
        // own double-click, and added a point where one was being removed.
        .allowsHitTesting(false)
    }
}

/// Temperature and speed of one curve point, as a small label.
private struct CurveReadout: View {
    let point: CurvePoint
    let limits: FanLimits

    /// What the speed amounts to, when that is worth saying.
    private var note: String {
        if point.rpm <= 0 { return L10n.t("вентилятор стоит", "fan stopped") }
        if point.rpm < limits.minRPM { return L10n.t("ниже минимума SMC", "below SMC minimum") }
        if point.rpm >= limits.maxRPM { return L10n.t("максимум", "maximum") }
        return L10n.t("об/мин", "rpm")
    }

    var body: some View {
        HStack(spacing: 10) {
            value(Format.temperature(point.temperature), caption: L10n.t("температура", "temperature"))
            Rectangle()
                .fill(Palette.ink.opacity(0.14))
                .frame(width: 0.5, height: 24)
            value(Format.rpm(point.rpm), caption: note)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        // A plain surface, not glass: it moves with every step of a drag.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.surface.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
        .fixedSize()
    }

    private func value(_ text: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.ink.opacity(0.45))
        }
    }
}

#Preview("Curve readout") {
    @Previewable @State var curves = [CurveRule(sensorKeys: [], curve: FanCurve(points: [
        CurvePoint(temperature: 45, rpm: 0),
        CurvePoint(temperature: 62, rpm: 1200),
        CurvePoint(temperature: 78, rpm: 3400),
        CurvePoint(temperature: 92, rpm: 5348),
    ]))]
    VStack(spacing: 0) {
        ForEach([1, 2], id: \.self) { point in
            CurveEditor(curves: $curves, editing: .constant(0), limits: FanLimits(minRPM: 1499, maxRPM: 5348),
                        currentTemp: 58, currentRPM: 1700, onCommit: {}, highlighted: point)
                .frame(height: 260)
                .padding(20)
        }
    }
    .frame(width: 600)
    .background(Color(red: 0.11, green: 0.13, blue: 0.18))
    .environment(\.colorScheme, .dark)
}

/// Palm rests, CPU and GPU: the palm rests' curve being edited, the CPU's driving,
/// and curves 1 and 2 ending at the same speed, so their numbers have to part.
#Preview("Curve editor · three curves") {
    @Previewable @State var curves = [
        CurveRule(sensorKeys: ["Ts0P"], curve: FanCurve(points: [
            CurvePoint(temperature: 40, rpm: 0), CurvePoint(temperature: 55, rpm: 1800),
            CurvePoint(temperature: 75, rpm: 3400), CurvePoint(temperature: 90, rpm: 5776)])),
        CurveRule(sensorKeys: ["TCMz"], curve: FanCurve(points: [
            CurvePoint(temperature: 60, rpm: 2500), CurvePoint(temperature: 85, rpm: 5776)])),
        CurveRule(sensorKeys: ["Tg05"], curve: FanCurve(points: [
            CurvePoint(temperature: 50, rpm: 1000), CurvePoint(temperature: 100, rpm: 4000)])),
    ]
    @Previewable @State var editing = 0
    CurveEditor(curves: $curves, editing: $editing, driving: 1, curveTemps: [33, 72, 41],
                limits: FanLimits(minRPM: 1499, maxRPM: 5776),
                currentTemp: 72, currentRPM: 4072, learnedFloor: 1240, onCommit: {})
        .padding(16)
        .frame(width: 700, height: 300)
        .background(Color(red: 0.12, green: 0.14, blue: 0.19))
        .environment(\.colorScheme, .dark)
}
