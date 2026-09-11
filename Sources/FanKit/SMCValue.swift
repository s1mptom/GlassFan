import Foundation

/// Decoding and encoding of SMC payloads. Pure byte work, kept here so it can be
/// tested without hardware. Type codes come from the SMC itself.
///
/// Byte order is not uniform: floats are little-endian, the integer types are big-endian.
/// Both were confirmed against this machine rather than assumed.
public enum SMCValue {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Float(bitPattern: bits)
            return value.isFinite ? Double(value) : nil

        case "ioft":
            // 64-bit little-endian fixed point, 16 fractional bits.
            guard bytes.count >= 8 else { return nil }
            var raw: UInt64 = 0
            for i in (0..<8).reversed() { raw = raw << 8 | UInt64(bytes[i]) }
            return Double(raw) / 65536.0

        case "ui8 ", "si8 ":
            guard let first = bytes.first else { return nil }
            return type == "si8 " ? Double(Int8(bitPattern: first)) : Double(first)

        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))

        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))

        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))

        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0

        case "flag":
            guard let first = bytes.first else { return nil }
            return first == 0 ? 0 : 1

        default:
            return nil
        }
    }

    public static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        switch type {
        case "flt ":
            guard size == 4 else { return nil }
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]

        case "ui8 ", "flag":
            guard size == 1 else { return nil }
            return [UInt8(max(0, min(255, value.rounded())))]

        case "ui16":
            guard size == 2 else { return nil }
            let v = UInt16(max(0, min(65535, value.rounded())))
            return [UInt8(v >> 8), UInt8(v & 0xff)]

        case "fpe2":
            guard size == 2 else { return nil }
            let v = UInt16(max(0, min(16383, (value * 4).rounded())))
            return [UInt8(v >> 8), UInt8(v & 0xff)]

        default:
            return nil
        }
    }

    /// True for payload types that carry a physical reading we can chart.
    public static func isNumeric(type: String) -> Bool {
        ["flt ", "ioft", "ui8 ", "si8 ", "ui16", "si16", "ui32", "fpe2"].contains(type)
    }
}
