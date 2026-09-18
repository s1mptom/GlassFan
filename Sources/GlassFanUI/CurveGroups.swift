import SwiftUI
import FanKit

/// The sensors behind a fan's curves. One curve is the box this always was: its
/// sensors, the hottest of which drives it. Two or three are cards, one per curve,
/// numbered as their lines are on the plot; the one being edited sits under the glass
/// drop, and clicking another card - or dragging the drop onto it - edits that one.
struct CurveGroups: View {
    @Environment(DaemonClient.self) private var client
    @Binding var curves: [CurveRule]
    @Binding var editing: Int
    let driving: Int?
    let drivingTemp: Double?
    let maxRPM: Double

    @State private var picking: Int?
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(text: L10n.t("Датчики кривой", "Curve sensors"))
                Spacer()
                if curves.count < FanSettings.maxCurves {
                    Button(action: addCurve) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                            Text(L10n.t("кривая", "curve")).font(.system(size: 10.5))
                        }
                        .frame(height: 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .help(L10n.t("Добавить кривую со своими датчиками", "Add a curve with its own sensors"))
                }
            }

            if curves.count == 1 {
                HStack(alignment: .top, spacing: 6) {
                    chips(0)
                    Spacer(minLength: 0)
                    addSensor(0)
                }
            } else {
                GlassDropList(count: curves.count, selection: $editing) { index in card(index) }
            }

            Text(footnote)
                .font(.system(size: 10))
                .foregroundStyle(nothingChosen ? Palette.heat.opacity(0.9) : Palette.ink.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.ink.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5))
        )
    }

    private var nothingChosen: Bool { curves.allSatisfy { $0.sensorKeys.isEmpty } }

    private var footnote: String {
        if nothingChosen {
            return L10n.t("Ни одного датчика — вентилятор останется на авто.",
                          "No sensor chosen, so the fan stays on auto.")
        }
        return curves.count == 1
            ? L10n.t("Кривую ведёт самый горячий", "The hottest one drives the curve")
            : L10n.t("Вентилятор идёт по самой быстрой кривой", "The fan follows the fastest of its curves")
    }

    // MARK: Parts

    private func card(_ index: Int) -> some View {
        let role = CurveRole.of(index, editing: editing, driving: driving)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CurveNumber(number: index + 1, role: role)
                tags(index)
                Spacer(minLength: 0)
                if hovered == index {
                    Button { removeCurve(index) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .help(L10n.t("Убрать кривую \(index + 1)", "Remove curve \(index + 1)"))
                }
                addSensor(index)
            }
            if curves[index].sensorKeys.isEmpty {
                Text(L10n.t("Нет датчиков — кривая не работает", "No sensors, so this curve does nothing"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                chips(index)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.ink.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.07), lineWidth: 0.5))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Кривая \(index + 1)", "Curve \(index + 1)"))
        .accessibilityAddTraits(role == .editing ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { editing = index }
    }

    private func tags(_ index: Int) -> some View {
        HStack(spacing: 5) {
            if index == editing {
                Text(L10n.t("правится", "editing")).foregroundStyle(Palette.calm)
            }
            if index == driving {
                Text(L10n.t("крутит", "driving")).foregroundStyle(Palette.heat)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
    }

    private func chips(_ index: Int) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(curves[index].sensorKeys, id: \.self) { key in
                SensorChip(name: SensorCatalog.info(for: key).name,
                           value: client.reading(for: key),
                           highlighted: (curves.count == 1 || index == driving)
                               && client.reading(for: key) == drivingTemp) {
                    curves[index].sensorKeys.removeAll { $0 == key }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: curves[index].sensorKeys)
    }

    private func addSensor(_ index: Int) -> some View {
        Button { picking = index } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink.opacity(0.6))
        .help(L10n.t("Добавить датчик", "Add a sensor"))
        .popover(isPresented: Binding(get: { picking == index }, set: { if !$0 { picking = nil } }),
                 arrowEdge: .trailing) {
            SensorPicker(selection: $curves[index].sensorKeys)
                .environment(client)
                .frame(width: 360, height: 420)
        }
    }

    // MARK: Editing

    private func addCurve() {
        guard curves.count < FanSettings.maxCurves else { return }
        curves.append(CurveRule(curve: .starter(maxRPM: maxRPM)))
        editing = curves.count - 1
    }

    private func removeCurve(_ index: Int) {
        guard curves.count > 1, curves.indices.contains(index) else { return }
        curves.remove(at: index)
        if editing >= index, editing > 0 { editing -= 1 }
        hovered = nil
    }
}
