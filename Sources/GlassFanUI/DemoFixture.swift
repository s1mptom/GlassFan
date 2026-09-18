import Foundation
import FanKit

/// Fixed readings matching the design mockup, so the built app can be compared against
/// it one for one. Screenshot fixture only - switched on with GLASSFAN_DEMO=1 and never
/// reachable otherwise.
enum DemoFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["GLASSFAN_DEMO"] == "1"
    }

    static let limits0 = FanLimits(minRPM: 1499, maxRPM: 5348)
    static let limits1 = FanLimits(minRPM: 1499, maxRPM: 5776)

    /// Every temperature an M1 Max reports, read off one and warmed so the CPU
    /// tops out where the mockup does. The whole set rather than a handful, so the
    /// Sensors screen shows its filter doing real work: 38 essential of 223.
    static let temperatures: [(String, Double)] = """
        TCMz=78.5 TCMb=67.7 Tp02=74.7 Tp00=58.8 Tp01=67.6 Tp06=74.3 Tp04=57.5 Tp05=66.3 Tp0E=76.3
        Tp0C=58.8 Tp0D=67.7 Tp0I=75.8 Tp0G=56.7 Tp0H=65.6 Tp0M=75.4 Tp0K=56.9 Tp0L=65.6 Tp0Q=76.2
        Tp0O=56.4 Tp0P=65.1 Tp0Y=77.9 Tp0W=56.4 Tp0X=65.1 Tp0c=78.5 Tp0a=56.1 Tp0b=64.9 Tp0A=69.7
        Tp08=55.3 Tp09=64.1 Tp0U=70.2 Tp0S=53.7 Tp0T=62.6 TCDX=57.3 Te00=52.9 Te01=65.9 Te02=73.9
        TCHP=40.0 TC10=54.6 TC11=56.8 TC12=56.7 TC13=57.1 TC20=48.7 TC21=50.1 TC22=49.5 TC23=50.1
        TC30=49.2 TC31=50.2 TC32=49.8 TC33=49.4 TC40=48.5 TC41=51.3 TC42=49.5 TC43=50.1 TC50=47.7
        TC51=48.5 TC52=47.8 TC53=47.9 Tg05=58.6 Tg04=49.4 Tg0D=58.8 Tg0C=49.6 Tg0L=59.2 Tg0K=50.0
        Tg0T=57.9 Tg0S=48.7 TG0B=33.3 TG0C=33.0 TG0V=33.3 TG1B=33.3 TG2B=33.2 Tm02=47.9 Tm00=46.7
        Tm01=46.7 Tm06=51.6 Tm04=49.8 Tm05=49.8 Tm0A=48.8 Tm08=47.8 Tm09=47.8 Tm0E=45.5 Tm0C=44.1
        Tm0D=44.1 Th02=65.4 Th00=53.7 Th01=61.1 Th06=58.7 Th04=53.6 Th05=53.6 Th0A=49.5 Th08=48.4
        Th09=48.4 Th0E=56.3 Th0C=46.9 Th0D=54.2 Th0I=47.2 Th0G=46.8 Th0H=46.8 TG0H=33.0 TaLP=44.7
        TaRF=46.9 Ts02=57.7 Ts00=54.9 Ts01=54.9 Ts06=58.7 Ts04=53.5 Ts05=53.5 TH0x=34.2 TH0a=34.1
        TH0b=34.2 TS0P=45.1 TB0T=33.3 TB1T=33.3 TB2T=33.2 Ts0P=33.0 Ts1P=31.0 TaLW=34.7 TaRW=35.1
        TaLT=35.4 TaRT=35.3 TPDX=44.8 TPSP=49.3 TSVR=44.0 TSWR=43.1 TSXR=44.9 TMVR=41.2 TPMP=42.8
        TPVD=52.6 TPD0=44.3 TPD1=44.3 TPD2=44.2 TPD3=44.3 TPD4=44.8 TPD5=44.1 TPD6=44.2 TPD7=44.3
        TPD8=44.2 TPD9=44.5 TPDa=44.3 TPDb=44.3 TPDc=44.1 TPDd=44.2 TPDe=44.6 TPDf=43.9 TPDg=44.1
        TPDh=43.9 TPDi=44.4 TPDj=44.5 Td02=49.7 Td00=48.5 Td01=48.5 Td06=49.8 Td04=48.5 Td05=48.5
        Td0A=50.5 Td08=49.0 Td09=49.0 Td0E=47.1 Td0C=46.0 Td0D=46.0 Td0I=50.0 Td0G=48.9 Td0H=48.9
        Td0M=47.5 Td0K=46.3 Td0L=46.3 TDEL=35.8 TDER=36.5 TDEC=37.2 TDCR=38.2 TDeL=35.2 TDeR=35.6
        TDBP=35.9 TDTP=38.9 TDVx=37.0 TD00=31.3 TD01=31.7 TD02=30.9 TD03=31.0 TD04=30.5 TD10=31.4
        TD11=33.1 TD12=32.9 TD13=33.6 TD14=31.7 TD20=33.3 TD21=36.5 TD22=34.9 TD23=37.0 TD24=33.4
        TW0P=45.5 TRDX=51.8 TR0Z=51.9 TR1d=44.4 TR2d=48.0 TRD0=51.8 TRD1=49.2 TRD2=50.1 TRD3=50.0
        TRD4=49.7 TRD5=48.6 TRD6=48.9 TRD7=49.9 TRD8=49.7 TRD9=49.5 TRDa=49.1 TRDb=48.9 TRDc=48.8
        TRDd=48.9 TRDe=49.5 TRDf=48.7 TRDg=48.7 TRDh=48.7 TRDi=50.2 TRDj=49.5 TVD0=66.7 TVA0=28.1
        TVV0=58.4 TVSx=37.3 TVS0=37.1 TVS1=37.3 TVS2=36.9 TaTP=47.9 TAOL=31.5
        """
        .split(whereSeparator: \.isWhitespace)
        .map { pair in
            let parts = pair.split(separator: "=")
            return (String(parts[0]), Double(parts[1])!)
        }

    /// `alarming` is the state nobody sees during normal use and which therefore
    /// rots: one fan run away on the emergency rule, the other refusing writes.
    /// `curves`: how many curves fan 1 follows - palm rests, CPU, GPU - with the
    /// CPU's setting the speed when there is more than one.
    static func snapshot(alarming: Bool = false, fanless: Bool = false, curves: Int = 1) -> Snapshot {
        var config = AppConfig.default(fanCount: fanless ? 0 : 2)
        if !fanless {
            config.fans[0].mode = .curve
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
        }
        config.trackedSensors = ["TCMz", "Tg05", "Th02", "Ts0P"]

        return Snapshot(
            time: Date().timeIntervalSince1970,
            sensors: temperatures.map { SensorReading(key: $0.0, value: $0.1) },
            fans: fanless ? [] : [
                FanReading(index: 0,
                           actualRPM: alarming ? 5348 : 2600,
                           targetRPM: alarming ? 5348 : 2600,
                           limits: limits0,
                           mode: .curve, forced: true, drivingTemp: alarming ? 97 : 78.5,
                           emergency: alarming, drivingCurve: curves > 1 ? 1 : 0),
                FanReading(index: 1, actualRPM: 1654, targetRPM: 1654, limits: limits1,
                           mode: alarming ? .fixed : .auto, forced: false, drivingTemp: nil,
                           emergency: false,
                           writeError: alarming ? "SMC write refused (kIOReturnNotPrivileged)" : nil),
            ],
            config: config,
            daemonVersion: "demo"
        )
    }

    /// Fifteen minutes of plausible wander, so the chart has the same shape every run.
    /// `sleptAt`: seconds into the fifteen minutes where the Mac went to sleep for
    /// three minutes, so a preview can show the line breaking across it.
    static func history(sleptAt: Int? = nil) -> [HistorySample] {
        let now = Date().timeIntervalSince1970
        let keys = ["TCMz", "Tg05", "Th02", "Ts0P"]
        let bases: [Double] = [76, 58, 55, 33]
        return (0..<900).filter { step in
            guard let sleptAt else { return true }
            return !(sleptAt..<(sleptAt + 180)).contains(step)
        }.map { step in
            let t = Double(step)
            var temps: [String: Double] = [:]
            for (index, key) in keys.enumerated() {
                let slow = sin(t / 130 + Double(index)) * (index < 2 ? 3.5 : 0.6)
                let fast = sin(t / 11 + Double(index) * 2) * (index < 2 ? 1.8 : 0.2)
                temps[key] = bases[index] + slow + fast
            }
            return HistorySample(t: now - 900 + t, temps: temps,
                                 fanRPM: [2600 + sin(t / 90) * 120, 1654 + sin(t / 70) * 60])
        }
    }
}
