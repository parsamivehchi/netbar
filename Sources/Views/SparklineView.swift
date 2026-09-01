import SwiftUI

/// 60-second throughput sparkline. Plain Canvas paths - deliberately not Swift Charts.
struct SparklineView: View {
    let samples: [SpeedSample]  // oldest -> newest

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let maxValue = max(
                samples.lazy.map(\.downMbps).max() ?? 0,
                samples.lazy.map(\.upMbps).max() ?? 0,
                0.1
            )
            context.stroke(path(\.downMbps, in: size, maxValue: maxValue),
                           with: .color(.accentColor), lineWidth: 1.5)
            context.stroke(path(\.upMbps, in: size, maxValue: maxValue),
                           with: .color(.secondary.opacity(0.55)), lineWidth: 1)
        }
        .frame(height: 32)
        .accessibilityLabel("Throughput over the last minute")
    }

    private func path(_ key: KeyPath<SpeedSample, Double>, in size: CGSize, maxValue: Double) -> Path {
        var p = Path()
        let stepX = size.width / CGFloat(samples.count - 1)
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * stepX
            let y = size.height - CGFloat(sample[keyPath: key] / maxValue) * (size.height - 2) - 1
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
