import SwiftUI
import FanKit

/// Which sensors the list shows.
enum SensorFilter: String, CaseIterable {
    /// The named parts - cores, GPU clusters, memory, heatsinks, drives, battery -
    /// plus anything the user charted. The rest are probes of those same parts,
    /// board diodes and virtual sensors: real, and noise to almost everyone.
    case essential
    case all
    case charted

    var title: String {
        switch self {
        case .essential: return L10n.t("Основные", "Essential")
        case .all:       return L10n.t("Все", "All")
        case .charted:   return L10n.t("На графике", "Charted")
        }
    }
}

/// The column the list is ordered by.
enum SensorSort: String, CaseIterable {
    case importance, key, temperature

    /// Hottest first is what anyone sorting by temperature is after; the others
    /// read top to bottom.
    var ascendingByDefault: Bool { self != .temperature }
}

struct SensorsView: View {
    static let filterKey = "sensors.filter"
    static let sortKey = "sensors.sort"
    static let ascendingKey = "sensors.ascending"

    @Environment(DaemonClient.self) private var client
    @AppStorage(SensorsView.filterKey) private var filter: SensorFilter = .essential
    @AppStorage(SensorsView.sortKey) private var sort: SensorSort = .importance
    @AppStorage(SensorsView.ascendingKey) private var ascending = true
    @State private var search = ""

    /// Temperature order, taken every few seconds rather than on every reading.
    ///
    /// Sorted live, the list reshuffled every second as two cores traded a tenth
    /// of a degree, and a row moved out from under the pointer on its way to it.
    /// Activity Monitor has the same problem with CPU and solves it the same way:
    /// the order holds still between refreshes.
    @State private var heatRank: [String: Int] = [:]

    /// Only sensors this Mac actually has: a charted key that does not exist here
    /// is not on the chart, and counting it made "charted" a lie.
    private var tracked: Set<String> {
        Set(client.config?.trackedSensors ?? [])
            .intersection((client.snapshot?.sensors ?? []).map(\.key))
    }

    private struct Listing {
        var groups: [(SensorGroup, [SensorReading])] = []
        var shown = 0
        /// Matches the search would find under "All" - offered when the current
        /// filter hides every one of them.
        var hiddenMatches = 0
    }

    /// Buckets, filters and orders the readings in a single pass.
    ///
    /// The order never depends on the readings themselves, except under the
    /// temperature column, and there only through `heatRank`.
    private var listing: Listing {
        let tracked = self.tracked
        var buckets: [SensorGroup: [(SensorInfo, SensorReading)]] = [:]
        var listing = Listing()
        for sensor in client.snapshot?.sensors ?? [] {
            let info = SensorCatalog.info(for: sensor.key)
            if !search.isEmpty,
               !info.name.localizedCaseInsensitiveContains(search),
               !sensor.key.localizedCaseInsensitiveContains(search) { continue }
            let included: Bool
            switch filter {
            case .essential: included = info.essential || tracked.contains(sensor.key)
            case .all:       included = true
            case .charted:   included = tracked.contains(sensor.key)
            }
            guard included else { listing.hiddenMatches += 1; continue }
            buckets[info.group, default: []].append((info, sensor))
            listing.shown += 1
        }

        let ascending = self.ascending
        let sort = self.sort
        let rank = heatRank
        listing.groups = SensorGroup.allCases.compactMap { group in
            guard let rows = buckets[group], !rows.isEmpty else { return nil }
            let ordered = rows.sorted { a, b in
                switch sort {
                case .importance:
                    return ascending ? SensorCatalog.precedes(a.0, b.0) : SensorCatalog.precedes(b.0, a.0)
                case .key:
                    return ascending ? a.0.key < b.0.key : a.0.key > b.0.key
                case .temperature:
                    // Rank 0 is the hottest. New sensors, not yet ranked, go last
                    // in either direction, in their usual order.
                    let ra = rank[a.0.key] ?? .max, rb = rank[b.0.key] ?? .max
                    if ra != rb {
                        if ra == .max || rb == .max { return ra < rb }
                        return ascending ? ra > rb : ra < rb
                    }
                    return SensorCatalog.precedes(a.0, b.0)
                }
            }
            return (group, ordered.map(\.1))
        }
        return listing
    }

    var body: some View {
        if !client.isConnected {
            DaemonMissingNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let listing = self.listing
            VStack(spacing: 0) {
                toolbar(listing).riseIn(0.02)
                columnHeader.riseIn(0.03)
                if listing.groups.isEmpty {
                    noMatches(listing)
                } else {
                    sensorList(listing.groups)
                }
            }
            .task(id: sort) { await keepHeatRank() }
        }
    }

    /// Re-ranks by temperature while that column is the sort, every five seconds,
    /// with the rows gliding to their new places.
    private func keepHeatRank() async {
        guard sort == .temperature else { return }
        // Straight away when the screen opens already sorted this way.
        if heatRank.isEmpty { heatRank = currentHeatRank() }
        while !Task.isCancelled {
            // Until the first readings arrive there is nothing to rank; look again
            // soon rather than in five seconds.
            try? await Task.sleep(for: .seconds(heatRank.isEmpty ? 0.5 : 5))
            guard !Task.isCancelled else { break }
            let rank = currentHeatRank()
            if rank != heatRank {
                withAnimation(heatRank.isEmpty ? nil : .smooth(duration: 0.45)) { heatRank = rank }
            }
        }
    }

    private func currentHeatRank() -> [String: Int] {
        let ranked = (client.snapshot?.sensors ?? []).sorted { $0.value > $1.value }
        return Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.key, $0) })
    }

    private func noMatches(_ listing: Listing) -> some View {
        let chartedEmpty = filter == .charted && search.isEmpty
        return VStack(spacing: 8) {
            Image(systemName: chartedEmpty ? "chart.line.uptrend.xyaxis" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.ink.opacity(0.25))
            Text(chartedEmpty
                 ? L10n.t("На графике пока ничего нет", "Nothing is on the chart yet")
                 : L10n.t("Ничего не нашлось", "Nothing matches"))
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink.opacity(0.45))
            if chartedEmpty {
                Text(L10n.t("Отметьте датчик значком графика слева от названия.",
                            "Mark a sensor with the chart icon to the left of its name."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.3))
            } else if listing.hiddenMatches > 0 {
                // The search found something, just not under this filter: say so,
                // instead of "nothing" for a sensor that is one click away.
                Button(L10n.t("Показать среди всех: \(listing.hiddenMatches)",
                              "Show \(listing.hiddenMatches) among all sensors")) {
                    withAnimation(.smooth(duration: 0.3)) { filter = .all }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.top, 4)
            } else {
                Text(L10n.t("Попробуйте другое название или ключ датчика.",
                            "Try another name, or the sensor key."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.3))
            }
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
        let tracked = self.tracked
        return ScrollView {
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

    private func toolbar(_ listing: Listing) -> some View {
        let total = client.snapshot?.sensors.count ?? 0
        return HStack(spacing: 14) {
            GlassSearchField(
                placeholder: L10n.t("Поиск по \(total) датчикам", "Search \(total) sensors"),
                text: $search
            )

            GlassSegmented(
                items: SensorFilter.allCases.map { .init(value: $0, title: $0.title) },
                selection: $filter.animation(.smooth(duration: 0.3)),
                segmentWidth: nil,
                fontSize: 11.5
            )
            .fixedSize()

            Spacer()

            Text(L10n.t("\(listing.shown) из \(total)", "\(listing.shown) of \(total)"))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.3))
                .contentTransition(.identity)
        }
        .padding(.horizontal, 30)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Column titles that sort the list, lined up over the row's own columns.
    /// Clicking the sorted column again reverses it, as in Finder and Activity Monitor.
    private var columnHeader: some View {
        HStack(spacing: SensorRow.spacing) {
            Color.clear.frame(width: SensorRow.markerWidth, height: 1)
            header(L10n.t("Датчик", "Sensor"), sort: .importance)
                .frame(width: SensorRow.nameWidth, alignment: .leading)
            header(L10n.t("Ключ", "Key"), sort: .key)
                .frame(width: SensorRow.keyWidth, alignment: .leading)
            Spacer(minLength: 0)
            header(L10n.t("Температура", "Temperature"), sort: .temperature)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 0.5)
                .padding(.horizontal, 22)
        }
    }

    private func arrow(visible: Bool) -> some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .rotationEffect(.degrees(ascending ? 180 : 0))
            .opacity(visible ? 1 : 0)
    }

    private func header(_ title: String, sort column: SensorSort) -> some View {
        let active = sort == column
        return Button {
            withAnimation(.smooth(duration: 0.35)) {
                if active {
                    ascending.toggle()
                } else {
                    // Ranked in the same transaction, so the rows travel straight
                    // to their temperature order instead of via the old one.
                    if column == .temperature { heatRank = currentHeatRank() }
                    sort = column
                    ascending = column.ascendingByDefault
                }
            }
        } label: {
            // The arrow sits on the inner side of the title, so a right-aligned
            // title still ends exactly over the numbers beneath it.
            HStack(spacing: 4) {
                if column == .temperature { arrow(visible: active) }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.6)
                if column != .temperature { arrow(visible: active) }
            }
            .foregroundStyle(Palette.ink.opacity(active ? 0.7 : 0.38))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isHeader, .isSelected] : .isHeader)
        .accessibilityHint(L10n.t("Сортировать по этой колонке", "Sort by this column"))
    }
}

struct SensorRow: View {
    static let spacing: CGFloat = 14
    static let markerWidth: CGFloat = 14
    static let nameWidth: CGFloat = 250
    static let keyWidth: CGFloat = 46

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
        let info = SensorCatalog.info(for: sensor.key)
        HStack(spacing: Self.spacing) {
            Button(action: toggleTracking) {
                Image(systemName: tracked ? "chart.line.uptrend.xyaxis" : "circle.dotted")
                    .font(.system(size: 11, weight: .medium))
                    // Untracked sensors keep their marker nearly invisible until the
                    // pointer is on the row, so a list of 228 of them is not 228 dots.
                    .foregroundStyle(tracked ? Palette.calm
                                             : Palette.ink.opacity(hovering ? 0.5 : 0.22))
                    .frame(width: Self.markerWidth, height: 14)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Показывать на графике", "Show on the chart"))
            .accessibilityLabel(L10n.t("Показывать на графике", "Show on the chart"))
            .accessibilityValue(tracked ? L10n.t("включено", "on") : L10n.t("выключено", "off"))

            // Probes and diodes a step quieter than the parts they belong to, so
            // under "All" the named rows still read first.
            Text(info.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink.opacity(tracked ? 0.9 : info.essential ? 0.78 : 0.55))
                .frame(width: Self.nameWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(info.name)

            Text(sensor.key)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.3))
                .frame(width: Self.keyWidth, alignment: .leading)

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
        .accessibilityLabel("\(info.name), "
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
