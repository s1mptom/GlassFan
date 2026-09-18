import SwiftUI
import FanKit

struct FansView: View {
    @Environment(DaemonClient.self) private var client
    @Environment(DaemonInstaller.self) private var installer
    /// Which fan the detail pane shows. Stored, so the overview can point the
    /// screen at a particular fan before switching to it.
    @AppStorage(FansView.selectedKey) private var selected: Int = 0
    static let selectedKey = "fans.selected"
    @State private var hoveredFan: Int?
    /// Per fan, which of its curves is being edited.
    @State private var editingCurve: [Int: Int] = [:]

    private var fans: [FanReading] { client.snapshot?.fans ?? [] }
    private var fan: FanReading? { fans.first { $0.index == selected } ?? fans.first }
    /// Empty on a Mac that reports no setpoints, and on a daemon too old to send them.
    private var zoneTargets: [SMCZoneTarget] {
        guard let snapshot = client.snapshot else { return [] }
        return snapshot.smcZoneTargets ?? []
    }

    var body: some View {
        if !client.isConnected {
            DaemonMissingNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if client.snapshot == nil {
            DataHint()
        } else if fans.isEmpty {
            NoFansNotice().frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Scrolls once it outgrows the window: three curve groups and, on an M3 Pro, the
    /// SMC's zone targets under them are taller than the window's height.
    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) { sidebarContent }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 212)
    }

    private var sidebarContent: some View {
        VStack(spacing: 12) {
            ForEach(fans) { item in
                fanRow(item)
            }
            if let fan, settings(for: fan).mode == .curve {
                CurveGroups(curves: binding(for: fan).curves,
                            editing: editingBinding(for: fan),
                            driving: fan.drivingCurve,
                            drivingTemp: fan.drivingTemp,
                            maxRPM: fan.limits.maxRPM)
            }
            if !zoneTargets.isEmpty {
                smcTargetBox(zoneTargets)
            }
        }
        .frame(width: 212)
    }

    /// What the SMC's own control is aiming for, whether or not we are holding the
    /// fans somewhere else.
    ///
    /// Beside the fans rather than on one of them: a zone is an engine, not a fan.
    /// On the M3 Pro, loading each engine alone showed one zone following the CPU and
    /// the other the GPU; that the count matches the number of fans is a coincidence.
    private func smcTargetBox(_ targets: [SMCZoneTarget]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: L10n.t("Автоматика SMC", "SMC's own control"))
            ForEach(targets) { target in
                HStack(spacing: 6) {
                    Text(SensorCatalog.smcZoneName(target.zone))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink.opacity(0.45))
                    Spacer(minLength: 0)
                    Text(Format.temperature(target.target))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink.opacity(0.8))
                }
            }
            Text(L10n.t("Температура, к которой ведёт штатное управление",
                        "What the automatic control steers towards"))
                .font(.system(size: 10))
                .foregroundStyle(Palette.ink.opacity(0.3))
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

    private func fanRow(_ item: FanReading) -> some View {
        let isSelected = item.index == (fan?.index ?? -1)
        return HStack(spacing: 14) {
            FanDial(rpm: item.actualRPM, limits: item.limits, controlled: item.forced,
                    alert: item.alerting,
                    size: 58, showsCaption: false, showsValue: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("Вентилятор \(item.index + 1)", "Fan \(item.index + 1)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                Text(Format.rpm(item.actualRPM))
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.forced ? Palette.ink : Palette.ink.opacity(0.86))
                Text(modeCaption(item))
                    .font(.system(size: 10.5))
                    .foregroundStyle(item.failureCaption != nil ? Palette.critical
                                     : item.forced ? Palette.calm : Palette.ink.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.ink.opacity(isSelected ? 0.075
                                          : (hoveredFan == item.index ? 0.055 : 0.03)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(isSelected ? 0.16
                                                      : (hoveredFan == item.index ? 0.12 : 0.07)),
                                  lineWidth: 0.5))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fan?.index)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredFan = inside ? item.index : (hoveredFan == item.index ? nil : hoveredFan)
            }
        }
        .onTapGesture { selected = item.index }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func modeCaption(_ item: FanReading) -> String {
        if let failure = item.failureCaption { return failure }
        switch item.mode {
        case .auto:  return L10n.t("система", "system")
        case .fixed: return L10n.t("фиксировано", "fixed")
        case .curve:
            if let driving = item.drivingCurve, settings(for: item).curves.count > 1 {
                return L10n.t("по кривой \(driving + 1)", "curve \(driving + 1)")
            }
            return L10n.t("по кривой", "curve")
        }
    }

    // MARK: Detail

    private func detail(_ fan: FanReading) -> some View {
        let settingsBinding = binding(for: fan)
        return VStack(alignment: .leading, spacing: 16) {
            if installer.status == .outdated {
                // Said where it bites: this is the screen whose settings the old
                // daemon will not honour.
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.heat)
                    Text(L10n.t("Установлен старый демон — эти настройки применит только новый. Настройки → Обновить.",
                                "An older daemon is installed; only the new one honours these settings. Settings → Update."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                    Spacer()
                    Button(L10n.t("Обновить", "Update")) { installer.install() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.heat.opacity(0.10)))
            }
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
                Text("0 – \(Format.rpm(fan.limits.maxRPM)) " + L10n.t("об/мин", "rpm")
                     + L10n.t(" · минимум SMC \(Format.rpm(fan.limits.minRPM))",
                              " · SMC minimum \(Format.rpm(fan.limits.minRPM))"))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.42))
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
            // The selector slides and the panel under it used to cut. A short
            // cross-fade ties the two halves of the same gesture together.
            .animation(.easeInOut(duration: 0.2), value: settingsBinding.wrappedValue.mode)

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
                .foregroundStyle(Palette.ink.opacity(0.3))
            Text(L10n.t("Вентилятором управляет система", "The system is in charge of this fan"))
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink.opacity(0.55))
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
                .foregroundStyle(Palette.ink)
            Text(L10n.t("об/мин", "rpm"))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.4))
                .offset(y: -18)
            // Rounded in the binding rather than declared as a step, which would
            // have the control draw a tick for every fifty rpm across the range.
            Slider(value: Binding(
                get: { settings.wrappedValue.fixedRPM },
                set: { settings.wrappedValue.fixedRPM = ($0 / 50).rounded() * 50 }
            ), in: 0...fan.limits.maxRPM) { editing in
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
        let editing = editingBinding(for: fan)
        let current = settings.wrappedValue.curves[editing.wrappedValue]
        return Group {
            if current.curve.points.isEmpty {
                VStack(spacing: 14) {
                    Text(L10n.t("Кривая ещё не задана", "No curve yet"))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                    Button(L10n.t("Создать кривую", "Create a curve")) {
                        settings.wrappedValue.curves[editing.wrappedValue].curve = .starter(maxRPM: fan.limits.maxRPM)
                        client.commit()
                    }
                    .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CurveEditor(
                    curves: settings.curves,
                    editing: editing,
                    driving: fan.drivingCurve,
                    limits: fan.limits,
                    currentTemp: fan.drivingTemp,
                    currentRPM: fan.actualRPM,
                    learnedFloor: fan.learnedFloor,
                    onCommit: { client.commit() }
                )
                .padding(16)
            }
        }
        .background(panelBackground)
    }

    /// Which of a fan's curves is being edited, kept per fan and within its curves.
    private func editingBinding(for fan: FanReading) -> Binding<Int> {
        Binding(
            get: { min(editingCurve[fan.index] ?? 0, settings(for: fan).curves.count - 1) },
            set: { editingCurve[fan.index] = $0 }
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Palette.ink.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.11), lineWidth: 0.5))
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
    /// Shares the Sensors screen's choice, so "All" there means all here too.
    @AppStorage(SensorsView.filterKey) private var filter: SensorFilter = .essential

    /// One flat list, so a row can travel between sections with an animation.
    ///
    /// Chosen sensors live at the top, under their own caption, and a sensor
    /// moves there the moment it is ticked - up out of its group, not the list
    /// scrolling to it. Sections were separate `ForEach`es before, and SwiftUI
    /// cannot animate a row from one of those to another; it can only remove it
    /// here and insert it there. A single `ForEach` over rows with stable ids
    /// makes the move a move.
    private enum Row: Identifiable {
        case caption(String, String)
        case sensor(SensorReading)
        var id: String {
            switch self {
            case .caption(let id, _): return "caption:" + id
            case .sensor(let reading): return "sensor:" + reading.key
            }
        }
    }

    /// In the catalogue's fixed order, never by reading: a list that reshuffles as
    /// temperatures move is a list whose next row is not where the pointer is going.
    private var rows: [Row] {
        let chosen = Set(selection)
        var picked: [(SensorInfo, SensorReading)] = []
        var buckets: [SensorGroup: [(SensorInfo, SensorReading)]] = [:]
        for sensor in client.snapshot?.sensors ?? [] {
            let info = SensorCatalog.info(for: sensor.key)
            if !search.isEmpty,
               !info.name.localizedCaseInsensitiveContains(search),
               !sensor.key.localizedCaseInsensitiveContains(search) { continue }
            if chosen.contains(sensor.key) {
                picked.append((info, sensor))
            } else if filter == .all || info.essential || !search.isEmpty {
                // A search looks through everything: typing a key is asking for it.
                buckets[info.group, default: []].append((info, sensor))
            }
        }

        var rows: [Row] = []
        if !picked.isEmpty {
            rows.append(.caption("chosen", L10n.t("Выбрано", "Chosen")))
            rows += picked.sorted { SensorCatalog.precedes($0.0, $1.0) }.map { Row.sensor($0.1) }
        }
        for group in SensorGroup.allCases {
            guard let sensors = buckets[group], !sensors.isEmpty else { continue }
            rows.append(.caption(group.rawValue, group.title))
            rows += sensors.sorted { SensorCatalog.precedes($0.0, $1.0) }.map { Row.sensor($0.1) }
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.ink.opacity(0.08))
                .frame(height: 0.5)

            let rows = self.rows
            if rows.isEmpty {
                empty
            } else {
                list(rows)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            GlassSearchField(
                placeholder: L10n.t("Поиск датчика", "Search sensors"),
                text: $search
            )

            HStack {
                GlassSegmented(
                    items: [.init(value: SensorFilter.essential, title: SensorFilter.essential.title),
                            .init(value: SensorFilter.all, title: SensorFilter.all.title)],
                    selection: Binding(get: { filter == .all ? .all : .essential },
                                       set: { filter = $0 }).animation(.smooth(duration: 0.3)),
                    segmentWidth: nil,
                    fontSize: 11
                )
                .fixedSize()
                Text(selection.isEmpty
                     ? L10n.t("ничего не выбрано", "none chosen")
                     : L10n.t("выбрано: \(selection.count)", "\(selection.count) chosen"))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.4))
                    .padding(.leading, 4)
                Spacer()
                if !selection.isEmpty {
                    Button(L10n.t("Снять все", "Clear all")) { selection.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.calm)
                }
            }
        }
        .padding(12)
    }

    private var empty: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.ink.opacity(0.25))
            Text(L10n.t("Ничего не нашлось", "Nothing matches"))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ rows: [Row]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { item in
                    switch item {
                    case .caption(_, let title):
                        SectionCaption(text: title)
                            .padding(.leading, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    case .sensor(let sensor):
                        row(sensor)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selection)
        }
        .scrollContentBackground(.hidden)
    }

    /// The whole row is the hit target, not a checkbox the width of a pea.
    private func row(_ sensor: SensorReading) -> some View {
        let isOn = selection.contains(sensor.key)
        return Button {
            if isOn { selection.removeAll { $0 == sensor.key } }
            else { selection.append(sensor.key) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? Palette.calm : Palette.ink.opacity(0.22))
                    .frame(width: 14)

                Text(SensorCatalog.info(for: sensor.key).name)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(isOn ? 0.95 : 0.78))
                    .lineLimit(1)

                Text(sensor.key)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.28))

                Spacer(minLength: 8)

                Text(Format.temperatureFine(sensor.value))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Palette.calm.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A Mac with no fan at all - every MacBook Air. "Collecting data" would spin
/// here for ever, waiting for a fan that is not coming.
struct NoFansNotice: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.ink.opacity(0.3))
            Text(L10n.t("В этом Mac нет вентиляторов", "This Mac has no fans"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.88))
            Text(L10n.t("Он охлаждается пассивно — управлять здесь нечем, но все датчики температуры на месте.",
                        "It is cooled passively, so there is nothing to control - but every temperature sensor is still here."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        .riseIn(0.05)
    }
}

