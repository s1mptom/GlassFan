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

    func append(_ sample: HistorySample) {
        lock.lock()
        defer { lock.unlock() }
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
