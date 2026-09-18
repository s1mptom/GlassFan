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

    @Test("a goodbye is its own command, not a release in disguise")
    func goodbyeRoundTrip() throws {
        let data = try NDJSONEncoder.encode(ClientCommand.goodbye)
        var buffer = NDJSONDecoderBuffer()
        guard case .goodbye? = try buffer.append(data, as: ClientCommand.self).first else {
            Issue.record("wrong case"); return
        }
        // The distinction is the point: the panic button rewrites the settings to
        // auto, a goodbye leaves them alone and only stops applying them.
        let panic = try NDJSONEncoder.encode(ClientCommand.releaseAll)
        #expect(panic != data)
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

/// A daemon and an app are installed together but do not have to be restarted
/// together, so every field added to the wire has to survive meeting the other side
/// of its own age.
@Suite("Wire protocol across versions")
struct ProtocolCompatibilityTests {

    @Test("a snapshot from a daemon that knows nothing of the new fields still decodes")
    func olderDaemonStillDecodes() throws {
        // Exactly what 0.1.1 put on the wire: no setpoints, no engines, and a fan
        // reading whose failure is a string and nothing more.
        let json = """
        {"snapshot":{"_0":{"time":1700000000,"sensors":[{"key":"TCMz","value":73.8}],\
        "fans":[{"index":0,"actualRPM":0,"targetRPM":5349,"limits":{"minRPM":1350,"maxRPM":5349},\
        "mode":"fixed","forced":true,"emergency":false,"writeError":"SMC key F0Tg refused the write"}],\
        "config":{"emergencyTemp":95,"pollInterval":1,"trackedSensors":[],"fans":[]},\
        "daemonVersion":"0.1.1"}}}
        """
        var buffer = NDJSONDecoderBuffer()
        let decoded = try buffer.append(Data((json + "\n").utf8), as: DaemonMessage.self)
        guard case .snapshot(let snapshot) = decoded.first else {
            Issue.record("not a snapshot"); return
        }
        #expect(snapshot.smcZoneTargets == nil)
        #expect(snapshot.sensorEngines == nil)
        #expect(snapshot.fans[0].writeFailure == nil)
        #expect(snapshot.fans[0].writeError != nil)
    }

    @Test("the two ways a fan write can fail are told apart on the wire")
    func failureKindSurvives() throws {
        for failure in [FanWriteFailure.refused, .ignored] {
            let reading = FanReading(index: 0, actualRPM: 0, targetRPM: 0,
                                     limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                                     mode: .fixed, forced: false, drivingTemp: nil,
                                     emergency: false, writeError: "…", writeFailure: failure)
            let data = try NDJSONEncoder.encode(DaemonMessage.snapshot(
                Snapshot(time: 0, sensors: [], fans: [reading], config: .default(fanCount: 1),
                         daemonVersion: "test")))
            var buffer = NDJSONDecoderBuffer()
            guard case .snapshot(let snapshot)? = try buffer.append(data, as: DaemonMessage.self).first
            else { Issue.record("not a snapshot"); return }
            #expect(snapshot.fans[0].writeFailure == failure)
        }
    }
}

extension ProtocolCompatibilityTests {
    @Test("a learned floor survives the wire, and its absence is not a zero")
    func learnedFloorSurvives() throws {
        let known = FanReading(index: 0, actualRPM: 968, targetRPM: 446,
                               limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                               mode: .curve, forced: true, drivingTemp: 31, emergency: false,
                               learnedFloor: 968)
        let data = try NDJSONEncoder.encode(DaemonMessage.snapshot(
            Snapshot(time: 0, sensors: [], fans: [known], config: .default(fanCount: 1),
                     daemonVersion: "test")))
        var buffer = NDJSONDecoderBuffer()
        guard case .snapshot(let snapshot)? = try buffer.append(data, as: DaemonMessage.self).first
        else { Issue.record("not a snapshot"); return }
        #expect(snapshot.fans[0].learnedFloor == 968)

        // Not yet learned is nil, not 0 - a floor of zero would be a fan that stops,
        // which is a claim, and the editor would draw a line along the bottom for it.
        let unknown = FanReading(index: 0, actualRPM: 0, targetRPM: 0,
                                 limits: FanLimits(minRPM: 1350, maxRPM: 5349),
                                 mode: .auto, forced: false, drivingTemp: nil, emergency: false)
        #expect(unknown.learnedFloor == nil)
    }
}
