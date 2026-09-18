import Testing
@testable import FanKit

@Suite("Fan control decisions")
struct ControllerTests {
    /// A fan with a simple ramp: 1500 rpm at 40 C rising to 5000 rpm at 80 C.
    func makeSettings(mode: FanMode = .curve) -> FanSettings {
        FanSettings(
            id: 0,
            mode: mode,
            fixedRPM: 3000,
            sensorKeys: ["TCMz", "Ts0P"],
            curve: FanCurve(points: [
                CurvePoint(temperature: 40, rpm: 1500),
                CurvePoint(temperature: 80, rpm: 5000),
            ]),
            hysteresis: 2,
            smoothing: 0
        )
    }

    let limits = FanLimits(minRPM: 1499, maxRPM: 5348)

    @Test("auto mode releases the fan to the system")
    func autoMode() {
        var c = FanController(settings: makeSettings(mode: .auto), limits: limits)
        #expect(c.update(temperatures: ["TCMz": 90], emergencyTemp: 95) == nil)
    }

    @Test("fixed mode ignores temperature")
    func fixedMode() {
        var c = FanController(settings: makeSettings(mode: .fixed), limits: limits)
        #expect(c.update(temperatures: ["TCMz": 45], emergencyTemp: 95) == 3000)
        #expect(c.update(temperatures: ["TCMz": 75], emergencyTemp: 95) == 3000)
    }

    @Test("takes the hottest of its assigned sensors")
    func aggregatesByMax() {
        var c = FanController(settings: makeSettings(), limits: limits)
        // Ts0P is hotter, so it drives the curve: 60 C -> 3250 rpm.
        #expect(c.update(temperatures: ["TCMz": 45, "Ts0P": 60], emergencyTemp: 95) == 3250)
    }

    @Test("ignores sensors it was not assigned")
    func ignoresOtherSensors() {
        var c = FanController(settings: makeSettings(), limits: limits)
        #expect(c.update(temperatures: ["TCMz": 40, "TG0B": 99], emergencyTemp: 95) == 1500)
    }

    @Test("falls back to auto when no assigned sensor is readable")
    func noSensors() {
        var c = FanController(settings: makeSettings(), limits: limits)
        #expect(c.update(temperatures: ["TG0B": 70], emergencyTemp: 95) == nil)
    }

    /// The declared minimum is not a floor. Tested on the hardware: asked for
    /// targets under it the fan ran slow, asked for zero it stopped, and the
    /// SMC kept each target as written. Only the maximum is enforced.
    @Test("caps the result at the fan's maximum and lets it fall to zero")
    func clamps() {
        var s = makeSettings()
        s.curves[0].curve = FanCurve(points: [CurvePoint(temperature: 40, rpm: 100),
                                    CurvePoint(temperature: 80, rpm: 9000)])
        var c = FanController(settings: s, limits: limits)
        #expect(c.update(temperatures: ["TCMz": 20], emergencyTemp: 95) == 100)
        #expect(c.update(temperatures: ["TCMz": 99], emergencyTemp: 95) == 5348)
    }

    @Test("a curve point at zero stops the fan rather than idling it at the minimum")
    func restsAtZero() {
        var s = makeSettings()
        s.smoothing = 0
        s.curves[0].curve = FanCurve(points: [CurvePoint(temperature: 40, rpm: 0),
                                    CurvePoint(temperature: 60, rpm: 3000)])
        var c = FanController(settings: s, limits: limits)
        #expect(c.update(temperatures: ["TCMz": 30], emergencyTemp: 95) == 0)
        #expect(c.update(temperatures: ["TCMz": 50], emergencyTemp: 95) == 1500)
    }

    @Test("a fixed target below the declared minimum is passed through, not raised")
    func fixedBelowMinimum() {
        var s = makeSettings()
        s.mode = .fixed
        s.fixedRPM = 800
        var c = FanController(settings: s, limits: limits)
        #expect(c.update(temperatures: ["TCMz": 50], emergencyTemp: 95) == 800)
    }

    @Test("emergency temperature overrides the curve with full speed")
    func emergency() {
        var c = FanController(settings: makeSettings(), limits: limits)
        #expect(c.update(temperatures: ["TCMz": 96], emergencyTemp: 95) == 5348)
    }

    @Test("rises immediately but only falls once past the hysteresis band")
    func hysteresis() {
        var c = FanController(settings: makeSettings(), limits: limits)
        #expect(c.update(temperatures: ["TCMz": 60], emergencyTemp: 95) == 3250)
        // A rise always applies at once.
        #expect(c.update(temperatures: ["TCMz": 62], emergencyTemp: 95) == 3425)
        // A small drop inside the 2 C band keeps the previous target.
        #expect(c.update(temperatures: ["TCMz": 61], emergencyTemp: 95) == 3425)
        // A drop past the band applies.
        #expect(c.update(temperatures: ["TCMz": 59], emergencyTemp: 95) == 3162.5)
    }

    @Test("smoothing eases the target towards the demand")
    func smoothing() {
        var s = makeSettings()
        s.smoothing = 0.5
        s.hysteresis = 0
        var c = FanController(settings: s, limits: limits)
        #expect(c.update(temperatures: ["TCMz": 40], emergencyTemp: 95) == 1500)
        // Demand jumps to 5000; with 0.5 smoothing we move half way there.
        #expect(c.update(temperatures: ["TCMz": 80], emergencyTemp: 95) == 3250)
        #expect(c.update(temperatures: ["TCMz": 80], emergencyTemp: 95) == 4125)
    }

    @Test("emergency bypasses smoothing entirely")
    func emergencyBypassesSmoothing() {
        var s = makeSettings()
        s.smoothing = 0.9
        var c = FanController(settings: s, limits: limits)
        _ = c.update(temperatures: ["TCMz": 40], emergencyTemp: 95)
        #expect(c.update(temperatures: ["TCMz": 97], emergencyTemp: 95) == 5348)
    }

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

    @Test("removing a curve does not leave its hold on the curve that moves into its place")
    func holdsFollowTheirGroups() {
        let flat = FanCurve(points: [CurvePoint(temperature: 40, rpm: 1000), CurvePoint(temperature: 80, rpm: 5000)])
        var c = FanController(settings: FanSettings(id: 0, mode: .curve, fixedRPM: 0, curves: [
            CurveRule(sensorKeys: ["a"], curve: flat), CurveRule(sensorKeys: ["b"], curve: flat),
        ], hysteresis: 20, smoothing: 0), limits: limits)
        _ = c.update(temperatures: ["a": 65, "b": 50], emergencyTemp: 95)
        c.settings.curves.remove(at: 0)
        // b alone at 49: its own reading. With a's 65 held over, inside the 20-degree
        // band, it would have asked for 3500.
        #expect(c.update(temperatures: ["a": 65, "b": 49], emergencyTemp: 95) == 1900)
    }
}
