import Foundation
import CSMC
import FanKit

/// Swift face of the SMC. Serialises access; every call goes through one queue.
final class SMCDevice {
    enum Failure: Error, CustomStringConvertible {
        case cannotOpen
        case notPrivileged
        case unwritable(String)

        var description: String {
            switch self {
            case .cannotOpen: return "cannot open AppleSMC"
            case .notPrivileged: return "SMC write refused: run as root"
            case .unwritable(let key): return "SMC key \(key) refused the write"
            }
        }
    }

    init() throws {
        guard smc_open() == SMC_OK else { throw Failure.cannotOpen }
    }

    deinit { smc_close() }

    func readRaw(_ key: String) -> (bytes: [UInt8], type: String)? {
        var buf = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        var type: UInt32 = 0
        let result = buf.withUnsafeMutableBufferPointer { ptr in
            smc_read(smc_key_from_string(key), ptr.baseAddress, &size, &type)
        }
        guard result == SMC_OK, size > 0, size <= 32 else { return nil }
        return (Array(buf.prefix(Int(size))), Self.typeString(type))
    }

    func read(_ key: String) -> (value: Double, type: String)? {
        guard let raw = readRaw(key),
              let value = SMCValue.decode(type: raw.type, bytes: raw.bytes) else { return nil }
        return (value, raw.type)
    }

    /// Writes `value` to `key`, encoding it the way the key itself declares.
    func write(_ key: String, value: Double) throws {
        guard let raw = readRaw(key) else { throw Failure.unwritable(key) }
        guard let bytes = SMCValue.encode(value, type: raw.type, size: raw.bytes.count) else {
            throw Failure.unwritable(key)
        }
        let result = bytes.withUnsafeBufferPointer { ptr in
            smc_write(smc_key_from_string(key), ptr.baseAddress, UInt32(bytes.count))
        }
        if result == SMC_ERR_NOT_PRIVILEGED { throw Failure.notPrivileged }
        guard result == SMC_OK else { throw Failure.unwritable(key) }
    }

    /// Every key on this machine that carries a temperature, with its reading.
    ///
    /// One place, because three callers - the daemon, `--probe` and `--dump-sensors`
    /// - have to agree on what counts as a sensor, and the moment they disagree the
    /// dump stops describing what the app shows.
    func temperatureReadings() -> [(key: String, type: String, value: Double)] {
        allKeys().filter { $0.hasPrefix("T") }.compactMap { key in
            guard let reading = read(key),
                  SensorCatalog.looksLikeTemperature(key: key, type: reading.type, value: reading.value)
            else { return nil }
            return (key, reading.type, reading.value)
        }
    }

    /// The temperatures the SMC's own fan control is steering its zones towards.
    /// Not sensors, and deliberately not in the list above.
    func zoneTargets() -> [(zone: Int, key: String, target: Double)] {
        allKeys().compactMap { key in
            guard let zone = SensorCatalog.smcZoneTarget(key: key),
                  let reading = read(key), reading.value > 0 else { return nil }
            return (zone, key, reading.value)
        }.sorted { $0.zone < $1.zone }
    }

    func allKeys() -> [String] {
        var count: UInt32 = 0
        guard smc_key_count(&count) == SMC_OK else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<count {
            var key: UInt32 = 0
            guard smc_key_at_index(index, &key) == SMC_OK else { continue }
            keys.append(Self.typeString(key))
        }
        return keys
    }

    private static func typeString(_ value: UInt32) -> String {
        let bytes = [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff),
                     UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
