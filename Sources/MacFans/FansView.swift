import SwiftUI
import FanKit

struct FansView: View {
    @Environment(DaemonClient.self) private var client
    @State private var selected: Int = 0
    @State private var showingSensorPicker = false

    private var fans: [FanReading] { client.snapshot?.fans ?? [] }
    private var fan: FanReading? { fans.first { $0.index == selected } ?? fans.first }

    var body: some View {
        if !client.isConnected {
            DaemonMissingNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if fans.isEmpty {
            DataHint()
        } else {
            HStack(alignment: .top, spacing: 26) {
                sidebar.riseIn(0.02)
                if let fan { detail(fan).riseIn(0.10) }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    // MARK: Fan picker

    private var sidebar: some View {
        VStack(spacing: 12) {
            ForEach(fans) { item in
                fanRow(item)
            }
            Spacer(minLength: 0)
            if let fan, settings(for: fan).mode == .curve {
                sensorBox(fan)
            }
        }
        .frame(width: 212)
    }

    private func fanRow(_ item: FanReading) -> some View {
        let isSelected = item.index == (fan?.index ?? -1)
        return HStack(spacing: 14) {
            FanDial(rpm: item.actualRPM, limits: item.limits, controlled: item.forced,
                    size: 58, showsCaption: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Вентилятор \(item.index + 1)", "Fan \(item.index + 1)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                Text(Format.rpm(item.actualRPM))
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.forced ? .white : .white.opacity(0.86))
                Text(modeCaption(item))
                    .font(.system(size: 10.5))
                    .foregroundStyle(item.forced ? Palette.calm : .white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.075 : 0.03))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.16 : 0.07), lineWidth: 0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selected = item.index }
        }
    }

    private func modeCaption(_ item: FanReading) -> String {
        if item.writeError != nil { return L10n.t("запись отклонена", "write refused") }
        switch item.mode {
        case .auto:  return L10n.t("система", "system")
        case .fixed: return L10n.t("фиксировано", "fixed")
        case .curve: return L10n.t("по кривой", "curve")
        }
    }

    private func sensorBox(_ fan: FanReading) -> some View {
        let current = settings(for: fan)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(text: L10n.t("Датчики кривой", "Curve sensors"))
                Spacer()
                Button {
                    showingSensorPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .popover(isPresented: $showingSensorPicker, arrowEdge: .trailing) {
                    SensorPicker(selection: binding(for: fan).sensorKeys)
                        .environment(client)
                        .frame(width: 360, height: 420)
                }
            }

            if current.sensorKeys.isEmpty {
                Text(L10n.t("Ни одного датчика — вентилятор останется на авто.",
                            "No sensor chosen, so the fan stays on auto."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.heat.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(current.sensorKeys, id: \.self) { key in
                        SensorChip(name: SensorCatalog.info(for: key).name,
                                   value: client.reading(for: key),
                                   highlighted: client.reading(for: key) == fan.drivingTemp)
                    }
                }
                Text(L10n.t("Кривую ведёт самый горячий", "The hottest one drives the curve"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        )
    }

    // MARK: Detail

    private func detail(_ fan: FanReading) -> some View {
        let settingsBinding = binding(for: fan)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                GlassSegmented(
                    items: [
                        .init(value: FanMode.auto, title: L10n.t("Авто", "Auto")),
                        .init(value: FanMode.fixed, title: L10n.t("Фиксировано", "Fixed")),
                        .init(value: FanMode.curve, title: L10n.t("По кривой", "Curve")),
                    ],
                    selection: settingsBinding.mode,
                    segmentWidth: 96,
                    fontSize: 12
                )
                Spacer()
                Text("\(Format.rpm(fan.limits.minRPM)) – \(Format.rpm(fan.limits.maxRPM)) "
                     + L10n.t("об/мин", "rpm"))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.42))
            }

            // One container whose size never depends on the mode, so switching modes
            // cannot resize the card and shove the control that was just clicked.
            ZStack {
                switch settingsBinding.wrappedValue.mode {
                case .auto:  autoPanel
                case .fixed: fixedPanel(fan, settingsBinding)
                case .curve: curvePanel(fan, settingsBinding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 26) {
                LabelledSlider(
                    title: L10n.t("Гистерезис", "Hysteresis"),
                    valueText: String(format: "%.0f °C", settingsBinding.wrappedValue.hysteresis),
                    value: settingsBinding.hysteresis, range: 0...10, step: nil,
                    onCommit: { client.commit() }
                )
                LabelledSlider(
                    title: L10n.t("Сглаживание", "Smoothing"),
                    valueText: String(format: "%.0f %%", settingsBinding.wrappedValue.smoothing * 100),
                    value: settingsBinding.smoothing, range: 0...0.95, step: nil,
                    onCommit: { client.commit() }
                )
            }
            .opacity(settingsBinding.wrappedValue.mode == .curve ? 1 : 0.35)
            .disabled(settingsBinding.wrappedValue.mode != .curve)
        }
    }

    private var autoPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(L10n.t("Вентилятором управляет система", "The system is in charge of this fan"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
    }

    private func fixedPanel(_ fan: FanReading, _ settings: Binding<FanSettings>) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Text(Format.rpm(settings.wrappedValue.fixedRPM))
                .font(.system(size: 56, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(L10n.t("об/мин", "rpm"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .offset(y: -18)
            Slider(value: settings.fixedRPM,
                   in: fan.limits.minRPM...fan.limits.maxRPM,
                   step: 50) { editing in
                if !editing { client.commit() }
            }
            .tint(Palette.calm)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
    }

    private func curvePanel(_ fan: FanReading, _ settings: Binding<FanSettings>) -> some View {
        Group {
            if settings.wrappedValue.curve.points.isEmpty {
                VStack(spacing: 14) {
                    Text(L10n.t("Кривая ещё не задана", "No curve yet"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                    Button(L10n.t("Создать кривую", "Create a curve")) {
                        settings.wrappedValue.curve = .defaultCurve(minRPM: fan.limits.minRPM,
                                                                    maxRPM: fan.limits.maxRPM)
                        client.commit()
                    }
                    .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CurveEditor(
                    curve: settings.curve,
                    limits: fan.limits,
                    currentTemp: fan.drivingTemp,
                    currentRPM: fan.actualRPM,
                    onCommit: { client.commit() }
                )
                .padding(16)
            }
        }
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.5))
    }

    // MARK: Config plumbing

    private func settings(for fan: FanReading) -> FanSettings {
        client.config?.fans.first { $0.id == fan.index }
            ?? FanSettings(id: fan.index, mode: .auto, fixedRPM: fan.limits.minRPM,
                           sensorKeys: [], curve: FanCurve(points: []),
                           hysteresis: 2, smoothing: 0.3)
    }

    private func binding(for fan: FanReading) -> Binding<FanSettings> {
        Binding(
            get: { settings(for: fan) },
            set: { newValue in
                guard var config = client.draftConfig ?? client.snapshot?.config else { return }
                if let index = config.fans.firstIndex(where: { $0.id == fan.index }) {
                    config.fans[index] = newValue
                } else {
                    config.fans.append(newValue)
                }
                client.draftConfig = config
                client.commit()
            }
        )
    }
}

struct SensorPicker: View {
    @Environment(DaemonClient.self) private var client
    @Binding var selection: [String]
    @State private var search = ""

    private var groups: [(SensorGroup, [SensorReading])] {
        SensorGroup.allCases.compactMap { group in
            let sensors = client.sensors(in: group).filter { sensor in
                guard !search.isEmpty else { return true }
                let info = SensorCatalog.info(for: sensor.key)
                return info.name.localizedCaseInsensitiveContains(search)
                    || sensor.key.localizedCaseInsensitiveContains(search)
            }
            return sensors.isEmpty ? nil : (group, sensors.sorted { $0.value > $1.value })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.t("Поиск датчика", "Search sensors"), text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)

            List {
                ForEach(groups, id: \.0) { group, sensors in
                    SwiftUI.Section(group.title) {
                        ForEach(sensors) { sensor in
                            Toggle(isOn: Binding(
                                get: { selection.contains(sensor.key) },
                                set: { isOn in
                                    if isOn { selection.append(sensor.key) }
                                    else { selection.removeAll { $0 == sensor.key } }
                                }
                            )) {
                                HStack {
                                    Text(SensorCatalog.info(for: sensor.key).name)
                                    Text(sensor.key)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(Format.temperatureFine(sensor.value))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
