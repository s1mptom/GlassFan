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
}
