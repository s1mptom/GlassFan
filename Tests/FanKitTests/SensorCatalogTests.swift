import Testing
@testable import FanKit

/// The M1 family's table, checked against the layout both sources describe and
/// against what a live M1 Max reports.
@Suite("Sensor catalogue")
struct SensorCatalogTests {
    private func info(_ key: String) -> SensorInfo { SensorCatalog.info(for: key, family: .m1) }

    @Test("each core's row is the third key of its triplet; the other two are its probes")
    func coreTriplets() {
        #expect(info("Tp02").name == L10n.t("Производительное ядро 1", "Performance core 1"))
        #expect(info("Tp02").essential)
        #expect(info("Tp00").name.hasPrefix(info("Tp02").name))
        #expect(!info("Tp00").essential && !info("Tp01").essential)
        // The triplets step four characters through 0-9A-Za-z.
        #expect(info("Tp0c").name == L10n.t("Производительное ядро 8", "Performance core 8"))
        #expect(info("Tp0A").name == L10n.t("Энергоэффективное ядро 1", "Efficiency core 1"))
        #expect(info("Tp0U").name == L10n.t("Энергоэффективное ядро 2", "Efficiency core 2"))
    }

    @Test("GPU clusters are pairs, memory and heatsinks triplets")
    func otherLayouts() {
        #expect(info("Tg05").essential && !info("Tg04").essential)
        #expect(info("Tg0T").name == L10n.t("GPU, кластер 4", "GPU cluster 4"))
        #expect(info("Tm0E").essential && info("Tm0E").group == .memory)
        #expect(info("Th0I").essential && info("Th0I").group == .cooling)
    }

    @Test("the aliases that read with the battery are not promoted to 'the GPU'")
    func gpuAliases() {
        #expect(info("TG0B").group == .gpu)
        #expect(!info("TG0B").essential)
    }

    @Test("every name in the table is distinct")
    func namesAreDistinct() {
        let keys = ["TCMz", "TCMb", "TCDX", "TCHP", "Te00", "TC10", "TC53",
                    "Tp00", "Tp01", "Tp02", "Tg04", "Tg05", "Tm00", "Tm02", "Th00", "Th02",
                    "Ts00", "Ts02", "Ts0P", "Ts1P", "TS0P", "TH0x", "TB0T", "TB1T",
                    "TaLP", "TaRF", "TaLW", "TaRW", "TaLT", "TPDX", "TPD0", "TPDa", "TPDj",
                    "TD00", "TD24", "Td00", "Td0M", "TRD0", "TRDj", "TW0P", "TVS0"]
        let names = keys.map { info($0).name }
        #expect(Set(names).count == names.count)
    }

    @Test("outside the M1 family, core keys keep generic names")
    func otherFamilies() {
        let other = SensorCatalog.info(for: "Tp02", family: .other)
        #expect(!other.essential)
        #expect(other.group == .cpu)
        #expect(other.name != info("Tp02").name)
    }

    @Test("keys that pass for temperatures by type and range but are not")
    func notTemperatures() {
        #expect(!SensorCatalog.looksLikeTemperature(key: "TVMD", type: "flt ", value: 1))
        #expect(!SensorCatalog.looksLikeTemperature(key: "Ta05", type: "flt ", value: 9))
        #expect(SensorCatalog.looksLikeTemperature(key: "Tp02", type: "flt ", value: 60))
    }

    @Test("an untouched old default is recognised; any edit makes it the user's own")
    func retiredDefaults() {
        let old = ["TCMz", "Tp0D", "Tp0E", "TG0B", "Ts0P", "Ts1P", "TaLW", "TaRW", "TB0T", "TH0x"]
        #expect(SensorCatalog.isRetiredDefault(old))
        #expect(SensorCatalog.isRetiredDefault(old.reversed()))
        #expect(!SensorCatalog.isRetiredDefault(Array(old.dropLast())))
        #expect(!SensorCatalog.isRetiredDefault(old + ["Tg05"]))
        #expect(!SensorCatalog.isRetiredDefault(SensorCatalog.defaultTracked))
    }

    @Test("headlines prefer named parts over probes that run hotter")
    func headlines() {
        // Only meaningful where the M1 table applies; the runner is an M1 Max.
        guard ChipFamily.current == .m1 else { return }
        let readings = [SensorReading(key: "TG0B", value: 80), SensorReading(key: "Tg05", value: 55),
                        SensorReading(key: "Tzz9", value: 40)]
        let result = SensorCatalog.headlines(readings, groups: [.gpu, .other, .battery])
        #expect(result.map(\.0) == [.gpu, .other])
        #expect(result[0].1 == 55)
        #expect(result[1].1 == 40)
    }
}
