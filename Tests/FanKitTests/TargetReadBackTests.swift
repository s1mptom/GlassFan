import Testing
@testable import FanKit

/// Read back from the SMC after writing a fan target, measured on two machines: an
/// M3 Pro keeps its own value when it ignores a write (0 against 5349 asked), and an
/// M1 Max takes every write but on its next pass, so a read straight after the write
/// still shows the target before it.
@Suite("Fan target read-back")
struct TargetReadBackTests {
    @Test("taken at once: the read-back is what was asked")
    func immediate() {
        #expect(TargetReadBack.took(asked: 3000, readAfter: 3002, readBefore: 2900, lastAsked: 2900))
    }

    @Test("an M1 applies a target on its next pass: the last one showing before this write counts")
    func applyLag() {
        // Logged on an M1 Max: asked 1321, read back 1296 - the target written a second before.
        #expect(TargetReadBack.took(asked: 1321, readAfter: 1296, readBefore: 1296, lastAsked: 1296))
    }

    @Test("an M3 keeping its own value is not mistaken for lag")
    func ignored() {
        #expect(!TargetReadBack.took(asked: 5349, readAfter: 0, readBefore: 0, lastAsked: 5349))
    }

    @Test("the first write, with nothing written before it, is judged on its read-back alone")
    func firstWrite() {
        #expect(!TargetReadBack.took(asked: 1296, readAfter: 1212, readBefore: 1212, lastAsked: nil))
        #expect(TargetReadBack.took(asked: 1296, readAfter: 1296, readBefore: 1212, lastAsked: nil))
    }

    @Test("nothing readable is nothing taken")
    func unreadable() {
        #expect(!TargetReadBack.took(asked: 2000, readAfter: nil, readBefore: nil, lastAsked: 2000))
    }
}
