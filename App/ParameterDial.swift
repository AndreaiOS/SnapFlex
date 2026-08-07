import SwiftUI
import SnapFlexCore

struct ParameterDial: View {
    let engine: CameraEngine
    let parameter: SelectedParameter

    @State private var dragStartNormalized: Double?

    var body: some View {
        VStack(spacing: 6) {
            Text(currentLabel)
                .font(Theme.valueFont(15))
                .foregroundStyle(Theme.accent)
            GeometryReader { geo in
                dialTrack
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                if dragStartNormalized == nil {
                                    dragStartNormalized = currentNormalized
                                }
                                let delta = drag.translation.width / geo.size.width
                                apply(normalized: (dragStartNormalized! + delta).clamped01)
                            }
                            .onEnded { _ in dragStartNormalized = nil }
                    )
            }
            .frame(height: 28)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.chrome)
    }

    private var dialTrack: some View {
        ZStack {
            HStack(spacing: 5) {
                ForEach(0..<41, id: \.self) { index in
                    Rectangle()
                        .fill(index == 20 ? Theme.accent : Theme.inactiveText.opacity(0.5))
                        .frame(width: 1.5, height: index % 5 == 0 ? 16 : 9)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Value mapping (log for ISO/shutter, linear otherwise)

    private var currentNormalized: Double {
        let ranges = engine.ranges
        let values = engine.values
        switch parameter {
        case .iso:
            let iso = Double(values.iso ?? Float(midLog(Double(ranges.iso.lowerBound), Double(ranges.iso.upperBound))))
            return normalizedLog(iso, Double(ranges.iso.lowerBound), Double(ranges.iso.upperBound))
        case .shutter:
            let seconds = values.shutterSeconds ??
                midLog(ranges.shutterSeconds.lowerBound, ranges.shutterSeconds.upperBound)
            return normalizedLog(seconds, ranges.shutterSeconds.lowerBound, ranges.shutterSeconds.upperBound)
        case .ev:
            return normalizedLinear(Double(values.evBias),
                                    Double(ranges.evBias.lowerBound), Double(ranges.evBias.upperBound))
        case .focus:
            return Double(values.focusPosition ?? 0.5)
        case .wb:
            return normalizedLinear(Double(values.wbKelvin ?? 5500),
                                    Double(ManualValues.wbKelvinRange.lowerBound),
                                    Double(ManualValues.wbKelvinRange.upperBound))
        }
    }

    private func apply(normalized: Double) {
        let ranges = engine.ranges
        switch parameter {
        case .iso:
            engine.setISO(Float(valueLog(normalized, Double(ranges.iso.lowerBound), Double(ranges.iso.upperBound))))
        case .shutter:
            engine.setShutter(valueLog(normalized, ranges.shutterSeconds.lowerBound, ranges.shutterSeconds.upperBound))
        case .ev:
            let value = valueLinear(normalized, Double(ranges.evBias.lowerBound), Double(ranges.evBias.upperBound))
            engine.setEVBias((Float(value) * 10).rounded() / 10)
        case .focus:
            engine.setFocus(Float(normalized))
        case .wb:
            let kelvin = valueLinear(normalized, Double(ManualValues.wbKelvinRange.lowerBound),
                                     Double(ManualValues.wbKelvinRange.upperBound))
            engine.setWhiteBalance(kelvin: Int((kelvin / 100).rounded() * 100))
        }
    }

    private var currentLabel: String {
        let values = engine.values
        switch parameter {
        case .iso: return "ISO \(values.iso.map { String(Int($0)) } ?? "AUTO")"
        case .shutter: return values.shutterSeconds.map(Format.shutter) ?? "AUTO"
        case .ev: return String(format: "EV %+.1f", values.evBias)
        case .focus: return values.focusPosition.map { String(format: "FOCUS %.2f", $0) } ?? "AF"
        case .wb: return values.wbKelvin.map { "\($0)K" } ?? "AWB"
        }
    }

    private func normalizedLog(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low, low > 0 else { return 0.5 }
        return (log(value) - log(low)) / (log(high) - log(low))
    }
    private func valueLog(_ normalized: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low, low > 0 else { return low }
        return exp(log(low) + normalized * (log(high) - log(low)))
    }
    private func normalizedLinear(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low else { return 0.5 }
        return (value - low) / (high - low)
    }
    private func valueLinear(_ normalized: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low else { return low }
        return low + normalized * (high - low)
    }
    private func midLog(_ low: Double, _ high: Double) -> Double { (low * high).squareRoot() }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
