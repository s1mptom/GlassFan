import Testing
@testable import FanKit

@Suite("SMC payload decoding")
struct SMCValueTests {
    @Test("flt is a little-endian IEEE float")
    func float() {
        // Bytes taken from this machine's TCMz key while it read 73.83 C.
        let value = SMCValue.decode(type: "flt ", bytes: [0x2b, 0xa7, 0x93, 0x42])
        #expect(value != nil)
        #expect(abs(value! - 73.826) < 0.01)
    }

    @Test("ioft is little-endian fixed point with 16 fractional bits")
    func ioft() {
        // TG0B reading 37.0 C.
        #expect(SMCValue.decode(type: "ioft", bytes: [0, 0, 0x25, 0, 0, 0, 0, 0]) == 37.0)
        // TG1B reading 36.1 C.
        let v = SMCValue.decode(type: "ioft", bytes: [0x99, 0x19, 0x24, 0, 0, 0, 0, 0])
        #expect(abs(v! - 36.1) < 0.01)
    }

    @Test("the integer types are big-endian")
    func integers() {
        // #KEY read 2251 keys on this machine.
        #expect(SMCValue.decode(type: "ui32", bytes: [0, 0, 0x08, 0xcb]) == 2251)
        #expect(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]) == 256)
        #expect(SMCValue.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCValue.decode(type: "si8 ", bytes: [0xff]) == -1)
    }

    @Test("fpe2 carries two fractional bits")
    func fpe2() {
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x17, 0x70]) == 1500.0)
    }

    @Test("unknown types decode to nil rather than to a wrong number")
    func unknown() {
        #expect(SMCValue.decode(type: "ch8*", bytes: [1, 2, 3, 4]) == nil)
    }

    @Test("truncated payloads decode to nil")
    func truncated() {
        #expect(SMCValue.decode(type: "flt ", bytes: [0x2b, 0xa7]) == nil)
        #expect(SMCValue.decode(type: "ioft", bytes: [0, 0, 0x25]) == nil)
    }

    @Test("a float round-trips through encode and decode")
    func floatRoundTrip() {
        let bytes = SMCValue.encode(2330, type: "flt ", size: 4)
        #expect(bytes != nil)
        #expect(SMCValue.decode(type: "flt ", bytes: bytes!) == 2330)
    }

    @Test("encoding a fan mode flag gives a single byte")
    func flagEncode() {
        #expect(SMCValue.encode(1, type: "ui8 ", size: 1) == [1])
        #expect(SMCValue.encode(0, type: "ui8 ", size: 1) == [0])
    }

    @Test("encoding refuses a size the type cannot fill")
    func encodeSizeMismatch() {
        #expect(SMCValue.encode(2330, type: "flt ", size: 2) == nil)
    }

    @Test("temperature keys are told apart from other T keys")
    func temperatureDetection() {
        #expect(SensorCatalog.looksLikeTemperature(key: "TCMz", type: "flt ", value: 73.8))
        #expect(SensorCatalog.looksLikeTemperature(key: "TG0B", type: "ioft", value: 37))
        // Zeroed and out-of-range readings are not temperatures.
        #expect(!SensorCatalog.looksLikeTemperature(key: "Tz11", type: "flt ", value: 0))
        #expect(!SensorCatalog.looksLikeTemperature(key: "TS0C", type: "ui8 ", value: 40))
        #expect(!SensorCatalog.looksLikeTemperature(key: "F0Ac", type: "flt ", value: 1500))
    }
}
