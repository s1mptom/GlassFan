import Testing
@testable import FanKit

/// Reading parts off a machine's own key layout, on the layout that forced the
/// question: a MacBook Pro Mac15,7 (M3 Pro), whose cores, GPU clusters and heatsinks
/// sit at keys no table here describes.
@Suite("Sensor layout")
struct SensorLayoutTests {

    /// `cores: 0` means "do not check the count", which is what a machine that will
    /// not say its core count gets. The check has its own test below.
    private func named(_ readings: [(String, Double)], cores: Int = 0) -> [String: SensorCatalog.Entry] {
        let parts = SensorCatalog.discovered(readings.map { SensorReading(key: $0.0, value: $0.1) },
                                             cores: cores)
        return Dictionary(uniqueKeysWithValues: (parts.named + parts.numbered).map { ($0.key, $0) })
    }

    @Test("a run is a core only when the runs and the machine's cores come to the same number")
    func coresAreCountedBeforeTheyAreClaimed() {
        // Two runs under Tp. On a two-core machine they are its cores...
        let two: [(String, Double)] = [("Tp04", 46), ("Tp05", 52), ("Tp06", 59),
                                       ("Tp0C", 46), ("Tp0D", 52), ("Tp0E", 59)]
        #expect(named(two, cores: 2)["Tp06"]?.en == "CPU core 1")
        // ...and on a twelve-core one they are not, whatever the prefix suggests.
        // The M3 Pro measured has seventeen such runs and twelve cores.
        #expect(named(two, cores: 12)["Tp06"]?.en == "CPU zone 1")
        #expect(named(two, cores: 12)["Tp06"]?.group == .cpu)
        #expect(named(two, cores: 12)["Tp04"]?.en == "CPU zone 1 · probe 1")
        // A machine that will not say how many cores it has gets the benefit of the
        // doubt rather than a worse name.
        #expect(named(two, cores: 0)["Tp06"]?.en == "CPU core 1")
        // The count is only ever checked against the CPU's own prefix.
        let gpu: [(String, Double)] = [("Tg04", 41), ("Tg05", 48)]
        #expect(named(gpu, cores: 12)["Tg05"]?.en == "GPU cluster 1")
    }

    @Test("a run steps past the end of the alphabet instead of falling off it")
    func advanceCarries() {
        // The M3 Pro's tenth core triplet is Tp0y, Tp0z, Tp10.
        #expect(SensorCatalog.advance("Tp0y", by: 1) == "Tp0z")
        #expect(SensorCatalog.advance("Tp0y", by: 2) == "Tp10")
        #expect(SensorCatalog.advance("Tp0z", by: 1) == "Tp10")
        // And the M1 family's own bases still step the way they always did.
        #expect(SensorCatalog.advance("Tp00", by: 2) == "Tp02")
        #expect(SensorCatalog.advance("Tg0S", by: 1) == "Tg0T")
        #expect(SensorCatalog.advance("Tp0a", by: 0) == "Tp0a")
    }

    @Test("parts are cut where the reading falls, not every three keys")
    func runsCutAtTheSeam() {
        // Seven consecutive keys holding three parts, read off the M3 Pro: two
        // probes, then a triplet, then a pair. Cutting by key alone made the first
        // part (Te0P, Te0Q, Te0R) lead with its coldest reading.
        let table = named([("Te0P", 53.7), ("Te0Q", 63.4), ("Te0R", 45.5), ("Te0S", 53.5),
                           ("Te0T", 60.8), ("Te0U", 54.0), ("Te0V", 60.8)])
        #expect(table["Te0Q"]?.en == "CPU die zone 1")
        #expect(table["Te0P"]?.en == "CPU die zone 1 · probe 1")
        #expect(table["Te0T"]?.en == "CPU die zone 2")
        #expect(table["Te0R"]?.en == "CPU die zone 2 · probe 1")
        #expect(table["Te0V"]?.en == "CPU die zone 3")
        #expect(table["Te0U"]?.en == "CPU die zone 3 · probe 1")
    }

    @Test("a part is never wider than three, even with no seam to cut at")
    func runsAreCappedAtThree() {
        let table = named([("Th00", 40.0), ("Th01", 41.0), ("Th02", 42.0),
                           ("Th03", 43.0), ("Th04", 44.0)])
        #expect(table["Th02"]?.en == "SoC heatsink 1")
        #expect(table["Th04"]?.en == "SoC heatsink 2")
        #expect(table["Th03"]?.en == "SoC heatsink 2 · probe 1")
    }

    @Test("a part that ends below its own probe is still one part")
    func aPartNeedNotClimbAllTheWay() {
        // Tp0u, Tp0v, Tp0w as this M3 Pro reports them: the part's own key reads
        // below its second probe. A seam is six degrees and up; this is two, and
        // cutting here left Tp0w stranded and unnamed.
        let table = named([("Tp0u", 47.7), ("Tp0v", 57.0), ("Tp0w", 55.1),
                           ("Tp0y", 47.7), ("Tp0z", 57.0), ("Tp10", 55.2)])
        #expect(table["Tp0w"]?.en == "CPU core 1")
        #expect(table["Tp0v"]?.en == "CPU core 1 · probe 2")
        // ...and the carry into Tp10 holds the second part together.
        #expect(table["Tp10"]?.en == "CPU core 2")
        #expect(table["Tp0y"]?.en == "CPU core 2 · probe 1")
    }

    @Test("a key with no neighbour is nobody's probe")
    func lonelyKeysAreLeftAlone() {
        // Ts0P is the palm rest, sitting between two parts of the SoC. It must not be
        // swept into either.
        let table = named([("Ts0M", 45.2), ("Ts0P", 31.6), ("Ts0Y", 45.5), ("Ts0Z", 45.5)])
        #expect(table["Ts0P"] == nil)
        #expect(table["Ts0Z"] != nil)
    }

    @Test("a prefix nobody measured is numbered, not named, and never promoted")
    func unknownPrefixesClaimNothing() {
        let parts = SensorCatalog.discovered([SensorReading(key: "TED0", value: 50.6),
                                              SensorReading(key: "TED1", value: 49.7)])
        #expect(parts.named.isEmpty)
        #expect(parts.numbered.contains { $0.key == "TED1" && $0.en == "TE group 1" })
        #expect(parts.numbered.allSatisfy { !$0.essential })
        // Where the prefix is known, the part leads its group.
        let cores = SensorCatalog.discovered([SensorReading(key: "Tp04", value: 46.2),
                                              SensorReading(key: "Tp05", value: 52.8),
                                              SensorReading(key: "Tp06", value: 59.5)])
        #expect(cores.named.first { $0.key == "Tp06" }?.essential == true)
        #expect(cores.named.first { $0.key == "Tp04" }?.essential == false)
    }

    @Test("die zones are named but not promoted, as the M1 table has them")
    func dieZonesAreNotEssential() {
        let parts = SensorCatalog.discovered([SensorReading(key: "Te04", value: 47.2),
                                              SensorReading(key: "Te05", value: 53.0),
                                              SensorReading(key: "Te06", value: 63.4)])
        #expect(parts.named.first { $0.key == "Te06" }?.en == "CPU die zone 1")
        #expect(parts.named.allSatisfy { !$0.essential })
    }
}

/// The M3 Pro's own table, and the SMC's fan control that sits among its keys.
@Suite("M3 Pro")
struct M3ProTests {
    private func info(_ key: String) -> SensorInfo { SensorCatalog.info(for: key, family: .m3Pro) }

    @Test("the chip is told from the brand string, and only the measured one claims a table")
    func familyDetection() {
        #expect(ChipFamily.from(brand: "Apple M3 Pro") == .m3Pro)
        #expect(ChipFamily.from(brand: "Apple M1 Max") == .m1)
        #expect(ChipFamily.from(brand: "Apple M1") == .m1)
        // An M3 and an M3 Max have different core counts and were never measured;
        // they take the layout-derived names rather than an M3 Pro's.
        #expect(ChipFamily.from(brand: "Apple M3") == .other)
        #expect(ChipFamily.from(brand: "Apple M3 Max") == .other)
        #expect(ChipFamily.from(brand: "Apple M4 Pro") == .other)
    }

    @Test("Ts0 reads with the SoC here, not with the SSD as it does on an M1")
    func ts0IsNotTheSSD() {
        #expect(info("Ts02").group == .cooling)
        #expect(info("Ts02").name == L10n.t("Зона SoC 1", "SoC zone 1"))
        #expect(SensorCatalog.info(for: "Ts02", family: .m1).group == .storage)
        // The palm rest keys are the same part on both, and belong to neither table.
        #expect(info("Ts0P").group == .comfort)
        #expect(SensorCatalog.info(for: "Ts0P", family: .m1).group == .comfort)
        #expect(SensorCatalog.info(for: "Ts0P", family: .other).group == .comfort)
    }

    @Test("the CPU aggregates lead the list, and TCDX is not one of them")
    func aggregates() {
        #expect(info("TCMz").essential && info("TCMz").group == .cpu)
        #expect(info("TCMb").essential)
        // TCDX == max(Tf14, Tf24) across 138 samples: the hotter control zone, which
        // under a GPU load is the GPU's. Filed with the cooling it drives, not the CPU.
        #expect(info("TCDX").group == .cooling)
        #expect(SensorCatalog.info(for: "TCDX", family: .m1).group == .cpu)
    }

    @Test("TCHP is the charge regulator on both chips, not the CPU")
    func chargeRegulator() {
        for family in [ChipFamily.m1, .m3Pro] {
            let tchp = SensorCatalog.info(for: "TCHP", family: family)
            #expect(tchp.group == .power)
            #expect(tchp.name == L10n.t("Регулятор зарядки", "Charge regulator"))
        }
    }

    @Test("a control zone is an engine, and is named only where that was measured")
    func zoneSubjects() {
        #expect(SensorCatalog.smcZoneName(0, family: .m3Pro) == "CPU")
        #expect(SensorCatalog.smcZoneName(1, family: .m3Pro) == "GPU")
        #expect(SensorCatalog.smcZoneName(2, family: .m3Pro) == L10n.t("Зона 3", "Zone 3"))
        #expect(SensorCatalog.smcZoneName(0, family: .m1) == L10n.t("Зона 1", "Zone 1"))
        #expect(SensorCatalog.smcZoneName(0, family: .other) == L10n.t("Зона 1", "Zone 1"))
        // The blocks behind those zones: Tf1 followed the CPU load, Tf2 the GPU one.
        #expect(info("Tf14").name == L10n.t("Зона SMC · CPU", "SMC zone · CPU"))
        #expect(info("Tf24").name == L10n.t("Зона SMC · GPU", "SMC zone · GPU"))
        #expect(info("Tf14").essential && info("Tf24").essential)
    }

    @Test("board sensors are filed by the engine they answer to")
    func proximitySensors() {
        #expect(info("TED0").group == .cpu)
        #expect(info("TSCP").group == .cpu)
        #expect(info("TFD0").group == .gpu)
        // TSG1/TSG2 sit under a "TS" prefix that the fallback files under power; the
        // GPU load says otherwise.
        #expect(info("TSG1").group == .gpu)
        #expect(SensorCatalog.info(for: "TSG1", family: .other).group == .power)
    }

    @Test("the SMC's control block is not a row of sensors")
    func fanControlBlock() {
        // Constants over 18 samples spanning idle to 90 C: gains and flags.
        for key in ["Tf11", "Tf15", "Tf1C", "Tf21", "Tf25", "Tf2C"] {
            #expect(!SensorCatalog.looksLikeTemperature(key: key, type: "flt ", value: 3.2),
                    "\(key) is a control value, not a reading")
        }
        // The setpoints read as plausible temperatures - that is the whole problem.
        #expect(!SensorCatalog.looksLikeTemperature(key: "Tf16", type: "flt ", value: 79.6))
        #expect(!SensorCatalog.looksLikeTemperature(key: "Tf26", type: "flt ", value: 82.4))
        #expect(SensorCatalog.smcZoneTarget(key: "Tf16") == 0)
        #expect(SensorCatalog.smcZoneTarget(key: "Tf26") == 1)
        // The zone temperatures in the same block are readings and stay.
        #expect(SensorCatalog.looksLikeTemperature(key: "Tf14", type: "flt ", value: 52.0))
        #expect(SensorCatalog.smcZoneTarget(key: "Tf14") == nil)
        #expect(SensorCatalog.smcZoneTarget(key: "Tf06") == nil)   // no zone zero
        #expect(SensorCatalog.smcZoneTarget(key: "TB0T") == nil)
        #expect(info("Tf14").essential && info("Tf14").group == .cooling)
    }

    @Test("setpoints are reported by zone")
    func zoneTargets() {
        let targets = SensorCatalog.smcZoneTargets([
            SensorReading(key: "TCMz", value: 74.1),
            SensorReading(key: "Tf16", value: 79.6),
            SensorReading(key: "Tf26", value: 82.4),
        ])
        #expect(targets == [0: 79.6, 1: 82.4])
    }
}
