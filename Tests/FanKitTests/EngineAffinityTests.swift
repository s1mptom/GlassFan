import Testing
import Foundation
@testable import FanKit

/// Attributing a sensor to the engine whose power explains it.
///
/// The machines behind the numbers here are synthetic, but the shapes are the ones
/// that broke earlier attempts on a real M3 Pro: engines that rise together, an
/// engine that never moves, and a sensor nothing on the list explains.
@Suite("Engine affinity")
struct EngineAffinityTests {

    /// A die warms towards the power put into it and cools towards the room, which is
    /// what makes a sensor lag its engine and why the learner smooths before it fits.
    private func heat(_ power: [Double], gain: Double, tau: Double = 15, ambient: Double = 30) -> [Double] {
        var temperature = ambient
        return power.map { watts in
            let target = ambient + gain * watts
            temperature += (1 - exp(-1 / tau)) * (target - temperature)
            return temperature
        }
    }

    /// Alternating quiet and busy stretches, the way a machine actually runs.
    private func square(_ n: Int, period: Int, high: Double, low: Double = 0) -> [Double] {
        (0..<n).map { ($0 / period) % 2 == 0 ? low : high }
    }

    private func learn(_ engines: [Engine: [Double]], _ sensors: [String: [Double]]) -> EngineAffinity {
        var affinity = EngineAffinity()
        let count = engines.values.first?.count ?? 0
        for i in 0..<count {
            affinity.observe(power: engines.mapValues { $0[i] },
                             temperatures: sensors.mapValues { $0[i] })
        }
        return affinity
    }

    @Test("a sensor is attributed to the engine that heats it")
    func attribution() {
        let cpu = square(900, period: 90, high: 20000)
        let gpu = square(900, period: 140, high: 16000)
        let affinity = learn([.cpu: cpu, .gpu: gpu],
                             ["Tp02": heat(cpu, gain: 0.0015),
                              "Tg05": heat(gpu, gain: 0.0015)])
        let verdicts = affinity.verdicts(minimumSamples: 300)
        #expect(verdicts["Tp02"]?.engine == .cpu)
        #expect(verdicts["Tg05"]?.engine == .gpu)
        #expect((verdicts["Tp02"]?.share ?? 0) > 0.8)
    }

    @Test("an engine that never moves cannot be the answer")
    func flatEngineNeverWins() {
        // The M3 Pro's image signal processor sat at 3 mJ/s all run. Correlated
        // against each engine on its own it won every GPU sensor on the machine,
        // because a near-constant column correlates with whatever you like.
        let gpu = square(900, period: 90, high: 16000)
        let isp = [Double](repeating: 3, count: 900)
        let affinity = learn([.gpu: gpu, .neural: isp], ["Tg05": heat(gpu, gain: 0.0015)])
        #expect(affinity.verdicts(minimumSamples: 300)["Tg05"]?.engine == .gpu)
    }

    @Test("engines that run together are told apart by what only one of them explains")
    func collinearEngines() {
        // The CPU is busy whenever the GPU is, and busy on its own besides - the
        // ordinary case, and the one where picking the strongest correlation put
        // every GPU sensor on the CPU.
        let gpu = square(1200, period: 150, high: 16000)
        let cpu = zip(gpu, square(1200, period: 90, high: 8000)).map { $0 * 0.5 + $1 + 2000 }
        let affinity = learn([.cpu: cpu, .gpu: gpu],
                             ["Tg05": heat(gpu, gain: 0.0015), "Tp02": heat(cpu, gain: 0.0015)])
        let verdicts = affinity.verdicts(minimumSamples: 300)
        #expect(verdicts["Tg05"]?.engine == .gpu)
        #expect(verdicts["Tp02"]?.engine == .cpu)
    }

    @Test("a sensor that never moved, and one nothing explains, get no verdict")
    func silenceIsNotAVerdict() {
        let cpu = square(900, period: 90, high: 20000)
        let steady = [Double](repeating: 31.5, count: 900)
        // A chassis sensor answering to the room rather than to any engine.
        let wandering = (0..<900).map { 30 + 6 * sin(Double($0) / 211) }
        let affinity = learn([.cpu: cpu], ["TB0T": steady, "TaLW": wandering])
        let verdicts = affinity.verdicts(minimumSamples: 300)
        #expect(verdicts["TB0T"] == nil)
        #expect(verdicts["TaLW"] == nil)
    }

    @Test("nothing is claimed before the machine has been watched long enough")
    func patience() {
        let cpu = square(900, period: 90, high: 20000)
        let affinity = learn([.cpu: cpu], ["Tp02": heat(cpu, gain: 0.0015)])
        #expect(affinity.verdicts(minimumSamples: 5000).isEmpty)
        #expect(!affinity.verdicts(minimumSamples: 300).isEmpty)
        #expect(affinity.sampleCount == 900)
    }

    @Test("a sensor that missed ticks is not judged against a window it was not in")
    func partialSensorsAreSkipped() {
        let cpu = square(900, period: 90, high: 20000)
        let warm = heat(cpu, gain: 0.0015)
        var affinity = EngineAffinity()
        for i in 0..<900 {
            // One key reads every tick; the other drops out for a stretch, the way a
            // key that occasionally refuses to be read would.
            var temperatures = ["Tp02": warm[i]]
            if !(300..<400).contains(i) { temperatures["Tp06"] = warm[i] }
            affinity.observe(power: [.cpu: cpu[i]], temperatures: temperatures)
        }
        let verdicts = affinity.verdicts(minimumSamples: 300)
        #expect(verdicts["Tp02"]?.engine == .cpu)
        #expect(verdicts["Tp06"] == nil)
    }

    @Test("weights never go negative, however the engines are tangled")
    func weightsStayPositive() {
        let gram = [[1.0, 0.95], [0.95, 1.0]]
        let weights = EngineAffinity.solve(gram: gram, target: [0.2, 0.9])
        #expect(weights.allSatisfy { $0 >= 0 })
        #expect(weights[1] > weights[0])
    }

    @Test("IOReport's channels are folded into engines, and the double-counts dropped")
    func channelMapping() {
        #expect(Engine.forPowerChannel("PCPU3") == .cpu)
        #expect(Engine.forPowerChannel("ECPU0") == .cpu)
        #expect(Engine.forPowerChannel("PCPM") == .cpu)
        #expect(Engine.forPowerChannel("GPU") == .gpu)
        #expect(Engine.forPowerChannel("DRAM") == .memory)
        #expect(Engine.forPowerChannel("AMCC") == .memory)
        #expect(Engine.forPowerChannel("DISP") == .display)
        #expect(Engine.forPowerChannel("ANE") == .neural)
        // The same cores, counted a second time.
        #expect(Engine.forPowerChannel("PCPU3_SRAM") == nil)
        #expect(Engine.forPowerChannel("ECPUDTL03") == nil)
        // Totals, which would count everything they sum twice.
        #expect(Engine.forPowerChannel("CPU Energy") == nil)
        #expect(Engine.forPowerChannel("GPU Energy") == nil)
        #expect(Engine.forPowerChannel("PCIe Port 0 Energy") == nil)
    }

    @Test("what the machine says beats what the key's prefix suggests")
    func layoutTakesTheVerdict() {
        // TSG1/TSG2 on the M3 Pro: a "TS" prefix the fallback files under power, and
        // a pair that rose 10-11 C under a GPU load and 1.3 under a CPU one.
        let run = [SensorReading(key: "TSG1", value: 39.2), SensorReading(key: "TSG2", value: 38.9)]
        let blind = SensorCatalog.discovered(run)
        #expect(blind.numbered.first { $0.key == "TSG2" }?.group == .power)
        #expect(blind.numbered.first { $0.key == "TSG2" }?.en == "TS group 1")

        let told = SensorCatalog.discovered(run, engines: ["TSG1": .gpu, "TSG2": .gpu])
        #expect(told.numbered.first { $0.key == "TSG2" }?.group == .gpu)
        #expect(told.numbered.first { $0.key == "TSG2" }?.en == "GPU sensor 1")
        #expect(told.numbered.first { $0.key == "TSG1" }?.en == "GPU sensor 1 · probe 1")

        // A run whose keys disagree was cut in the wrong place; neither answer is used.
        let split = SensorCatalog.discovered(run, engines: ["TSG1": .gpu, "TSG2": .cpu])
        #expect(split.numbered.first { $0.key == "TSG2" }?.en == "TS group 1")
    }

    @Test("a key with no neighbour still takes the engine's name")
    func lonelyKeysAreAttributedToo() {
        let layout = [SensorReading(key: "TSCP", value: 42.2)]
        let told = SensorCatalog.discovered(layout, engines: ["TSCP": .cpu])
        #expect(told.numbered.first { $0.key == "TSCP" }?.group == .cpu)
        #expect(told.numbered.first { $0.key == "TSCP" }?.en == "CPU sensor 1")
        #expect(SensorCatalog.discovered(layout).numbered.isEmpty)
    }
}
