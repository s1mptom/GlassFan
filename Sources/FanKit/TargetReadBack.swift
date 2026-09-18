import Foundation

/// Whether the SMC took a fan target, judged from what it reads back.
///
/// A write returning success does not mean the target was kept: an M3 Pro answered
/// every write with success and kept its own value, 0 against 5349 asked. So the
/// target is read back. But an M1 Max takes every write on its next pass rather than
/// at once: read straight after, the key still holds the target written a second
/// before, and every write on a moving curve looked ignored - three in a row, and the
/// daemon gave up fans it was in fact holding.
///
/// So a write counts as taken if the key reads back as asked, or if, just before it,
/// the key held what was asked last time - the last write went through, and this one
/// will be judged the same way on the next tick. An ignored write matches neither.
public enum TargetReadBack {
    /// The SMC rounds targets in its own float; a few rpm either way is the same target.
    public static let tolerance = 5.0

    public static func took(asked: Double, readAfter: Double?, readBefore: Double?,
                            lastAsked: Double?) -> Bool {
        if let after = readAfter, abs(after - asked) <= tolerance { return true }
        if let before = readBefore, let last = lastAsked, abs(before - last) <= tolerance { return true }
        return false
    }
}
