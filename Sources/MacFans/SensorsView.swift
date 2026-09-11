import SwiftUI
import FanKit

struct SensorsView: View {
    @Environment(DaemonClient.self) private var client
    @State private var search = ""
    @State private var onlyCharted = false

    private var groups: [(SensorGroup, [SensorReading])] {
        SensorGroup.allCases.compactMap { group in
            let tracked = Set(client.config?.trackedSensors ?? [])
            let sensors = client.sensors(in: group).filter { sensor in
                if onlyCharted && !tracked.contains(sensor.key) { return false }
                guard !search.isEmpty else { return true }
                return SensorCatalog.info(for: sensor.key).name.localizedCaseInsensitiveContains(search)
                    || sensor.key.localizedCaseInsensitiveContains(search)
            }
            return sensors.isEmpty ? nil : (group, sensors.sorted { $0.value > $1.value })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField(L10n.t("Поиск", "Search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle(L10n.t("Только на графике", "On the chart only"), isOn: $onlyCharted)
                    .toggleStyle(.checkbox)
                Spacer()
                Text(L10n.t("Всего: \(client.snapshot?.sensors.count ?? 0)",
                            "Total: \(client.snapshot?.sensors.count ?? 0)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(groups, id: \.0) { group, sensors in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(group.title, systemImage: group.symbol)
                                .font(.headline)
                            ForEach(sensors) { sensor in
                                SensorRow(sensor: sensor)
                            }
                        }
                        .glassCard()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }
}

struct SensorRow: View {
    @Environment(DaemonClient.self) private var client
    let sensor: SensorReading

    private var isTracked: Bool {
        client.config?.trackedSensors.contains(sensor.key) ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggleTracking()
            } label: {
                Image(systemName: isTracked ? "chart.xyaxis.line" : "circle.dotted")
                    .foregroundStyle(isTracked ? Palette.calm : .secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Показывать на графике", "Show on the chart"))

            Text(SensorCatalog.info(for: sensor.key).name)
            Text(sensor.key)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            // A bar as well as a number: the value is readable without reading the digits.
            GeometryReader { geometry in
                let ratio = min(max((sensor.value - 20) / 80, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule()
                        .fill(heatColor)
                        .frame(width: max(geometry.size.width * ratio, 3))
                }
            }
            .frame(width: 120, height: 6)

            Text(Format.temperatureFine(sensor.value))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var heatColor: Color {
        switch sensor.value {
        case ..<65: return Palette.calm
        case ..<85: return Palette.warning
        default: return Palette.critical
        }
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
