# Several Curves per Fan, and One Glass Drop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each fan follow up to three curves, each over its own group of sensors, at the fastest of them — edited from sensor-group cards whose selection is the app's glass drop, which becomes one shared shader-and-springs framework for both the segmented control and the new list.

**Architecture:** FanKit gains `CurveRule` and `FanSettings.curves` (old single-curve JSON migrates in and is still written out for old daemons); `FanController` takes the max over curves with per-curve hysteresis and reports the winner. The Metal shader's shape goes from a horizontal capsule to a two-box "drop" with a smooth join; a new `GlassDrop.swift` holds everything both drops share (geometry, refraction modifier, light painter, frame clock), `GlassSegmented` is moved onto it unchanged in behaviour, and `GlassDropList` is the vertical, tailed, sticky drop. `CurveEditor` draws all curves with numbered ends; `CurveGroups` replaces the sidebar's sensor box.

**Tech Stack:** Swift 6 / SwiftPM, SwiftUI (macOS 26), Metal stitchable shaders via `ShaderLibrary`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-18-multi-curve-fans-design.md`

## Global Constraints

- macOS 26+, Apple silicon; builds on Xcode 26.6 in CI and Xcode 27 locally — no API newer than macOS 26.
- 1...3 curves per fan (`FanSettings.maxCurves = 3`); 2...10 points per curve (`FanCurve.minPoints = 2`, `FanCurve.maxPoints = 10`).
- A new curve: 40 °C → 0 rpm, 90 °C → the fan's maximum.
- Config decoding accepts the old `sensorKeys` + `curve` shape; encoding writes `curves` **and** curve 1 in the old keys.
- Hysteresis and smoothing stay per fan; hysteresis is held per curve; smoothing applies to the max.
- Emergency: any assigned sensor in any group ≥ `emergencyTemp`.
- Colours: edited = `Palette.calm`, driving = `Palette.heat`, idle = `Palette.ink.opacity(0.28)` dashed.
- Glass: neutral, as `GlassSegmented`'s. The shader functions stay `glassLens` / `glassLight`.
- All user-facing text through `L10n.t("ru", "en")`.
- Tests: `swift test` (FanKitTests, GlassFanUITests). Never leave test settings in `com.glassfan.app`.
- Commits end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/FanKit/Config.swift` | modify | `CurveRule`, `FanSettings.curves`, migration, dual encoding |
| `Sources/FanKit/Curve.swift` | modify | point limits, `starter(maxRPM:)` replaces `defaultCurve` |
| `Sources/FanKit/FanController.swift` | modify | max over curves, per-curve hysteresis, `lastDrivingCurve` |
| `Sources/FanKit/Protocol.swift` | modify | `FanReading.drivingCurve` |
| `Sources/fanctld/Daemon.swift` | modify | report `drivingCurve`, track all groups, version 0.1.13 |
| `Sources/GlassFanUI/Shaders/GlassLens.metal` | modify | drop shape (two boxes + neck, smooth union) |
| `Sources/GlassFanUI/GlassDrop.swift` | create | `DropGeometry`, `DropOutline`, `GlassDropRefraction`, `GlassDropLight`, `FrameClock`, `LensSpring`, `LensShaders` |
| `Sources/GlassFanUI/GlassSegmented.swift` | modify | use the shared pieces; behaviour unchanged |
| `Sources/GlassFanUI/DropListMath.swift` | create | pure maths of the vertical drop |
| `Sources/GlassFanUI/GlassDropList.swift` | create | the vertical drop list and its state |
| `Sources/GlassFanUI/CurveNumbers.swift` | create | `CurveNumber` badge, `CurveNumberLayout` |
| `Sources/GlassFanUI/CurveEditor.swift` | modify | all curves, numbered ends, edit one |
| `Sources/GlassFanUI/CurveGroups.swift` | create | the sidebar's group cards |
| `Sources/GlassFanUI/FansView.swift` | modify | wire groups + editor, caption |
| `Sources/GlassFanUI/DemoFixture.swift`, `DaemonClient.swift`, `Previews.swift` | modify | three-curve fixture and previews |
| `Tests/FanKitTests/ConfigTests.swift`, `CurveTests.swift`, `ControllerTests.swift`, `ProtocolTests.swift` | modify | model + control tests |
| `Tests/GlassFanUITests/DropListMathTests.swift`, `CurveNumberLayoutTests.swift`, `DropGeometryTests.swift` | create | UI maths tests |

---

### Task 1: Curves in the config

**Files:**
- Modify: `Sources/FanKit/Config.swift` (`FanSettings`, `AppConfig.default`)
- Modify: `Sources/FanKit/Curve.swift` (editing section, `defaultCurve`)
- Modify: `Sources/fanctld/Daemon.swift:406`, `Sources/GlassFanUI/DaemonClient.swift:150`, `Sources/GlassFanUI/DemoFixture.swift:57-58`, `Sources/GlassFanUI/FansView.swift` (sensorBox + curvePanel use curve 1 for now)
- Test: `Tests/FanKitTests/ConfigTests.swift`, `Tests/FanKitTests/CurveTests.swift`

**Interfaces:**
- Produces: `public struct CurveRule { var sensorKeys: [String]; var curve: FanCurve; init(sensorKeys: [String] = [], curve: FanCurve) }`; `FanSettings.curves: [CurveRule]` (never empty); `FanSettings.maxCurves = 3`; `FanSettings.allSensorKeys: [String]`; `FanSettings.init(id:mode:fixedRPM:curves:hysteresis:smoothing:)`; the old `init(id:mode:fixedRPM:sensorKeys:curve:hysteresis:smoothing:)` kept as a convenience; `FanCurve.minPoints = 2`, `FanCurve.maxPoints = 10`, `FanCurve.starter(maxRPM:)`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FanKitTests/ConfigTests.swift` inside the suite:

```swift
    @Test("a config written before curves were grouped comes through as curve one")
    func migratesSingleCurve() throws {
        let json = #"""
        {"id":0,"mode":"curve","fixedRPM":2000,"sensorKeys":["Ts0P","Ts1P"],
         "curve":[{"temperature":40,"rpm":0},{"temperature":80,"rpm":3000}],
         "hysteresis":2,"smoothing":0.3}
        """#
        let settings = try JSONDecoder().decode(FanSettings.self, from: Data(json.utf8))
        #expect(settings.curves.count == 1)
        #expect(settings.curves[0].sensorKeys == ["Ts0P", "Ts1P"])
        #expect(settings.curves[0].curve.points.count == 2)
    }

    @Test("curve one is written in the old shape too, for a daemon that predates groups")
    func writesBothShapes() throws {
        let settings = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [
            CurveRule(sensorKeys: ["Ts0P"], curve: .starter(maxRPM: 5000)),
            CurveRule(sensorKeys: ["TCMz"], curve: .starter(maxRPM: 5000)),
        ], hysteresis: 2, smoothing: 0.3)
        let data = try JSONEncoder().encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["sensorKeys"] as? [String] == ["Ts0P"])
        #expect((object["curve"] as? [Any])?.count == 2)
        #expect((object["curves"] as? [Any])?.count == 2)
        #expect(try JSONDecoder().decode(FanSettings.self, from: data) == settings)
    }

    @Test("no more than three curves, and never none")
    func curveCount() {
        let rule = CurveRule(curve: .starter(maxRPM: 5000))
        let many = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: Array(repeating: rule, count: 5),
                               hysteresis: 2, smoothing: 0)
        #expect(many.curves.count == FanSettings.maxCurves)
        let none = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [], hysteresis: 2, smoothing: 0)
        #expect(none.curves.count == 1)
    }

    @Test("a sensor in two groups is listed once")
    func allSensorKeys() {
        let settings = FanSettings(id: 0, mode: .curve, fixedRPM: 2000, curves: [
            CurveRule(sensorKeys: ["A", "B"], curve: .starter(maxRPM: 5000)),
            CurveRule(sensorKeys: ["B", "C"], curve: .starter(maxRPM: 5000)),
        ], hysteresis: 2, smoothing: 0)
        #expect(settings.allSensorKeys == ["A", "B", "C"])
    }
```

Append to `Tests/FanKitTests/CurveTests.swift` inside the suite:

```swift
    @Test("a new curve is two points: resting when cool, full speed when hot")
    func starter() {
        let curve = FanCurve.starter(maxRPM: 5776)
        #expect(curve.points == [CurvePoint(temperature: 40, rpm: 0), CurvePoint(temperature: 90, rpm: 5776)])
    }

    @Test("points stop at ten and do not go below two")
    func pointLimits() {
        var curve = FanCurve.starter(maxRPM: 5000)
        curve.removePoint(at: 0)
        #expect(curve.points.count == 2)
        for t in stride(from: 45.0, through: 85.0, by: 5) { curve.addPoint(CurvePoint(temperature: t, rpm: 1000)) }
        #expect(curve.points.count == FanCurve.maxPoints)
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter "ConfigTests|CurveTests" 2>&1 | tail -20`
Expected: build errors — `CurveRule`, `curves:`, `starter`, `maxCurves`, `allSensorKeys` not found.

- [ ] **Step 3: Implement the model**

In `Sources/FanKit/Curve.swift`, replace the `// MARK: Editing` section through the end of the struct with:

```swift
    // MARK: Editing

    /// A curve is a line, so it needs two points; past ten it is fiddling, not shaping.
    public static let minPoints = 2
    public static let maxPoints = 10

    public mutating func movePoint(at index: Int, to point: CurvePoint) {
        guard points.indices.contains(index) else { return }
        points[index] = point
        points.sort { $0.temperature < $1.temperature }
    }

    public mutating func addPoint(_ point: CurvePoint) {
        guard points.count < Self.maxPoints else { return }
        points.append(point)
        points.sort { $0.temperature < $1.temperature }
    }

    public mutating func removePoint(at index: Int) {
        guard points.indices.contains(index), points.count > Self.minPoints else { return }
        points.remove(at: index)
    }

    /// What a new curve starts as: at rest while cool - the hardware stops at zero, as
    /// the system's own controller stops it - and flat out when hot. Two points, so it
    /// is shaped by adding what it needs rather than by clearing out what it does not.
    public static func starter(maxRPM: Double) -> FanCurve {
        FanCurve(points: [
            CurvePoint(temperature: 40, rpm: 0),
            CurvePoint(temperature: 90, rpm: maxRPM),
        ])
    }
}
```

In `Sources/FanKit/Config.swift`, replace the whole `public struct FanSettings { ... }` with:

```swift
/// One of a fan's curves: a group of sensors, the hottest of which is read against
/// `curve`. A fan runs at the fastest of its curves.
public struct CurveRule: Codable, Equatable, Sendable {
    public var sensorKeys: [String]
    public var curve: FanCurve

    public init(sensorKeys: [String] = [], curve: FanCurve) {
        self.sensorKeys = sensorKeys
        self.curve = curve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sensorKeys = try c.decodeIfPresent([String].self, forKey: .sensorKeys) ?? []
        curve = try c.decodeIfPresent(FanCurve.self, forKey: .curve) ?? FanCurve(points: [])
    }
}

public struct FanSettings: Codable, Equatable, Sendable, Identifiable {
    public static let maxCurves = 3

    public var id: Int
    public var mode: FanMode
    public var fixedRPM: Double
    /// One to three, each over its own sensors. Never empty.
    public var curves: [CurveRule] {
        didSet { curves = Self.normalised(curves) }
    }
    /// How far the temperature must fall before the target follows it down, in degrees.
    public var hysteresis: Double
    /// 0 applies the demand at once; values towards 1 ease into it.
    public var smoothing: Double

    /// Every sensor any of the curves reads, each once, in the order first met.
    public var allSensorKeys: [String] {
        var seen = Set<String>()
        return curves.flatMap(\.sensorKeys).filter { seen.insert($0).inserted }
    }

    public init(id: Int, mode: FanMode, fixedRPM: Double, curves: [CurveRule],
                hysteresis: Double, smoothing: Double) {
        self.id = id
        self.mode = mode
        self.fixedRPM = fixedRPM
        self.curves = Self.normalised(curves)
        self.hysteresis = hysteresis
        self.smoothing = smoothing
    }

    /// A fan with one curve, as every fan had before curves were grouped.
    public init(id: Int, mode: FanMode, fixedRPM: Double, sensorKeys: [String],
                curve: FanCurve, hysteresis: Double, smoothing: Double) {
        self.init(id: id, mode: mode, fixedRPM: fixedRPM,
                  curves: [CurveRule(sensorKeys: sensorKeys, curve: curve)],
                  hysteresis: hysteresis, smoothing: smoothing)
    }

    private static func normalised(_ curves: [CurveRule]) -> [CurveRule] {
        let kept = Array(curves.prefix(maxCurves))
        return kept.isEmpty ? [CurveRule(curve: FanCurve(points: []))] : kept
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, fixedRPM, curves, sensorKeys, curve, hysteresis, smoothing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mode = try c.decodeIfPresent(FanMode.self, forKey: .mode) ?? .auto
        fixedRPM = try c.decodeIfPresent(Double.self, forKey: .fixedRPM) ?? 2000
        // Written before curves were grouped: the one curve and its sensors are curve one.
        if let grouped = try c.decodeIfPresent([CurveRule].self, forKey: .curves), !grouped.isEmpty {
            curves = Self.normalised(grouped)
        } else {
            curves = [CurveRule(
                sensorKeys: try c.decodeIfPresent([String].self, forKey: .sensorKeys) ?? [],
                curve: try c.decodeIfPresent(FanCurve.self, forKey: .curve) ?? FanCurve(points: []))]
        }
        hysteresis = min(max(try c.decodeIfPresent(Double.self, forKey: .hysteresis) ?? 2, 0), 20)
        smoothing = min(max(try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.3, 0), 0.95)
    }

    /// Curve one goes out a second time under the old keys. A daemon from before groups
    /// reads only those, and drives by curve one instead of by nothing.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(mode, forKey: .mode)
        try c.encode(fixedRPM, forKey: .fixedRPM)
        try c.encode(curves, forKey: .curves)
        try c.encode(curves[0].sensorKeys, forKey: .sensorKeys)
        try c.encode(curves[0].curve, forKey: .curve)
        try c.encode(hysteresis, forKey: .hysteresis)
        try c.encode(smoothing, forKey: .smoothing)
    }
}
```

Call sites:
- `Sources/fanctld/Daemon.swift` (history tracking): `config.fans.flatMap(\.sensorKeys)` → `config.fans.flatMap(\.allSensorKeys)`.
- `Sources/GlassFanUI/DaemonClient.swift:150`: same replacement.
- `Sources/GlassFanUI/DemoFixture.swift:57-58`:
  ```swift
  config.fans[0].curves = [CurveRule(sensorKeys: ["TCMz", "Th02"],
                                     curve: .starter(maxRPM: limits0.maxRPM))]
  ```
- `Sources/GlassFanUI/FansView.swift` (temporary, replaced in Task 9): in `sensorBox`, `current.sensorKeys` → `current.curves[0].sensorKeys` and `binding(for: fan).sensorKeys` → `binding(for: fan).curves[0].sensorKeys` (three places); in `curvePanel`, `settings.wrappedValue.curve` → `settings.wrappedValue.curves[0].curve`, `.defaultCurve(minRPM: fan.limits.minRPM, maxRPM: fan.limits.maxRPM)` → `.starter(maxRPM: fan.limits.maxRPM)`, `curve: settings.curve` → `curve: settings.curves[0].curve`.

- [ ] **Step 4: Run the tests**

Run: `swift build 2>&1 | grep -E "error|warning: unre" ; swift test 2>&1 | tail -5`
Expected: build clean; all tests pass (the earlier 128 plus 6 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/FanKit/Config.swift Sources/FanKit/Curve.swift Sources/fanctld/Daemon.swift Sources/GlassFanUI/DaemonClient.swift Sources/GlassFanUI/DemoFixture.swift Sources/GlassFanUI/FansView.swift Tests/FanKitTests/ConfigTests.swift Tests/FanKitTests/CurveTests.swift
git commit -m "Give a fan up to three curves, each over its own sensors

An old config comes through as curve one, and curve one is still written
the old way, so a daemon from before groups keeps driving by it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The fan follows the fastest curve

**Files:**
- Modify: `Sources/FanKit/FanController.swift`
- Modify: `Sources/FanKit/Protocol.swift` (`FanReading`)
- Modify: `Sources/fanctld/Daemon.swift` (`version`, the `FanReading(` in `tick`)
- Test: `Tests/FanKitTests/ControllerTests.swift`, `Tests/FanKitTests/ProtocolTests.swift`

**Interfaces:**
- Consumes: `FanSettings.curves`, `CurveRule` (Task 1).
- Produces: `FanController.lastDrivingCurve: Int?`; `FanReading.drivingCurve: Int?` and init parameter `drivingCurve: Int? = nil` (last in the list).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FanKitTests/ControllerTests.swift` inside the suite:

```swift
    /// Palm rests on a gentle ramp, the CPU on a steep one.
    func twoCurves(hysteresis: Double = 0) -> FanSettings {
        FanSettings(id: 0, mode: .curve, fixedRPM: 3000, curves: [
            CurveRule(sensorKeys: ["Ts0P"], curve: FanCurve(points: [
                CurvePoint(temperature: 30, rpm: 0), CurvePoint(temperature: 40, rpm: 2000)])),
            CurveRule(sensorKeys: ["TCMz"], curve: FanCurve(points: [
                CurvePoint(temperature: 60, rpm: 2500), CurvePoint(temperature: 85, rpm: 5000)])),
        ], hysteresis: hysteresis, smoothing: 0)
    }

    @Test("the fan runs at the fastest of its curves, and says which")
    func fastestCurveWins() {
        var c = FanController(settings: twoCurves(), limits: limits)
        // Palm rest 33 -> 600 rpm; CPU 72 -> 3700 rpm.
        #expect(c.update(temperatures: ["Ts0P": 33, "TCMz": 72], emergencyTemp: 95) == 3700)
        #expect(c.lastDrivingCurve == 1)
        #expect(c.lastDrivingTemp == 72)
        // CPU idle: 45 is below its first point, so it asks 2500; the palm rests at 40 ask 2000.
        #expect(c.update(temperatures: ["Ts0P": 40, "TCMz": 45], emergencyTemp: 95) == 2500)
        #expect(c.lastDrivingCurve == 1)
    }

    @Test("a curve with nothing to read sits out")
    func unreadableCurveSitsOut() {
        var c = FanController(settings: twoCurves(), limits: limits)
        #expect(c.update(temperatures: ["Ts0P": 35], emergencyTemp: 95) == 1000)
        #expect(c.lastDrivingCurve == 0)
    }

    @Test("each curve holds its own temperature against hysteresis")
    func hysteresisPerCurve() {
        let flat = FanCurve(points: [CurvePoint(temperature: 40, rpm: 1000), CurvePoint(temperature: 80, rpm: 5000)])
        let settings = FanSettings(id: 0, mode: .curve, fixedRPM: 0, curves: [
            CurveRule(sensorKeys: ["a"], curve: flat), CurveRule(sensorKeys: ["b"], curve: flat),
        ], hysteresis: 2, smoothing: 0)
        var c = FanController(settings: settings, limits: limits)
        #expect(c.update(temperatures: ["a": 60, "b": 50], emergencyTemp: 95) == 3000)
        // a falls well past its band (-> 40, 1000 rpm); b slips within its own and is held at 50 (2000 rpm).
        #expect(c.update(temperatures: ["a": 40, "b": 49], emergencyTemp: 95) == 2000)
        #expect(c.lastDrivingCurve == 1)
    }

    @Test("any sensor in any group past the emergency point sends the fan to full")
    func emergencyFromAnyGroup() {
        var c = FanController(settings: twoCurves(), limits: limits)
        #expect(c.update(temperatures: ["Ts0P": 97, "TCMz": 50], emergencyTemp: 95) == limits.maxRPM)
        #expect(c.isEmergency)
        #expect(c.lastDrivingCurve == 0)
    }
```

Append to `Tests/FanKitTests/ProtocolTests.swift` inside the suite:

```swift
    @Test("which curve is driving survives the wire, and is absent from an older daemon")
    func drivingCurve() throws {
        let reading = FanReading(index: 0, actualRPM: 2000, targetRPM: 2000,
                                 limits: FanLimits(minRPM: 1499, maxRPM: 5348), mode: .curve,
                                 forced: true, drivingTemp: 72, emergency: false, drivingCurve: 1)
        let data = try JSONEncoder().encode(reading)
        #expect(try JSONDecoder().decode(FanReading.self, from: data).drivingCurve == 1)
        let old = #"{"index":0,"actualRPM":0,"targetRPM":0,"limits":{"minRPM":0,"maxRPM":1},"mode":"curve","forced":false,"emergency":false}"#
        #expect(try JSONDecoder().decode(FanReading.self, from: Data(old.utf8)).drivingCurve == nil)
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter "ControllerTests|ProtocolTests" 2>&1 | tail -20`
Expected: build errors — `lastDrivingCurve`, `drivingCurve:` not found.

- [ ] **Step 3: Implement**

`Sources/FanKit/Protocol.swift`, in `FanReading`: add after `acquiring`:

```swift
    /// Which of the fan's curves set the target, when it is following curves. Absent
    /// from a daemon older than grouped curves.
    public var drivingCurve: Int?
```

extend the init signature with `, drivingCurve: Int? = nil` after `learnedFloor: Double? = nil`, and assign `self.drivingCurve = drivingCurve`.

`Sources/FanKit/FanController.swift`: replace `private var heldTemp: Double?` with

```swift
    /// Per curve: the temperature that produced the demand it is holding, for hysteresis.
    /// Per curve because a cooling group must not drag another group's hold down with it.
    private var heldTemps: [Int: Double] = [:]
```

add `public private(set) var lastDrivingCurve: Int?` after `lastDrivingTemp`; in `reset()` replace `heldTemp = nil` with `heldTemps = [:]` and add `lastDrivingCurve = nil`; in `.auto` and `.fixed` replace `heldTemp = nil` (auto) with `heldTemps = [:]`, set `lastDrivingCurve = nil` in both, and use `settings.allSensorKeys` via `assignedMax`. Replace the whole `case .curve:` branch and the helpers below it with:

```swift
        case .curve:
            let temps = settings.curves.map { hottest(of: $0.sensorKeys, in: temperatures) }
            guard let hottestAnywhere = temps.compactMap({ $0 }).max() else {
                // Nothing to steer by - safer to let the system have the fan back.
                heldTemps = [:]
                lastTarget = nil
                lastDrivingTemp = nil
                lastDrivingCurve = nil
                return nil
            }

            if hottestAnywhere >= emergencyTemp {
                isEmergency = true
                let index = temps.firstIndex { $0 == hottestAnywhere }!
                heldTemps[index] = hottestAnywhere
                lastDrivingCurve = index
                lastDrivingTemp = hottestAnywhere
                lastTarget = limits.maxRPM
                return limits.maxRPM
            }

            // Each curve asks for a speed; the fan runs at the fastest. A tie goes to
            // the earlier curve, so the one reported does not flicker between equals.
            var winner: (index: Int, demand: Double)?
            for (index, rule) in settings.curves.enumerated() {
                guard let temp = temps[index] else { heldTemps[index] = nil; continue }
                let effective = applyHysteresis(to: temp, curve: index)
                guard let demand = rule.curve.rpm(at: effective) else { continue }
                if winner == nil || demand > winner!.demand { winner = (index, demand) }
            }
            guard let winner else {
                heldTemps = [:]
                lastTarget = nil
                lastDrivingTemp = nil
                lastDrivingCurve = nil
                return nil
            }
            lastDrivingCurve = winner.index
            lastDrivingTemp = temps[winner.index]

            let target = applySmoothing(to: limits.clamp(winner.demand))
            lastTarget = target
            return target
        }
    }

    private func hottest(of keys: [String], in temperatures: [String: Double]) -> Double? {
        keys.compactMap { temperatures[$0] }.max()
    }

    private func assignedMax(_ temperatures: [String: Double]) -> Double? {
        hottest(of: settings.allSensorKeys, in: temperatures)
    }

    /// Rises follow the temperature at once; falls wait until it has dropped past the band.
    private mutating func applyHysteresis(to temp: Double, curve: Int) -> Double {
        guard let held = heldTemps[curve] else {
            heldTemps[curve] = temp
            return temp
        }
        if temp > held || held - temp >= settings.hysteresis {
            heldTemps[curve] = temp
            return temp
        }
        return held
    }
```

(keep `applySmoothing` as it is; delete the old single-curve `applyHysteresis`.)

`Sources/fanctld/Daemon.swift`: `static let version = "0.1.13"`; in the `readings.append(FanReading(` call add `drivingCurve: controller.settings.mode == .curve ? controller.lastDrivingCurve : nil` after `learnedFloor: ...`.

- [ ] **Step 4: Run the tests**

Run: `swift test 2>&1 | tail -5`
Expected: all pass, including the existing controller tests (the single-curve init still builds one curve).

- [ ] **Step 5: Commit**

```bash
git add Sources/FanKit/FanController.swift Sources/FanKit/Protocol.swift Sources/fanctld/Daemon.swift Tests/FanKitTests/ControllerTests.swift Tests/FanKitTests/ProtocolTests.swift
git commit -m "Run a fan at the fastest of its curves, and say which one that is

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The shader's drop shape

**Files:**
- Modify: `Sources/GlassFanUI/Shaders/GlassLens.metal`
- Modify: `Sources/GlassFanUI/GlassSegmented.swift` (the two shader calls, `LensRefraction.body` and `Lens.body`)

**Interfaces:**
- Produces: shader signatures
  `glassLens(float2 position, SwiftUI::Layer layer, float4 head, float4 tail, float radius, float neck, float magnification, float lift, float motion, float darkInk)` and
  `glassLight(float2 position, half4 color, float4 head, float4 tail, float radius, float neck, float lift, float motion, float darkInk)`.
  `head`/`tail` are x, y, width, height; `radius` the corner radius; `neck` the radius of the bridge between their centres (0: none). head == tail, radius = height / 2, neck = 0 is exactly the old capsule.

- [ ] **Step 1: Replace the shape in the shader**

In `GlassLens.metal` replace `struct CapsuleHit` and `capsule()` with:

```metal
struct DropHit {
    float dist;       // signed distance to the rim: negative inside
    float2 outward;   // unit normal of the rim, pointing out
};

/// A rectangle with rounded corners; `box` is x, y, width, height.
static float roundBox(float2 p, float4 box, float radius) {
    float2 halfSize = box.zw * 0.5;
    float2 centre = box.xy + halfSize;
    float r = min(radius, min(halfSize.x, halfSize.y));
    float2 q = abs(p - centre) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float segmentDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

/// A minimum that melts two shapes into one where they come within `k` of each other.
static float smoothMin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// The drop: a head and a tail, each a rounded box, and between their centres a bridge
/// of radius `neck`, all melted together - so a drop pulled out of one place into
/// another necks between them the way a liquid does. With the tail on the head, a
/// radius of half the height and no neck, it is a capsule.
static float dropDist(float2 p, float4 head, float4 tail, float radius, float neck) {
    float d = roundBox(p, head, radius);
    if (any(head != tail)) {
        const float k = 8.0;
        d = smoothMin(d, roundBox(p, tail, radius), k);
        if (neck > 0.0) {
            d = smoothMin(d, segmentDist(p, head.xy + head.zw * 0.5, tail.xy + tail.zw * 0.5) - neck, k);
        }
    }
    return d;
}

/// The distance, and the rim's normal from the distance's slope.
static DropHit drop(float2 p, float4 head, float4 tail, float radius, float neck) {
    DropHit hit;
    hit.dist = dropDist(p, head, tail, radius, neck);
    const float e = 0.5;
    float2 slope = float2(
        dropDist(p + float2(e, 0.0), head, tail, radius, neck) - dropDist(p - float2(e, 0.0), head, tail, radius, neck),
        dropDist(p + float2(0.0, e), head, tail, radius, neck) - dropDist(p - float2(0.0, e), head, tail, radius, neck));
    float l = length(slope);
    hit.outward = l > 1e-4 ? slope / l : float2(0.0, 1.0);
    return hit;
}

/// The drop's thickness: its narrowest side. The bevel is cut from half of it.
static float thickness(float4 head, float4 tail) {
    return min(min(head.z, head.w), min(tail.z, tail.w));
}
```

In `glassLens`, change the signature to
`half4 glassLens(float2 position, SwiftUI::Layer layer, float4 head, float4 tail, float radius, float neck, float magnification, float lift, float motion, float darkInk)` and replace its first lines up to `bool dark = ...` with:

```metal
    half4 original = layer.sample(position);
    float4 bounds = float4(min(head.xy, tail.xy), 0.0, 0.0);
    bounds.zw = max(head.xy + head.zw, tail.xy + tail.zw) - bounds.xy;
    float2 halfSize = bounds.zw * 0.5;
    float2 centre = bounds.xy + halfSize;
    float half_ = thickness(head, tail) * 0.5;
    if (lift <= 0.002 || half_ <= 0.5) { return original; }

    DropHit shape = drop(position, head, tail, radius, neck);
    if (shape.dist > 2.5) { return original; }

    float2 normal = shape.outward;
    float2 tangent = float2(-normal.y, normal.x);
    float depth = max(-shape.dist, 0.0);
    bool dark = darkInk > 0.5;
```

and in the same function `float bevel = min(radius * 0.95, 18.0);` → `float bevel = min(half_ * 0.95, 18.0);`.

In `glassLight`, change the signature to
`half4 glassLight(float2 position, half4 color, float4 head, float4 tail, float radius, float neck, float lift, float motion, float darkInk)` and replace its first lines up to `float bevel = ...;` with:

```metal
    float half_ = thickness(head, tail) * 0.5;
    if (lift <= 0.002 || half_ <= 0.5) { return half4(0.0); }
    DropHit shape = drop(position, head, tail, radius, neck);
    if (shape.dist > 2.5) { return half4(0.0); }

    bool dark = darkInk > 0.5;
    float depth = max(-shape.dist, 0.0);
    float bevel = min(half_ * 0.95, 18.0);
```

- [ ] **Step 2: Pass the capsule from the segmented control**

In `GlassSegmented.swift`, `LensRefraction.body`: the `library.glassLens(` arguments become

```swift
                    library.glassLens(
                        .float4(rect.minX, rect.minY, rect.width, rect.height),
                        .float4(rect.minX, rect.minY, rect.width, rect.height),
                        .float(rect.height / 2),
                        .float(0),
                        .float(geometry.magnification),
                        .float(min(geometry.lift, 1)),
                        .float(geometry.motion),
                        .float(colorScheme == .light ? 1 : 0)
                    ),
```

and in `Lens.body` the `library.glassLight(` arguments become

```swift
                        .colorEffect(library.glassLight(
                            .float4(lens.minX, lens.minY, lens.width, lens.height),
                            .float4(lens.minX, lens.minY, lens.width, lens.height),
                            .float(lens.height / 2),
                            .float(0),
                            .float(min(geometry.lift, 1)),
                            .float(geometry.motion),
                            .float(colorScheme == .light ? 1 : 0)
                        ))
```

- [ ] **Step 3: Build and check the lens is unchanged**

Run: `swift build 2>&1 | grep -E "error" ; Scripts/build-app.sh >/dev/null && echo built`
Expected: no errors, `built` (the script compiles the shader and fails if the metallib is missing).
Then render the `Segmented lens` preview (`Sources/GlassFanUI/GlassSegmented.swift`, scheme `GlassFanUI`) and compare with `docs/lens.png`: same rim, refraction, colour fringes, glare.

- [ ] **Step 4: Commit**

```bash
git add Sources/GlassFanUI/Shaders/GlassLens.metal Sources/GlassFanUI/GlassSegmented.swift
git commit -m "Cut the glass from a drop shape rather than a capsule

Two rounded boxes and a bridge, melted together. With the tail on the head it
is the capsule the segmented control has always had.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: One glass framework for both drops

**Files:**
- Create: `Sources/GlassFanUI/GlassDrop.swift`
- Modify: `Sources/GlassFanUI/GlassSegmented.swift` (move `LensSpring`, `LensShaders` out; replace `LensRefraction` and `Lens` with the shared ones; `LensState.advance` uses `FrameClock`)
- Test: `Tests/GlassFanUITests/DropGeometryTests.swift`

**Interfaces:**
- Consumes: shader signatures from Task 3.
- Produces:
  - `struct DropGeometry: Equatable { var head: CGRect; var tail: CGRect; var cornerRadius: CGFloat; var neck: CGFloat; var lift: CGFloat; var motion: CGFloat; var maxMagnification: CGFloat; static func capsule(_ rect: CGRect, lift: CGFloat, motion: CGFloat) -> DropGeometry; var bounds: CGRect; var magnification: CGFloat; var isVisible: Bool; var outline: Path; func offsetBy(dx: CGFloat, dy: CGFloat) -> DropGeometry }`
  - `struct DropOutline: Shape { let geometry: DropGeometry }`
  - `struct GlassDropRefraction: ViewModifier { let geometry: DropGeometry? }`
  - `struct GlassDropLight: View { let geometry: DropGeometry; let pointer: CGPoint; let size: CGSize }`
  - `struct FrameClock { mutating func reset(); mutating func advance(to time: TimeInterval) -> (count: Int, dt: CGFloat)? }`
  - `LensSpring`, `LensShaders` (moved, unchanged).

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlassFanUITests/DropGeometryTests.swift`:

```swift
import Testing
import SwiftUI
@testable import GlassFanUI

@Suite("Drop geometry")
struct DropGeometryTests {
    @Test("a capsule is one box with a radius of half its height")
    func capsule() {
        let rect = CGRect(x: 10, y: 4, width: 96, height: 30)
        let drop = DropGeometry.capsule(rect, lift: 1, motion: 0)
        #expect(drop.head == rect && drop.tail == rect)
        #expect(drop.cornerRadius == 15)
        #expect(drop.neck == 0)
        #expect(drop.bounds == rect)
    }

    @Test("the outline covers head, tail and the bridge between them")
    func outline() {
        let drop = DropGeometry(head: CGRect(x: 0, y: 0, width: 100, height: 40),
                                tail: CGRect(x: 0, y: 80, width: 100, height: 40),
                                cornerRadius: 14, neck: 10, lift: 1)
        let path = drop.outline
        #expect(path.contains(CGPoint(x: 50, y: 20)))
        #expect(path.contains(CGPoint(x: 50, y: 100)))
        #expect(path.contains(CGPoint(x: 50, y: 60)))   // the neck
        #expect(!path.contains(CGPoint(x: 5, y: 60)))   // beside the neck, in the gap
    }

    @Test("the frame clock steps each frame once, and no more than a thirtieth of a second")
    func frameClock() {
        var clock = FrameClock()
        #expect(clock.advance(to: 10, now: 0.5) == nil)   // the first call only starts it
        let step = clock.advance(to: 10.5, now: 1)!
        #expect(abs(CGFloat(step.count) * step.dt - 1.0 / 30) < 1e-6)
        #expect(clock.advance(to: 10.6, now: 1.001) == nil)   // same frame: another view asking
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter DropGeometryTests 2>&1 | tail -10`
Expected: build errors — `DropGeometry`, `FrameClock` not found.

- [ ] **Step 3: Create `GlassDrop.swift`**

Move `struct LensSpring` and `enum LensShaders` verbatim out of `GlassSegmented.swift` into the new file, then add:

```swift
import SwiftUI

/// Hands out one step of time per display frame, however many views ask for it.
///
/// A drop is drawn by three views - the glass under the content, the refraction, the
/// light over it - and each asks for the frame it is drawing. Their timelines hand
/// them times up to 3 ms apart within one frame; stepped to each, the three parts
/// were drawn a point or two apart, by a different amount every frame, and a fast drop
/// shimmered. The first to ask in a frame steps the springs; the others, arriving
/// within a few milliseconds, get the same drop.
struct FrameClock {
    private var steppedTo: TimeInterval = 0
    private var askedAt: TimeInterval = -1

    mutating func reset() { steppedTo = 0 }

    /// Sub-steps to advance by, or nil when this frame has been stepped already.
    /// `now` is the process's uptime; tests pass their own.
    mutating func advance(to time: TimeInterval,
                          now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (count: Int, dt: CGFloat)? {
        guard now - askedAt > 0.004 else { return nil }
        askedAt = now
        guard time > steppedTo else { return nil }
        // After a stall - a screen being built - the drop carries on from where it
        // was, rather than leaping to where it would have got to.
        let elapsed = steppedTo == 0 ? 0 : min(time - steppedTo, 1.0 / 30)
        steppedTo = time
        guard elapsed > 0 else { return nil }
        let count = Int((elapsed * 480).rounded(.up))
        return (count, CGFloat(elapsed) / CGFloat(count))
    }
}

/// Where a drop of glass is and how far it has lifted: a head and a tail, each a
/// rounded box, joined by a bridge. The segmented control's drop is a capsule - one
/// box, round-ended; the list's is drawn out between two rows.
struct DropGeometry: Equatable {
    var head: CGRect
    var tail: CGRect
    var cornerRadius: CGFloat
    /// Radius of the bridge between head and tail; 0 for none.
    var neck: CGFloat = 0
    /// 0 for a platter at rest, 1 for the drop fully up.
    var lift: CGFloat
    /// Speed along the way it moves, -1...1: the light swings and the colours part with it.
    var motion: CGFloat = 0
    var maxMagnification: CGFloat = 1.3

    static func capsule(_ rect: CGRect, lift: CGFloat, motion: CGFloat) -> DropGeometry {
        DropGeometry(head: rect, tail: rect, cornerRadius: rect.height / 2, lift: lift, motion: motion)
    }

    var bounds: CGRect { head.union(tail) }
    var magnification: CGFloat { 1 + (maxMagnification - 1) * min(lift, 1) }
    var isVisible: Bool { lift > 0.002 }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> DropGeometry {
        var moved = self
        moved.head = head.offsetBy(dx: dx, dy: dy)
        moved.tail = tail.offsetBy(dx: dx, dy: dy)
        return moved
    }

    /// The shape for glass and shadow behind the shader's drop: its boxes and bridge,
    /// joined. The shader melts the joins; at these sizes a sharp join under a soft
    /// rim cannot be told from it.
    var outline: Path {
        func box(_ rect: CGRect) -> Path {
            Path(roundedRect: rect, cornerRadius: min(cornerRadius, rect.width / 2, rect.height / 2),
                 style: .continuous)
        }
        guard tail != head else { return box(head) }
        var shape = box(head).union(box(tail))
        if neck > 0 {
            let bridge = Path { path in
                path.move(to: CGPoint(x: head.midX, y: head.midY))
                path.addLine(to: CGPoint(x: tail.midX, y: tail.midY))
            }.strokedPath(StrokeStyle(lineWidth: neck * 2, lineCap: .round))
            shape = shape.union(bridge)
        }
        return shape
    }

    fileprivate func shaderShape(_ rect: CGRect) -> Shader.Argument {
        .float4(rect.minX, rect.minY, rect.width, rect.height)
    }
}

struct DropOutline: Shape {
    let geometry: DropGeometry
    func path(in rect: CGRect) -> Path { geometry.outline }
}

/// Refracts what is under the drop, on the GPU. Off whenever the drop is down: a
/// layer effect renders the view offscreen, and a resting control has no business
/// paying for that.
struct GlassDropRefraction: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry?

    /// Room around the content for the parts of the drop that reach past it.
    private let room: CGFloat = 16

    func body(content: Content) -> some View {
        if let library = LensShaders.library {
            let geometry = (geometry ?? DropGeometry(head: .zero, tail: .zero, cornerRadius: 0, lift: 0))
                .offsetBy(dx: room, dy: room)
            let bounds = geometry.bounds
            let thick = min(geometry.head.width, geometry.head.height, geometry.tail.width, geometry.tail.height)
            content
                .padding(room)
                .layerEffect(
                    Shader(function: ShaderFunction(library: library, name: "glassLens"), arguments: [
                        geometry.shaderShape(geometry.head),
                        geometry.shaderShape(geometry.tail),
                        .float(geometry.cornerRadius),
                        .float(geometry.neck),
                        .float(geometry.magnification),
                        .float(min(geometry.lift, 1)),
                        .float(geometry.motion),
                        // The ink follows the scheme: dark labels in light mode.
                        .float(colorScheme == .light ? 1 : 0),
                    ]),
                    // How far the drop reaches for what it shows: the magnified body,
                    // the bend of the rim, and the reflection beside it.
                    maxSampleOffset: CGSize(width: bounds.width * 0.3 + thick + 8,
                                            height: bounds.height * 0.3 + thick + 8),
                    isEnabled: geometry.isVisible
                )
                .padding(-room)
        } else {
            content
        }
    }
}

/// The light on the drop and what it casts: glare, edge and shading worked out from
/// its shape by the shader, its shadow on what is below, and a bloom under the pointer.
///
/// Painted in one `Canvas` rather than built from views: as a shadow, masks and a
/// dozen strokes, the lens was rebuilt as a view tree on every frame, and that, not
/// the drawing, was what moving it cost.
struct GlassDropLight: View {
    @Environment(\.colorScheme) private var colorScheme
    let geometry: DropGeometry
    let pointer: CGPoint
    /// The area the drop moves over, in the same coordinates as `geometry`.
    let size: CGSize

    /// Room around the area for what reaches past it: the lifted drop, its shadow.
    private let margin: CGFloat = 16

    var body: some View {
        if geometry.isVisible {
            let drop = geometry.offsetBy(dx: margin, dy: margin)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: margin, y: margin)
                    paint(in: &context)
                }
                if let library = LensShaders.library {
                    Rectangle()
                        .fill(.white)
                        .colorEffect(Shader(function: ShaderFunction(library: library, name: "glassLight"), arguments: [
                            drop.shaderShape(drop.head),
                            drop.shaderShape(drop.tail),
                            .float(drop.cornerRadius),
                            .float(drop.neck),
                            .float(min(drop.lift, 1)),
                            .float(drop.motion),
                            .float(colorScheme == .light ? 1 : 0),
                        ]))
                }
            }
            .frame(width: size.width + margin * 2, height: size.height + margin * 2)
            .offset(x: -margin, y: -margin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func paint(in context: inout GraphicsContext) {
        let outline = geometry.outline
        // Faster than the glass shrinks, so a landing drop never shows two edges.
        let edges = geometry.lift * geometry.lift
        paintShadow(in: &context, outline: outline, opacity: edges)
        context.drawLayer { layer in
            layer.opacity = edges
            layer.clip(to: outline)
            paintBloom(in: &layer)
        }
    }

    /// Cast on what is below, and kept off the inside of the drop: seen through clear
    /// glass, a shadow underneath reads as a smudge.
    private func paintShadow(in context: inout GraphicsContext, outline: Path, opacity: CGFloat) {
        context.drawLayer { layer in
            layer.opacity = opacity
            var outside = Path(CGRect(x: -margin, y: -margin,
                                      width: size.width + margin * 2, height: size.height + margin * 2))
            outside.addPath(outline)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            let box = geometry.bounds.insetBy(dx: -7, dy: -6).offsetBy(dx: 0, dy: 3)
            let radius = box.height / 2
            layer.translateBy(x: box.midX, y: box.midY)
            layer.scaleBy(x: box.width / box.height, y: 1)
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                                                                    location: 0.6),
                                                              .init(color: .black.opacity(0), location: 1)]),
                                             center: .zero, startRadius: 0, endRadius: radius))
        }
    }

    /// A soft bloom under the pointer - the response system glass gives to a touch.
    private func paintBloom(in context: inout GraphicsContext) {
        let dark = colorScheme == .dark
        context.blendMode = dark ? .plusLighter : .normal
        let bounds = geometry.bounds
        let short = min(bounds.width, bounds.height)
        let radius = short * 0.8
        let inner = bounds.insetBy(dx: min(short * 0.3, bounds.width / 2), dy: min(short * 0.3, bounds.height / 2))
        let at = CGPoint(x: min(max(pointer.x, inner.minX), inner.maxX),
                         y: min(max(pointer.y, inner.minY), inner.maxY))
        context.fill(Path(ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(dark ? 0.08 : 0.16), .white.opacity(0)]),
                                           center: at, startRadius: 0, endRadius: radius))
    }
}
```

- [ ] **Step 4: Move the segmented control onto it**

In `GlassSegmented.swift`:
- Delete `struct LensSpring`, `enum LensShaders`, `private struct LensRefraction`, `private struct Lens`.
- In `LensState`, replace `steppedTo`/`askedAt` with `@ObservationIgnored private var clock = FrameClock()`; in `engage` replace `steppedTo = 0` with `clock.reset()`; replace the first seven lines of `advance(to:)` (through `let dt = ...`) with
  ```swift
          guard let step = clock.advance(to: time) else { return }
          let steps = step.count, dt = step.dt
  ```
  (keep the rest of `advance` and the doc comment's second paragraph; drop its first paragraph, now on `FrameClock`).
- Add to `LensGeometry`:
  ```swift
      var drop: DropGeometry { .capsule(rect, lift: lift, motion: motion) }
  ```
- `LensRefracted.body`: `content.modifier(GlassDropRefraction(geometry: lens.engaged ? lens.geometry(at: context.date, band: band).drop : nil))`.
- `LensOverlay.body`: 
  ```swift
              TimelineView(.animation) { context in
                  let geometry = lens.geometry(at: context.date, band: band)
                  GlassDropLight(geometry: geometry.drop,
                                 pointer: CGPoint(x: lens.pointer, y: geometry.rect.midY),
                                 size: rowSize)
              }
  ```

- [ ] **Step 5: Run the tests and look at the lens**

Run: `swift test 2>&1 | tail -5 && Scripts/build-app.sh >/dev/null && echo built`
Expected: all pass, `built`. Render the `Segmented lens` preview: identical to Task 3's.

- [ ] **Step 6: Commit**

```bash
git add Sources/GlassFanUI/GlassDrop.swift Sources/GlassFanUI/GlassSegmented.swift Tests/GlassFanUITests/DropGeometryTests.swift
git commit -m "Share one glass drop between everything that has one

Geometry, refraction, light, springs and the frame clock move out of the
segmented control, which now draws with them and looks as it did.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: How a drop moves down a list

**Files:**
- Create: `Sources/GlassFanUI/DropListMath.swift`
- Test: `Tests/GlassFanUITests/DropListMathTests.swift`

**Interfaces:**
- Produces: `enum DropListMath` with
  `static func owner(of y: CGFloat, in rows: [CGRect]) -> Int`,
  `static func stick(_ y: CGFloat, in rows: [CGRect]) -> CGFloat`,
  `static func gapness(at y: CGFloat, in rows: [CGRect]) -> CGFloat`,
  `static func thinned(_ size: CGSize, speed: CGFloat, gapness: CGFloat) -> CGSize`,
  `static func cornerRadius(rest: CGFloat, speed: CGFloat) -> CGFloat`.
  `rows` are in order top to bottom and non-empty.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlassFanUITests/DropListMathTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import GlassFanUI

@Suite("Drop list motion")
struct DropListMathTests {
    /// Three rows of different heights with 8 pt gaps: 0-60, 68-100, 108-140.
    let rows = [CGRect(x: 0, y: 0, width: 180, height: 60),
                CGRect(x: 0, y: 68, width: 180, height: 32),
                CGRect(x: 0, y: 108, width: 180, height: 32)]

    @Test("a row owns down to the middle of the gap on either side")
    func owner() {
        #expect(DropListMath.owner(of: 30, in: rows) == 0)
        #expect(DropListMath.owner(of: 63.9, in: rows) == 0)
        #expect(DropListMath.owner(of: 64, in: rows) == 1)
        #expect(DropListMath.owner(of: 500, in: rows) == 2)
        #expect(DropListMath.owner(of: -50, in: rows) == 0)
    }

    @Test("held, the drop hangs back near its row's middle, then gives")
    func sticks() {
        #expect(DropListMath.stick(30, in: rows) == 30)
        // Halfway from the middle (30) to the edge of row 0's stretch (64): an eighth of the way.
        #expect(abs(DropListMath.stick(47, in: rows) - 34.25) < 0.01)
        // At the edge it has caught up with the pointer.
        #expect(abs(DropListMath.stick(63.99, in: rows) - 63.99) < 0.1)
    }

    @Test("passing from one row's pull to the next, the drop does not jump")
    func continuous() {
        let before = DropListMath.stick(63.999, in: rows)
        let after = DropListMath.stick(64.001, in: rows)
        #expect(abs(before - after) < 0.05)
    }

    @Test("over a row there is no pinch; four points into a gap, full pinch")
    func gapness() {
        #expect(DropListMath.gapness(at: 30, in: rows) == 0)
        #expect(DropListMath.gapness(at: 62, in: rows) == 0.5)
        #expect(DropListMath.gapness(at: 64, in: rows) == 1)
    }

    @Test("faster is thinner and shorter, and never thinner than a seventh")
    func thinned() {
        let size = CGSize(width: 180, height: 60)
        #expect(DropListMath.thinned(size, speed: 0, gapness: 0) == size)
        let fast = DropListMath.thinned(size, speed: 2000, gapness: 1)
        #expect(abs(fast.width - 180 * 0.14) < 0.001)
        #expect(abs(fast.height - 36) < 0.001)
    }

    @Test("corners open towards a pill with speed")
    func corners() {
        #expect(DropListMath.cornerRadius(rest: 14, speed: 0) == 14)
        #expect(DropListMath.cornerRadius(rest: 14, speed: 1000) == 74)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter DropListMathTests 2>&1 | tail -10`
Expected: build error — `DropListMath` not found.

- [ ] **Step 3: Implement**

Create `Sources/GlassFanUI/DropListMath.swift`:

```swift
import CoreGraphics
import Foundation

/// The motion of a drop moving down a list, as plain numbers, so it can be tested
/// without drawing anything. `rows` are the rows' frames, top to bottom.
enum DropListMath {
    /// The row whose stretch holds `y`: each gap is split down its middle, so a tall
    /// row and a short one each own what is theirs, not whatever is nearer a centre.
    static func owner(of y: CGFloat, in rows: [CGRect]) -> Int {
        for index in 0..<(rows.count - 1) where y < (rows[index].maxY + rows[index + 1].minY) / 2 {
            return index
        }
        return rows.count - 1
    }

    /// Where a held drop sits for a pointer at `y`.
    ///
    /// It sticks to the row it is over: inside the row's stretch it lags the pointer
    /// on a steep curve, so it barely leaves the row's middle until the pointer is
    /// most of the way out - then it gives and runs to the edge, where the next row's
    /// own curve takes it from the other side. The two curves meet at the boundary,
    /// so the drop never jumps.
    static func stick(_ y: CGFloat, in rows: [CGRect]) -> CGFloat {
        let index = owner(of: y, in: rows)
        let row = rows[index]
        let above = index > 0 ? (rows[index - 1].maxY + row.minY) / 2 : row.minY
        let below = index < rows.count - 1 ? (row.maxY + rows[index + 1].minY) / 2 : row.maxY
        let offset = y - row.midY
        let reach = offset >= 0 ? below - row.midY : row.midY - above
        guard reach > 0 else { return row.midY }
        let t = min(abs(offset) / reach, 1)
        return row.midY + (offset < 0 ? -1 : 1) * reach * t * t * t
    }

    /// 0 over a row, rising to 1 four points out into a gap.
    static func gapness(at y: CGFloat, in rows: [CGRect]) -> CGFloat {
        let distance = rows.map { row in y < row.minY ? row.minY - y : y > row.maxY ? y - row.maxY : 0 }.min() ?? 0
        return min(distance / 4, 1)
    }

    /// The size a moving part of the drop reaches for: thinner and shorter the faster
    /// it goes, pinched further over a gap, and never thinner than a seventh.
    static func thinned(_ size: CGSize, speed: CGFloat, gapness: CGFloat) -> CGSize {
        let pace = min(abs(speed) / 750, 1)
        let width = size.width * max(0.14, (1 - 0.86 * pace) * (1 - 0.7 * gapness))
        return CGSize(width: width, height: size.height * (1 - 0.4 * pace))
    }

    /// Moving, the drop gives up the row's corners and rounds towards a pill; at rest
    /// it is the row's shape. The shader holds the radius to half the drop's size.
    static func cornerRadius(rest: CGFloat, speed: CGFloat) -> CGFloat {
        rest + min(abs(speed) / 250, 1) * 60
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter DropListMathTests 2>&1 | tail -5`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlassFanUI/DropListMath.swift Tests/GlassFanUITests/DropListMathTests.swift
git commit -m "Work out how a drop flows down a list and sticks to a row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The vertical glass drop list

**Files:**
- Create: `Sources/GlassFanUI/GlassDropList.swift`

**Interfaces:**
- Consumes: `DropGeometry`, `DropOutline`, `GlassDropRefraction`, `GlassDropLight`, `FrameClock`, `LensSpring` (Task 4); `DropListMath` (Task 5).
- Produces: `struct GlassDropList<Row: View>: View { init(count: Int, selection: Binding<Int>, spacing: CGFloat = 8, cornerRadius: CGFloat = 14, @ViewBuilder row: @escaping (Int) -> Row) }`.

- [ ] **Step 1: Write the list**

Create `Sources/GlassFanUI/GlassDropList.swift`:

```swift
import SwiftUI

/// A vertical list whose selection is a drop of glass: the segmented control's drop
/// turned on end, with a tail. Click a row and the drop flows to it - the head goes
/// first and thins with speed, the tail follows on a softer spring, and between two
/// rows the pair necks; on arrival it spreads to the row's full size and settles into
/// a platter. Pick it up and it follows the pointer, sticking to the row it is over.
///
/// The glass is the segmented control's own: the same shader, light and springs.
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
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        }
        .background(alignment: .topLeading) {
            DropGlass(drop: drop, rows: rows, resting: frames[selection], cornerRadius: cornerRadius,
                      size: size, selection: selection)
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
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                guard measured else { return }
                let rows = self.rows
                if !drop.pressing {
                    let pressed = DropListMath.owner(of: value.startLocation.y, in: rows)
                    begin(from: frames[selection]!)
                    drop.pressing = true
                    drop.target = pressed
                    drop.grabOffset = value.startLocation.y - drop.headY.value
                    drop.pointer = value.location
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
                guard measured else { return }
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
        let token = drop.token, target = drop.target, drop = self.drop
        drop.onArrival = { land(on: target, token: token) }
        // Springs only step while the drop is drawn. Should it stop being drawn, the
        // choice still counts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard drop.token == token, let arrival = drop.onArrival else { return }
            drop.onArrival = nil
            arrival()
        }
    }

    private func land(on index: Int, token: Int) {
        let drop = self.drop
        guard drop.token == token, !drop.pressing else { return }
        if index != selection, index < count { selection = index }
        drop.lift.tune(response: 0.36, dampingFraction: 0.9)
        drop.lift.target = 0
        drop.onSettled = {
            if drop.token == token, !drop.pressing { drop.engaged = false }
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
    @ObservationIgnored var target = 0
    @ObservationIgnored var token = 0
    @ObservationIgnored var onArrival: (() -> Void)?
    @ObservationIgnored var onSettled: (() -> Void)?
    @ObservationIgnored private var clock = FrameClock()

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
        for spring in [\DropListState.headY, \.tailY] { self[keyPath: spring].jump(to: frame.midY) }
        for spring in [\DropListState.headW, \.tailW] { self[keyPath: spring].jump(to: frame.width) }
        for spring in [\DropListState.headH, \.tailH] { self[keyPath: spring].jump(to: frame.height) }
        lift.jump(to: 0)
        pointer = CGPoint(x: frame.midX, y: frame.midY)
        clock.reset()
        engaged = true
    }

    func geometry(at date: Date, rows: [CGRect]) -> DropGeometry {
        advance(to: date.timeIntervalSinceReferenceDate, rows: rows)
        let up = max(lift.value, 0)
        // Grown a little past the row as it lifts, as the segmented drop grows past its track.
        func box(_ y: LensSpring, _ w: LensSpring, _ h: LensSpring) -> CGRect {
            CGRect(x: x - w.value / 2, y: y.value - h.value / 2, width: w.value, height: h.value)
                .insetBy(dx: -3 * up, dy: -3 * up)
        }
        let apart = abs(headY.value - tailY.value)
        return DropGeometry(
            head: box(headY, headW, headH),
            tail: box(tailY, tailW, tailH),
            cornerRadius: DropListMath.cornerRadius(rest: rowRadius,
                                                    speed: max(abs(headY.velocity), abs(tailY.velocity))),
            neck: apart > 2 ? min(headW.value, tailW.value) * 0.15 : 0,
            lift: up,
            motion: min(max(headY.velocity / 1200, -1), 1),
            maxMagnification: 1.08)
    }

    private func advance(to time: TimeInterval, rows: [CGRect]) {
        guard !rows.isEmpty, let step = clock.advance(to: time) else { return }
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
            headW.target = head.width; headH.target = head.height
            tailW.target = tail.width; tailH.target = tail.height
            for spring in [\DropListState.headW, \.headH, \.tailW, \.tailH] { self[keyPath: spring].step(step.dt) }
            lift.step(step.dt)
        }

        // Handed to the next turn of the run loop: they change state, and this runs
        // while the drop's views are being drawn.
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

private struct DropRefracted<Content: View>: View {
    let drop: DropListState
    let rows: [CGRect]
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !drop.engaged)) { context in
            content.modifier(GlassDropRefraction(geometry: drop.engaged ? drop.geometry(at: context.date, rows: rows) : nil))
        }
    }
}

/// Under the rows: the platter on the selected row at rest; in play, the drop's own
/// glass, with the platter fading out of it as it lifts.
private struct DropGlass: View {
    let drop: DropListState
    let rows: [CGRect]
    let resting: CGRect?
    let cornerRadius: CGFloat
    let size: CGSize
    let selection: Int

    var body: some View {
        if drop.engaged {
            TimelineView(.animation) { context in
                let geometry = drop.geometry(at: context.date, rows: rows)
                ZStack(alignment: .topLeading) {
                    platter(geometry.head).opacity(1 - min(geometry.lift, 1))
                    Color.clear
                        .frame(width: size.width, height: size.height)
                        .glassEffect(.clear, in: DropOutline(geometry: geometry))
                        .opacity(min(geometry.lift, 1))
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

private struct DropLight: View {
    let drop: DropListState
    let rows: [CGRect]
    let size: CGSize

    var body: some View {
        if drop.engaged {
            TimelineView(.animation) { context in
                GlassDropLight(geometry: drop.geometry(at: context.date, rows: rows), pointer: drop.pointer, size: size)
            }
        }
    }
}

// MARK: - Preview

#Preview("Glass drop list") {
    @Previewable @State var selection = 0
    GlassDropList(count: 3, selection: $selection) { index in
        Text("Group \(index + 1)")
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: index == 0 ? 64 : 40, alignment: .leading)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink.opacity(0.025)))
    }
    .frame(width: 184)
    .padding(24)
    .background(Color(red: 0.12, green: 0.14, blue: 0.19))
}
```

- [ ] **Step 2: Build and try it**

Run: `swift build 2>&1 | grep error ; Scripts/build-app.sh >/dev/null && echo built`
Expected: no errors, `built`.
Render the `Glass drop list` preview; run it live in the Xcode canvas: click rows (drop flows, necks, lands), drag the selected row (sticks, then gives), release between rows (lands on the owner).

- [ ] **Step 3: Commit**

```bash
git add Sources/GlassFanUI/GlassDropList.swift
git commit -m "Add a list whose selection is the glass drop, flowing between rows

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Numbers at the ends of the curves

**Files:**
- Create: `Sources/GlassFanUI/CurveNumbers.swift`
- Test: `Tests/GlassFanUITests/CurveNumberLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum CurveRole { case editing, driving, idle; static func of(_ index: Int, editing: Int, driving: Int?) -> CurveRole }` — editing wins over driving.
  - `struct CurveNumber: View { init(number: Int, role: CurveRole, size: CGFloat = 16) }`
  - `enum CurveNumberLayout { struct Placed: Equatable { var index: Int; var lineY: CGFloat; var y: CGFloat }; static func place(ends: [CGFloat], editing: Int, spacing: CGFloat = 20, within range: ClosedRange<CGFloat>) -> [Placed] }` — result sorted by `index`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/GlassFanUITests/CurveNumberLayoutTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import GlassFanUI

@Suite("Curve numbers")
struct CurveNumberLayoutTests {
    let range: ClosedRange<CGFloat> = 8...256

    @Test("numbers far apart stay at their lines' ends")
    func apart() {
        let placed = CurveNumberLayout.place(ends: [8, 120, 200], editing: 0, within: range)
        #expect(placed.map(\.y) == [8, 120, 200])
    }

    @Test("two curves ending together: the edited number keeps its place, the other steps down")
    func overlapping() {
        let placed = CurveNumberLayout.place(ends: [8, 8], editing: 1, within: range)
        #expect(placed[1].y == 8)
        #expect(placed[0].y == 28)
        #expect(placed[0].lineY == 8)
    }

    @Test("at the floor the other number steps up instead")
    func atFloor() {
        let placed = CurveNumberLayout.place(ends: [256, 256], editing: 0, within: range)
        #expect(placed[0].y == 256)
        #expect(placed[1].y == 236)
    }

    @Test("three together fan out, twenty points apart")
    func three() {
        let ys = CurveNumberLayout.place(ends: [8, 8, 8], editing: 2, within: range).map(\.y).sorted()
        #expect(ys == [8, 28, 48])
    }

    @Test("the edited curve is blue even when it is the one driving")
    func roles() {
        #expect(CurveRole.of(1, editing: 1, driving: 1) == .editing)
        #expect(CurveRole.of(0, editing: 1, driving: 0) == .driving)
        #expect(CurveRole.of(2, editing: 1, driving: 0) == .idle)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter CurveNumberLayoutTests 2>&1 | tail -10`
Expected: build error — `CurveNumberLayout` not found.

- [ ] **Step 3: Implement**

Create `Sources/GlassFanUI/CurveNumbers.swift`:

```swift
import SwiftUI

/// What a curve is doing, which is what colours it: the one being edited is blue, the
/// one setting the fan's speed orange, the rest grey.
enum CurveRole: Equatable {
    case editing, driving, idle

    static func of(_ index: Int, editing: Int, driving: Int?) -> CurveRole {
        index == editing ? .editing : index == driving ? .driving : .idle
    }

    var colour: Color {
        switch self {
        case .editing: Palette.calm
        case .driving: Palette.heat
        case .idle: Palette.ink.opacity(0.28)
        }
    }
}

/// A curve's number in a dot: on its group's card, and at the end of its line.
struct CurveNumber: View {
    let number: Int
    let role: CurveRole
    var size: CGFloat = 16

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.62, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(role == .editing ? .white : role == .driving ? Palette.heat : Palette.ink.opacity(0.55))
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(stroke, lineWidth: 0.5))
    }

    private var fill: Color {
        switch role {
        case .editing: Palette.calm
        case .driving: Palette.heat.opacity(0.16)
        case .idle: Palette.ink.opacity(0.06)
        }
    }

    private var stroke: Color {
        switch role {
        case .editing: Palette.calm
        case .driving: Palette.heat.opacity(0.45)
        case .idle: Palette.ink.opacity(0.16)
        }
    }
}

/// Where the numbers go at the right-hand ends of the curves.
///
/// Two curves that end at the same speed would put their numbers on top of each
/// other. They are kept `spacing` apart: the edited curve's number keeps its true
/// place, the others step aside - down the margin, or up it when there is no room
/// below - and are drawn with a leader back to where their line really ends.
enum CurveNumberLayout {
    struct Placed: Equatable {
        var index: Int
        /// Where the curve's line ends.
        var lineY: CGFloat
        /// Where its number sits.
        var y: CGFloat
    }

    static func place(ends: [CGFloat], editing: Int, spacing: CGFloat = 20,
                      within range: ClosedRange<CGFloat>) -> [Placed] {
        let order = ends.indices.sorted { a, b in
            if (a == editing) != (b == editing) { return a == editing }
            return ends[a] < ends[b]
        }
        var placed: [Placed] = []
        for index in order {
            let lineY = min(max(ends[index], range.lowerBound), range.upperBound)
            let clashes = { (y: CGFloat) in placed.contains { abs($0.y - y) < spacing - 0.001 } }
            var y = lineY
            while clashes(y) { y += spacing }
            if y > range.upperBound {
                y = lineY
                while clashes(y) { y -= spacing }
            }
            placed.append(Placed(index: index, lineY: lineY, y: y))
        }
        return placed.sorted { $0.index < $1.index }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CurveNumberLayoutTests 2>&1 | tail -5`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlassFanUI/CurveNumbers.swift Tests/GlassFanUITests/CurveNumberLayoutTests.swift
git commit -m "Number the curves, and keep numbers that meet from sitting on each other

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: The curve editor draws every curve

**Files:**
- Modify: `Sources/GlassFanUI/CurveEditor.swift`
- Modify: `Sources/GlassFanUI/FansView.swift` (`curvePanel`, the `CurveEditor(` call)

**Interfaces:**
- Consumes: `CurveRule` (Task 1), `CurveRole`, `CurveNumber`, `CurveNumberLayout` (Task 7).
- Produces: `CurveEditor(curves: Binding<[CurveRule]>, editing: Binding<Int>, driving: Int?, limits: FanLimits, currentTemp: Double?, currentRPM: Double?, learnedFloor: Double? = nil, onCommit: () -> Void)`.

- [ ] **Step 1: Change the editor's inputs**

In `CurveEditor`, replace `@Binding var curve: FanCurve` with:

```swift
    @Binding var curves: [CurveRule]
    /// The curve whose points take drags and double-clicks.
    @Binding var editing: Int
    /// The curve setting the fan's speed right now, when that is known.
    var driving: Int? = nil
```

and add below the stored properties:

```swift
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
```

In `body`, the plot width becomes `max(geometry.size.width - 44 - (numbered ? 26 : 0), 10)`, and after `handles(in: plot)` add `curveNumbers(in: plot)`.

- [ ] **Step 2: Draw every curve**

Replace `curveShape(in:)` with:

```swift
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
                        .position(x: x, y: number.y)
                    }
                }
            }
        }
    }
```

- [ ] **Step 3: Wire the editor in the fans screen**

In `FansView`, add `@State private var editingCurve: [Int: Int] = [:]` and:

```swift
    /// Which of a fan's curves is being edited, kept per fan and within its curves.
    private func editingBinding(for fan: FanReading) -> Binding<Int> {
        Binding(
            get: { min(editingCurve[fan.index] ?? 0, settings(for: fan).curves.count - 1) },
            set: { editingCurve[fan.index] = $0 }
        )
    }
```

Replace `curvePanel`'s body with:

```swift
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
```

(the function's signature changes from `-> some View { Group {` to `-> some View {` with the `let`s first and `return Group {`. The binding's setter already commits, so creating a curve needs no `client.commit()`.)

Update the `Curve readout` preview at the bottom of `CurveEditor.swift` to pass `curves: .constant([CurveRule(sensorKeys: [], curve: <its curve>)]), editing: .constant(0)` in place of `curve:`, and add:

```swift
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
    CurveEditor(curves: $curves, editing: $editing, driving: 1,
                limits: FanLimits(minRPM: 1499, maxRPM: 5776),
                currentTemp: 72, currentRPM: 4072, learnedFloor: 1240, onCommit: {})
        .padding(16)
        .frame(width: 700, height: 300)
        .background(Color(red: 0.12, green: 0.14, blue: 0.19))
        .environment(\.colorScheme, .dark)
}
```

- [ ] **Step 4: Build, test, look**

Run: `swift test 2>&1 | tail -5`
Expected: all pass.
Render `Curve editor · three curves`: curve 1 blue with handles and fill, curve 2 orange, curve 3 grey dashed; numbers 1 and 2 at the top right, 1 on its line end, 2 stepped down with a leader; 3 at its own end. Render `Curve readout`: unchanged, no numbers.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlassFanUI/CurveEditor.swift Sources/GlassFanUI/FansView.swift
git commit -m "Draw all of a fan's curves, edit one, and number their ends

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: The sensor groups in the sidebar

**Files:**
- Create: `Sources/GlassFanUI/CurveGroups.swift`
- Modify: `Sources/GlassFanUI/FansView.swift` (sidebar, remove `sensorBox` and `showingSensorPicker`, `modeCaption`)
- Modify: `Sources/GlassFanUI/DemoFixture.swift`, `Sources/GlassFanUI/DaemonClient.swift` (`demo`), `Sources/GlassFanUI/Previews.swift`

**Interfaces:**
- Consumes: `GlassDropList` (Task 6), `CurveNumber`, `CurveRole` (Task 7), `SensorPicker`, `SensorChip`, `FlowLayout`, `SectionCaption` (existing), `FanSettings.maxCurves`, `FanCurve.starter` (Task 1), `FanReading.drivingCurve` (Task 2).
- Produces: `CurveGroups(curves: Binding<[CurveRule]>, editing: Binding<Int>, driving: Int?, drivingTemp: Double?, maxRPM: Double)`; `DemoFixture.snapshot(alarming:fanless:curves:)` and `DaemonClient.demo(... , curves: Int = 1)`; `PreviewShell(... , curves: Int = 1)`.

- [ ] **Step 1: Write the groups view**

Create `Sources/GlassFanUI/CurveGroups.swift`:

```swift
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
                        Label(L10n.t("кривая", "curve"), systemImage: "plus")
                            .font(.system(size: 10.5))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .help(L10n.t("Добавить кривую со своими датчиками", "Add a curve with its own sensors"))
                }
            }

            if curves.count == 1 {
                HStack(alignment: .top) {
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

    @ViewBuilder
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
```

- [ ] **Step 2: Put it in the fans screen**

In `FansView`:
- In `sidebar`, replace `sensorBox(fan)` with
  ```swift
                  CurveGroups(curves: binding(for: fan).curves,
                              editing: editingBinding(for: fan),
                              driving: fan.drivingCurve,
                              drivingTemp: fan.drivingTemp,
                              maxRPM: fan.limits.maxRPM)
  ```
- Delete `sensorBox(_:)` and `@State private var showingSensorPicker`.
- In `modeCaption`, `case .curve:` becomes
  ```swift
          case .curve:
              if let driving = item.drivingCurve, settings(for: item).curves.count > 1 {
                  return L10n.t("по кривой \(driving + 1)", "curve \(driving + 1)")
              }
              return L10n.t("по кривой", "curve")
  ```

- [ ] **Step 3: Three curves in the fixture and a preview**

`DemoFixture.snapshot` gains `curves: Int = 1`. Where it sets fan 0's curves:

```swift
            config.fans[0].curves = curves > 1
                ? Array([
                    CurveRule(sensorKeys: ["Ts0P", "Ts1P"], curve: FanCurve(points: [
                        CurvePoint(temperature: 40, rpm: 0), CurvePoint(temperature: 55, rpm: 1800),
                        CurvePoint(temperature: 75, rpm: 3400), CurvePoint(temperature: 90, rpm: limits0.maxRPM)])),
                    CurveRule(sensorKeys: ["TCMz", "Th02"], curve: FanCurve(points: [
                        CurvePoint(temperature: 60, rpm: 1500), CurvePoint(temperature: 90, rpm: limits0.maxRPM)])),
                    CurveRule(sensorKeys: ["Tg05"], curve: .starter(maxRPM: 4000)),
                  ].prefix(curves))
                : [CurveRule(sensorKeys: ["TCMz", "Th02"], curve: .starter(maxRPM: limits0.maxRPM))]
```

and fan 0's `FanReading` gets `drivingCurve: curves > 1 ? 1 : 0`. `DaemonClient.demo` gains `curves: Int = 1` and passes it to `DemoFixture.snapshot(alarming:fanless:curves:)`. `PreviewShell.init` gains `curves: Int = 1` passed to `.demo(...)`, and add:

```swift
/// Three curves on fan 1: palm rests, CPU, GPU - the CPU's setting the speed.
#Preview("Fans · three curves") { PreviewShell(.fans, curves: 3) }
```

- [ ] **Step 4: Build, test, look**

Run: `swift test 2>&1 | tail -5 && Scripts/build-app.sh >/dev/null && echo built`
Expected: all pass, `built`.
Render `Fans` (one curve: looks as before) and `Fans · three curves` (three cards, card 1 on the glass platter with a blue 1 and "editing", card 2 with "driving"; plot as in Task 8). Check that the sidebar fits the 1008×640 window with three cards; if it does not, wrap the sidebar's `VStack` in `ScrollView(.vertical, showsIndicators: false)`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GlassFanUI/CurveGroups.swift Sources/GlassFanUI/FansView.swift Sources/GlassFanUI/DemoFixture.swift Sources/GlassFanUI/DaemonClient.swift Sources/GlassFanUI/Previews.swift
git commit -m "Group a fan's sensors by curve, with the drop on the one being edited

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Try it for real

**Files:** none new.

- [ ] **Step 1: Everything green**

Run: `swift test 2>&1 | tail -3 && Scripts/build-app.sh && echo built`
Expected: every test passes; `built`.

- [ ] **Step 2: Hand the build over**

Tell the user the app bundle is at `GlassFan.app`, that it carries daemon 0.1.13, and that installing it means Settings → Update in the app (their password). Do not run sudo.

- [ ] **Step 3: Live check with the user, on this M1 Max**

With the new daemon installed and fan 1 in Curve mode:
- add curve 2 with a CPU sensor, raise its first point above what curve 1 asks for → the fan follows curve 2, its card says "driving", the fan row says "curve 2";
- `.build/debug/fanctld --probe` shows `F0Md=1` and the target the app shows;
- read `/Library/Application Support/GlassFan/config.json`: `curves` has two entries, `sensorKeys`/`curve` equal curve 1;
- remove curve 2 → back to one box, no numbers.
Afterwards put the fan back the way the user had it.

- [ ] **Step 4: Push when the user says so**

```bash
git push origin master
```
A release is a `v0.1.13` tag, and only on the user's word.
