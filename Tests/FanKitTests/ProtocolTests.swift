import Testing
import Foundation
@testable import FanKit

@Suite("Wire protocol")
struct ProtocolTests {
    func makeSnapshot() -> Snapshot {
        Snapshot(
            time: 1_700_000_000,
            sensors: [SensorReading(key: "TCMz", value: 73.8)],
            fans: [FanReading(index: 0, actualRPM: 1522, targetRPM: 2330,
                              limits: FanLimits(minRPM: 1499, maxRPM: 5348),
                              mode: .curve, forced: true, drivingTemp: 73.8, emergency: false)],
            config: .default(fanCount: 2),
            daemonVersion: "test"
        )
    }

    @Test("a snapshot survives the round trip")
    func snapshotRoundTrip() throws {
        let message = DaemonMessage.snapshot(makeSnapshot())
        let data = try NDJSONEncoder.encode(message)
        var buffer = NDJSONDecoderBuffer()
        let decoded = try buffer.append(data, as: DaemonMessage.self)
        #expect(decoded.count == 1)
        guard case .snapshot(let s) = decoded[0] else { Issue.record("wrong case"); return }
        #expect(s.sensors.first?.key == "TCMz")
        #expect(s.fans.first?.targetRPM == 2330)
    }

    @Test("commands survive the round trip")
    func commandRoundTrip() throws {
        let data = try NDJSONEncoder.encode(ClientCommand.setConfig(.default(fanCount: 2)))
        var buffer = NDJSONDecoderBuffer()
        let decoded = try buffer.append(data, as: ClientCommand.self)
        guard case .setConfig(let cfg) = decoded.first else { Issue.record("wrong case"); return }
        #expect(cfg.fans.count == 2)
    }

    @Test("a message split across chunks is reassembled")
    func splitAcrossChunks() throws {
        let data = try NDJSONEncoder.encode(ClientCommand.hello)
        var buffer = NDJSONDecoderBuffer()
        let half = data.count / 2
        #expect(try buffer.append(data.prefix(half), as: ClientCommand.self).isEmpty)
        let rest = try buffer.append(data.suffix(from: half), as: ClientCommand.self)
        #expect(rest.count == 1)
    }

    @Test("several messages glued into one chunk all come out")
    func gluedMessages() throws {
        var data = Data()
        data.append(try NDJSONEncoder.encode(ClientCommand.hello))
        data.append(try NDJSONEncoder.encode(ClientCommand.releaseAll))
        data.append(try NDJSONEncoder.encode(ClientCommand.hello))
        var buffer = NDJSONDecoderBuffer()
        #expect(try buffer.append(data, as: ClientCommand.self).count == 3)
    }

    @Test("a corrupt line is skipped without losing the next message")
    func corruptLine() throws {
        var data = Data("{ this is not json }\n".utf8)
        data.append(try NDJSONEncoder.encode(ClientCommand.hello))
        var buffer = NDJSONDecoderBuffer()
        let decoded = try buffer.append(data, as: ClientCommand.self)
        #expect(decoded.count == 1)
    }

    @Test("blank lines are ignored")
    func blankLines() throws {
        var data = Data("\n\n".utf8)
        data.append(try NDJSONEncoder.encode(ClientCommand.hello))
        var buffer = NDJSONDecoderBuffer()
        #expect(try buffer.append(data, as: ClientCommand.self).count == 1)
    }

    @Test("a peer that never sends a newline is cut off")
    func floodProtection() throws {
        var buffer = NDJSONDecoderBuffer(maxMessageBytes: 1024)
        let flood = Data(repeating: UInt8(ascii: "x"), count: 2048)
        #expect(throws: NDJSONDecoderBuffer.BufferError.self) {
            _ = try buffer.append(flood, as: ClientCommand.self)
        }
    }
}
