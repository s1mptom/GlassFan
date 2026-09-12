import SwiftUI
import FanKit

struct SensorsView: View {
    @Environment(DaemonClient.self) private var client
    @State private var search = ""
    @State private var onlyCharted = false

    private var tracked: Set<String> { Set(client.config?.trackedSensors ?? []) }

    private var groups: [(SensorGroup, [SensorReading])] {
        SensorGroup.allCases.compactMap { group in
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
        if !client.isConnected {
            DaemonMissingNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                toolbar.riseIn(0.02)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groups, id: \.0) { group, sensors in
                            VStack(alignment: .leading, spacing: 0) {
                                SectionCaption(text: group.title)
                                    .padding(.bottom, 8)
                                ForEach(sensors) { sensor in
                                    SensorRow(sensor: sensor, tracked: tracked.contains(sensor.key))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                TextField(L10n.t("Поиск по \(client.snapshot?.sensors.count ?? 0) датчикам",
                                 "Search \(client.snapshot?.sensors.count ?? 0) sensors"),
                          text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.11), lineWidth: 0.5))
            )

            Toggle(L10n.t("Только на графике", "On the chart only"), isOn: $onlyCharted)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(L10n.t("на графике: \(tracked.count)", "charted: \(tracked.count)"))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.3))
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

    private var ratio: Double { min(max((sensor.value - 20) / 80, 0), 1) }

    private var barColor: Color {
        switch sensor.value {
        case ..<70: return tracked ? Palette.calm : .white.opacity(0.35)
        case ..<85: return Palette.heat
        default:    return Palette.critical
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggleTracking) {
                Image(systemName: tracked ? "chart.line.uptrend.xyaxis" : "circle.dotted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tracked ? Palette.calm : .white.opacity(0.22))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Показывать на графике", "Show on the chart"))

            Text(SensorCatalog.info(for: sensor.key).name)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(tracked ? 0.9 : 0.72))
                .frame(width: 186, alignment: .leading)
                .lineLimit(1)

            Text(sensor.key)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 46, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(geometry.size.width * ratio, 3))
                        .animation(.easeOut(duration: 0.5), value: ratio)
                }
            }
            .frame(height: 3)

            Text(Format.temperatureFine(sensor.value))
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(tracked ? 1 : 0.78))
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
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
