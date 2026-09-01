import Foundation

/// One second of throughput, in megabits per second.
struct SpeedSample: Sendable, Equatable {
    var downMbps: Double
    var upMbps: Double

    static let zero = SpeedSample(downMbps: 0, upMbps: 0)
}
