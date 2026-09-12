import SwiftUI
import FanKit

struct SensorsView: View {
    @Environment(DaemonClient.self) private var client
    @State private var search = ""
    @State private var onlyCharted = false

    private var tracked: Set<String> { Set(client.config?.trackedSensors ?? []) }

    /// Buckets the readings in a single pass.
    ///
    /// This used to ask `client.sensors(in:)` once per group, and each of those
    /// walked the whole list - eight passes over a couple of hundred sensors, with
    /// a catalogue lookup on every one, every time the view was evaluated. On a
    /// machine reporting 228 sensors that was most of a core.
    private var groups: [(SensorGroup, [SensorReading])] {
        var buckets: [SensorGroup: [SensorReading]] = [:]
        for sensor in client.snapshot?.sensors ?? [] {
            if onlyCharted && !tracked.contains(sensor.key) { continue }
            let info = SensorCatalog.info(for: sensor.key)
            if !search.isEmpty,
               !info.name.localizedCaseInsensitiveContains(search),
               !sensor.key.localizedCaseInsensitiveContains(search) { continue }
            buckets[info.group, default: []].append(sensor)
        }
        return SensorGroup.allCases.compactMap { group in
            guard let sensors = buckets[group], !sensors.isEmpty else { return nil }
            return (group, sensors.sorted { $0.value > $1.value })
        }
    }

    var body: some View {
        if !client.isConnected {
            DaemonMissingNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = self.groups
            VStack(spacing: 0) {
                toolbar.riseIn(0.02)
                if groups.isEmpty {
                    noMatches
                } else {
                    sensorList(groups)
                }
            }
        }
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.ink.opacity(0.25))
            Text(onlyCharted && search.isEmpty
                 ? L10n.t("На графике пока ничего нет", "Nothing is on the chart yet")
                 : L10n.t("Ничего не нашлось", "Nothing matches"))
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink.opacity(0.45))
            Text(onlyCharted && search.isEmpty
                 ? L10n.t("Отметьте датчик значком графика слева от названия.",
                          "Mark a sensor with the chart icon to the left of its name.")
                 : L10n.t("Попробуйте другое название или ключ датчика.",
                          "Try another name, or the sensor key."))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .riseIn(0.05)
    }

    /// Rows are direct children of the lazy stack, grouped with `Section`.
    ///
    /// They used to sit inside a `VStack` per group, and a `VStack` is not lazy:
    /// the lazy stack saw eight children and had to size each, so every one of
    /// the 228 rows existed and was laid out on every reading, on-screen or
    /// not - about a sixth of a core for a list showing twenty of them. With
    /// sections, only the rows in view are built.
    private func sensorList(_ groups: [(SensorGroup, [SensorReading])]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.0) { group, sensors in
                    Section {
                        ForEach(sensors) { sensor in
                            SensorRow(sensor: sensor, tracked: tracked.contains(sensor.key))
                        }
                    } header: {
                        SectionCaption(text: group.title)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            GlassSearchField(
                placeholder: L10n.t("Поиск по \(client.snapshot?.sensors.count ?? 0) датчикам",
                                    "Search \(client.snapshot?.sensors.count ?? 0) sensors"),
                text: $search
            )

            Toggle(L10n.t("Только на графике", "On the chart only"), isOn: $onlyCharted)
                .toggleStyle(.glassCheckbox)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.6))
                .fixedSize()

            Spacer()

            Text(L10n.t("на графике: \(tracked.count)", "charted: \(tracked.count)"))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.3))
        }
        .padding(.horizontal, 30)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

struct SensorRow: View {
    @Environment(DaemonClient.self) private var client
    let sensor: SensorReading
    let tracked: Bool

    @State private var hovering = false

    private var ratio: Double { min(max((sensor.value - 20) / 80, 0), 1) }

    private var barColor: Color {
        switch sensor.value {
        case ..<70: return tracked ? Palette.calm : Palette.ink.opacity(0.35)
        case ..<85: return Palette.heat
        default:    return Palette.critical
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggleTracking) {
                Image(systemName: tracked ? "chart.line.uptrend.xyaxis" : "circle.dotted")
                    .font(.system(size: 11, weight: .medium))
                    // Untracked sensors keep their marker nearly invisible until the
                    // pointer is on the row, so a list of 228 of them is not 228 dots.
                    .foregroundStyle(tracked ? Palette.calm
                                             : Palette.ink.opacity(hovering ? 0.5 : 0.22))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Показывать на графике", "Show on the chart"))
            .accessibilityLabel(L10n.t("Показывать на графике", "Show on the chart"))
            .accessibilityValue(tracked ? L10n.t("включено", "on") : L10n.t("выключено", "off"))

            Text(SensorCatalog.info(for: sensor.key).name)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink.opacity(tracked ? 0.9 : 0.72))
                .frame(width: 186, alignment: .leading)
                .lineLimit(1)

            Text(sensor.key)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.3))
                .frame(width: 46, alignment: .leading)

            // Scaled rather than measured: a GeometryReader in every one of a
            // couple of hundred rows forces a layout pass each redraw, and the
            // bar only ever needs a fraction of the width it is given.
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.08))
                Capsule()
                    .fill(barColor)
                    .scaleEffect(x: max(ratio, 0.004), y: 1, anchor: .leading)
            }
            .frame(height: 3)

            Text(Format.temperatureFine(sensor.value))
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(tracked ? 1 : 0.78))
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.ink.opacity(hovering ? 0.045 : 0))
        )
        .padding(.horizontal, -8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink.opacity(0.06)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        // One sentence per row rather than five unlabelled fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(SensorCatalog.info(for: sensor.key).name), "
                            + Format.temperatureFine(sensor.value))
    }

    private func toggleTracking() {
        guard var config = client.draftConfig ?? client.snapshot?.config else { return }
        if let index = config.trackedSensors.firstIndex(of: sensor.key) {
            config.trackedSensors.remove(at: index)
        } else {
            config.trackedSensors.append(sensor.key)
        }
        client.draftConfig = config
        client.commit()
    }
}
