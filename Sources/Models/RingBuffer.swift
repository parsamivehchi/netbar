import Foundation

/// Fixed-capacity ring of speed samples. Preallocated; append never allocates.
struct RingBuffer: Sendable {
    private var storage: [SpeedSample]
    private var head = 0
    private(set) var count = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: .zero, count: capacity)
    }

    mutating func append(_ sample: SpeedSample) {
        storage[head] = sample
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Oldest-to-newest snapshot. Allocates; call only when drawing (panel open).
    var ordered: [SpeedSample] {
        guard count > 0 else { return [] }
        if count < capacity { return Array(storage[0..<count]) }
        return Array(storage[head..<capacity] + storage[0..<head])
    }
}
