import Foundation
import FanKit

/// Fixed-size ring of recent samples, so a freshly opened window has a chart to draw.
final class History {
    private var samples: [HistorySample] = []
    private let capacity: Int
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    /// Appended since the last `markSaved()`, so a sleeping or idle daemon does
    /// not rewrite the same file.
    private var dirty = false

    func restore(_ restored: [HistorySample]) {
        lock.lock()
        defer { lock.unlock() }
        samples = Array(restored.suffix(capacity))
    }

    /// The samples if anything changed since the last save, else nil.
    func unsaved() -> [HistorySample]? {
        lock.lock()
        defer { lock.unlock() }
        return dirty ? samples : nil
    }

    func markSaved() {
        lock.lock()
        defer { lock.unlock() }
        dirty = false
    }

    func append(_ sample: HistorySample) {
        lock.lock()
        defer { lock.unlock() }
        dirty = true
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func all() -> [HistorySample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
