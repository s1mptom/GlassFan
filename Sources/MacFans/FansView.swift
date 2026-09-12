import SwiftUI
import FanKit

struct FansView: View {
    @Environment(DaemonClient.self) private var client

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 18) {
                    ForEach(client.snapshot?.fans ?? []) { fan in
                        FanCard(fan: fan)
                    }
                    if client.snapshot == nil {
                        DataHint().glassCard()
                    }
                }
            }
            .padding(22)
        }
        .scrollContentBackground(.hidden)
    }
}

struct FanCard: View {
    @Environment(DaemonClient.self) private var client
    let fan: FanReading
    @State private var showingSensorPicker = false

    private var settings: FanSettings? {
        client.config?.fans.first { $0.id == fan.index }
    }

    private func binding() -> Binding<FanSettings> {
        Binding(
            get: {
                self.settings ?? FanSettings(id: fan.index, mode: .auto, fixedRPM: fan.limits.minRPM,
                                             sensorKeys: [], curve: FanCurve(points: []),
                                             hysteresis: 2, smoothing: 0.3)
            },
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

    var body: some View {
        let fanSettings = binding()

        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("", selection: fanSettings.mode) {
                Text(L10n.t("Авто", "Auto")).tag(FanMode.auto)
                Text(L10n.t("Фиксировано", "Fixed")).tag(FanMode.fixed)
                Text(L10n.t("По кривой", "Curve")).tag(FanMode.curve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch fanSettings.wrappedValue.mode {
            case .auto:
                Text(L10n.t("Вентилятором управляет система.",
                            "The system is in charge of this fan."))
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .fixed:
                fixedControls(fanSettings)

            case .curve:
                curveControls(fanSettings)
            }
        }
        .glassCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"))
                .font(.headline)
            Spacer()
            if fan.emergency {
                Label(L10n.t("Аварийный режим", "Emergency"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }
            Text(Format.rpm(fan.actualRPM))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("rpm").foregroundStyle(.secondary)
        }
    }

    private func fixedControls(_ settings: Binding<FanSettings>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Обороты", "Speed"))
                Spacer()
                Text(Format.rpm(settings.wrappedValue.fixedRPM) + " rpm").monospacedDigit()
            }
            Slider(value: settings.fixedRPM, in: fan.limits.minRPM...fan.limits.maxRPM, step: 50)
            HStack {
                Text(Format.rpm(fan.limits.minRPM)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(Format.rpm(fan.limits.maxRPM)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func curveControls(_ settings: Binding<FanSettings>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.wrappedValue.curve.points.isEmpty {
                Button(L10n.t("Создать кривую", "Create a curve")) {
                    settings.wrappedValue.curve = .defaultCurve(minRPM: fan.limits.minRPM,
                                                                maxRPM: fan.limits.maxRPM)
                }
                .buttonStyle(.glassProminent)
            } else {
                CurveEditor(
                    curve: settings.curve,
                    limits: fan.limits,
                    currentTemp: fan.drivingTemp,
                    currentRPM: fan.actualRPM,
                    onCommit: { client.commit() }
                )
                Text(L10n.t("Двойной клик по полю — добавить точку, по точке — удалить.",
                            "Double-click the field to add a point, a point to remove it."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            sensorAssignment(settings)

            HStack(spacing: 24) {
                labelledSlider(L10n.t("Гистерезис", "Hysteresis"),
                               value: settings.hysteresis, range: 0...10,
                               format: { String(format: "%.0f °C", $0) })
                labelledSlider(L10n.t("Сглаживание", "Smoothing"),
                               value: settings.smoothing, range: 0...0.95,
                               format: { String(format: "%.0f %%", $0 * 100) })
            }
        }
    }

    private func sensorAssignment(_ settings: Binding<FanSettings>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("Датчики", "Sensors")).font(.subheadline).bold()
                Spacer()
                Button(L10n.t("Выбрать…", "Choose…")) { showingSensorPicker = true }
                    .buttonStyle(.glass)
                    .popover(isPresented: $showingSensorPicker, arrowEdge: .bottom) {
                        SensorPicker(selection: settings.sensorKeys)
                            .environment(client)
                            .frame(width: 360, height: 420)
                    }
            }
            if settings.wrappedValue.sensorKeys.isEmpty {
                Text(L10n.t("Ни одного датчика не выбрано — вентилятор останется на авто.",
                            "No sensor chosen, so the fan stays on auto."))
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(settings.wrappedValue.sensorKeys, id: \.self) { key in
                        HStack(spacing: 5) {
                            Text(SensorCatalog.info(for: key).name).font(.caption)
                            Text(Format.temperature(client.reading(for: key)))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                    }
                }
                Text(L10n.t("Кривую ведёт самый горячий из выбранных.",
                            "The hottest of these drives the curve."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func labelledSlider(_ title: String, value: Binding<Double>,
                                range: ClosedRange<Double>,
                                format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(format(value.wrappedValue)).font(.caption).monospacedDigit()
            }
            Slider(value: value, in: range) { editing in
                if !editing { client.commit() }
            }
        }
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
