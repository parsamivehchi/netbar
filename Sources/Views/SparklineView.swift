import SwiftUI

/// 2-minute throughput sparkline (60 slots x 2 s). Plain Canvas paths - deliberately
/// not Swift Charts. Hovering shows a crosshair and feeds hoverIndex back to the model
/// so the header can display the hovered moment's values.
struct SparklineView: View {
    let model: AppViewModel
    let samples: [SpeedSample]  // oldest -> newest

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard samples.count > 1 else { return }
                let maxValue = maxV
                context.stroke(path(\.downMbps, in: size, maxValue: maxValue),
                               with: .color(.accentColor), lineWidth: 1.5)
                context.stroke(path(\.upMbps, in: size, maxValue: maxValue),
                               with: .color(.secondary.opacity(0.55)), lineWidth: 1)
                if let idx = model.hoverIndex, idx >= 0, idx < samples.count {
                    let x = CGFloat(idx) * size.width / CGFloat(samples.count - 1)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                    let s = samples[idx]
                    for (v, color) in [(s.downMbps, Color.accentColor), (s.upMbps, .secondary)] {
                        let y = yFor(v, in: size, maxValue: maxValue)
                        let dot = Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
                        context.fill(dot, with: .color(color))
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    guard samples.count > 1, geo.size.width > 0 else { return }
                    let idx = Int((point.x / geo.size.width * CGFloat(samples.count - 1)).rounded())
                    model.hoverIndex = min(max(idx, 0), samples.count - 1)
                case .ended:
                    model.hoverIndex = nil
                }
            }
        }
        .frame(height: 32)
        .accessibilityLabel("Throughput over the last two minutes")
    }

    private var maxV: Double {
        max(samples.lazy.map(\.downMbps).max() ?? 0,
            samples.lazy.map(\.upMbps).max() ?? 0,
            0.1)
    }

    private func yFor(_ value: Double, in size: CGSize, maxValue: Double) -> CGFloat {
        size.height - CGFloat(value / maxValue) * (size.height - 2) - 1
    }

    private func path(_ key: KeyPath<SpeedSample, Double>, in size: CGSize, maxValue: Double) -> Path {
        var p = Path()
        let stepX = size.width / CGFloat(samples.count - 1)
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * stepX
            let y = yFor(sample[keyPath: key], in: size, maxValue: maxValue)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
