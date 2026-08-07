// App/HistogramView.swift
import SwiftUI

struct HistogramView: View {
    let bins: [UInt32]   // 192 values: R[0..63], G[64..127], B[128..191]

    var body: some View {
        Canvas { context, size in
            guard bins.count == 192 else { return }
            let maxBin = max(bins.max() ?? 1, 1)
            let channels: [(Range<Int>, Color)] = [
                (0..<64, .red), (64..<128, .green), (128..<192, .blue),
            ]
            for (range, color) in channels {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for (i, binIndex) in range.enumerated() {
                    let x = size.width * CGFloat(i) / 63
                    let y = size.height * (1 - CGFloat(bins[binIndex]) / CGFloat(maxBin))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.6)))
            }
        }
        .frame(width: 100, height: 46)
        .background(Theme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
    }
}
