import SwiftUI
import SnapFlexCore
import UIKit

struct ParameterDial: View {
    let engine: CameraEngine
    let parameter: SelectedParameter

    @State private var dragStartNormalized: Double?
    @State private var decayTask: Task<Void, Never>?
    @State private var lastDetentIndex: Int?

    // MARK: - Momentum tuning

    private static let velocityStopThreshold: Double = 0.05   // normalized units / sec
    private static let decayTimestep: Double = 1.0 / 60.0
    private static let decayFriction: Double = 0.93            // per-step multiplier
    private static let maxDecayIterations = 240                 // ~4s safety cap

    // MARK: - Visual layout (tick ruler)

    private static let tickSpacing: CGFloat = 8
    private static let tickStripHeight: CGFloat = 26
    private static let needleWidth: CGFloat = 2
    private static let needleHeight: CGFloat = 32
    private static let needleOverhang: CGFloat = (needleHeight - tickStripHeight) / 2
    private static let labelHeight: CGFloat = 12
    private static let labelGap: CGFloat = 16
    private static let needleTopOffset: CGFloat = labelHeight + labelGap
    private static let stripTopOffset: CGFloat = needleTopOffset + needleOverhang
    private static let dialHeight: CGFloat = needleTopOffset + needleHeight

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                tickStrip(width: geo.size.width)
                    .offset(y: Self.stripTopOffset)
                needle
                    .offset(y: Self.needleTopOffset)
                valueLabel
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        decayTask?.cancel()
                        decayTask = nil
                        if dragStartNormalized == nil {
                            dragStartNormalized = currentNormalized
                            lastDetentIndex = detentPlan.map {
                                nearestDetentIndex(currentNormalized, in: $0)
                            }
                        }
                        let delta = drag.translation.width / geo.size.width
                        let newNormalized = (dragStartNormalized! + delta).clamped01
                        apply(normalized: newNormalized)
                        registerDetentCrossing(at: newNormalized)
                    }
                    .onEnded { drag in
                        dragStartNormalized = nil
                        let width = max(Double(geo.size.width), 1)
                        let normalizedVelocity = Double(drag.velocity.width) / width
                        startDecay(initialVelocity: normalizedVelocity)
                    }
            )
        }
        .frame(height: Self.dialHeight)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.chrome)
        .onChange(of: parameter) { _, _ in
            decayTask?.cancel()
            decayTask = nil
            dragStartNormalized = nil
            lastDetentIndex = nil
        }
        .onDisappear {
            decayTask?.cancel()
            decayTask = nil
        }
    }

    private var valueLabel: some View {
        Text(currentLabel)
            .font(Theme.valueFont(9))
            .foregroundStyle(Theme.accent)
            .contentTransition(.numericText())
            .animation(Theme.motion(Theme.springStandard), value: currentLabel)
            .frame(height: Self.labelHeight)
    }

    private var needle: some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(width: Self.needleWidth, height: Self.needleHeight)
            .shadow(color: Theme.accent.opacity(0.8), radius: 8)
    }

    /// Scrolling tick strip: drawn across 3x the visible width so the ruler
    /// never runs out of ticks near the edges, then clipped back to the
    /// visible width and edge-faded. Offset is a pure function of the
    /// gesture engine's existing `currentNormalized` — no second state.
    private func tickStrip(width: CGFloat) -> some View {
        let contentWidth = width * 3
        let stripWidth = width * 2
        let offsetX = -(currentNormalized - 0.5) * stripWidth
        return Canvas { context, size in
            var x: CGFloat = 0
            while x <= size.width {
                let tick = Path(CGRect(x: x, y: 0, width: 1, height: size.height))
                context.fill(tick, with: .color(.white.opacity(0.28)))
                x += Self.tickSpacing
            }
        }
        .frame(width: contentWidth, height: Self.tickStripHeight)
        .offset(x: offsetX)
        .frame(width: width, height: Self.tickStripHeight)
        .clipped()
        .mask { edgeFadeMask }
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.18),
                .init(color: .white, location: 0.82),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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

    // MARK: - Detents

    /// A parameter's detent list in both its real domain (for exact snapping)
    /// and normalized domain (for distance comparisons against drag position).
    private struct DetentPlan {
        let values: [Double]
        let normalized: [Double]
    }

    /// Real-domain detent values for the active parameter, intersected with the
    /// device's current range. `nil` for parameters with no detents (focus).
    private var detentValues: [Double]? {
        let ranges = engine.ranges
        switch parameter {
        case .iso:
            let stops: [Double] = [25, 50, 100, 200, 400, 800, 1600, 3200]
            let low = Double(ranges.iso.lowerBound), high = Double(ranges.iso.upperBound)
            return withEndpoints(stops.filter { $0 >= low && $0 <= high }, low: low, high: high)
        case .shutter:
            return withEndpoints(RealCameraDevice.shutterStops(in: ranges.shutterSeconds),
                                 low: ranges.shutterSeconds.lowerBound,
                                 high: ranges.shutterSeconds.upperBound)
        case .ev:
            let low = Double(ranges.evBias.lowerBound), high = Double(ranges.evBias.upperBound)
            guard high > low else { return [low] }
            let startTenths = Int((low * 10).rounded())
            let endTenths = Int((high * 10).rounded())
            guard endTenths >= startTenths else { return [low] }
            return (startTenths...endTenths).map { Double($0) / 10 }
        case .wb:
            let low = ManualValues.wbKelvinRange.lowerBound
            let high = ManualValues.wbKelvinRange.upperBound
            return stride(from: low, through: high, by: 100).map(Double.init)
        case .focus:
            return nil
        }
    }

    /// Stop grids rarely reach the sensor's true limits (e.g. minISO 55 vs the
    /// first stop at 100), which made the endpoints unreachable after detent
    /// snap. Always include the exact range bounds as detents.
    private func withEndpoints(_ stops: [Double], low: Double, high: Double) -> [Double] {
        guard high > low else { return [low] }
        var values = stops
        let epsilon = (high - low) * 0.001
        if values.first.map({ abs($0 - low) > epsilon }) ?? true { values.insert(low, at: 0) }
        if values.last.map({ abs($0 - high) > epsilon }) ?? true { values.append(high) }
        return values
    }

    private func normalizedForDetent(_ value: Double) -> Double {
        let ranges = engine.ranges
        switch parameter {
        case .iso:
            return normalizedLog(value, Double(ranges.iso.lowerBound), Double(ranges.iso.upperBound))
        case .shutter:
            return normalizedLog(value, ranges.shutterSeconds.lowerBound, ranges.shutterSeconds.upperBound)
        case .ev:
            return normalizedLinear(value, Double(ranges.evBias.lowerBound), Double(ranges.evBias.upperBound))
        case .wb:
            return normalizedLinear(value, Double(ManualValues.wbKelvinRange.lowerBound),
                                    Double(ManualValues.wbKelvinRange.upperBound))
        case .focus:
            return value
        }
    }

    private var detentPlan: DetentPlan? {
        guard let values = detentValues, !values.isEmpty else { return nil }
        return DetentPlan(values: values, normalized: values.map(normalizedForDetent))
    }

    private func nearestDetentIndex(_ normalized: Double, in plan: DetentPlan) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, candidate) in plan.normalized.enumerated() {
            let distance = abs(candidate - normalized)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Fires one `Haptics.light()` per detent boundary crossed — never per frame.
    private func registerDetentCrossing(at normalized: Double) {
        guard let plan = detentPlan else {
            lastDetentIndex = nil
            return
        }
        let index = nearestDetentIndex(normalized, in: plan)
        if index != lastDetentIndex {
            Haptics.light()
            lastDetentIndex = index
        }
    }

    private func applyDetentValue(_ value: Double) {
        switch parameter {
        case .iso: engine.setISO(Float(value))
        case .shutter: engine.setShutter(value)
        case .ev: engine.setEVBias(Float(value))
        case .wb: engine.setWhiteBalance(kelvin: Int(value))
        case .focus: break   // continuous — no snap
        }
    }

    private func finalizeSnap(normalized: Double) {
        guard let plan = detentPlan else { return }
        let index = nearestDetentIndex(normalized, in: plan)
        lastDetentIndex = index
        applyDetentValue(plan.values[index])
    }

    // MARK: - Momentum

    /// On drag release, decays the last known velocity to zero (one main-actor
    /// step per ~16ms), then snaps to the nearest detent. Cancelled by a new
    /// drag, a parameter switch, or the view disappearing. Reduce Motion skips
    /// the animated decay entirely and snaps immediately.
    private func startDecay(initialVelocity: Double) {
        decayTask?.cancel()
        guard !UIAccessibility.isReduceMotionEnabled else {
            finalizeSnap(normalized: currentNormalized)
            return
        }
        decayTask = Task { @MainActor in
            var normalized = currentNormalized
            var velocity = initialVelocity
            var iterations = 0
            while !Task.isCancelled,
                  abs(velocity) > Self.velocityStopThreshold,
                  iterations < Self.maxDecayIterations,
                  normalized > 0, normalized < 1 {
                normalized = (normalized + velocity * Self.decayTimestep).clamped01
                apply(normalized: normalized)
                registerDetentCrossing(at: normalized)
                velocity *= Self.decayFriction
                iterations += 1
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            finalizeSnap(normalized: normalized)
            decayTask = nil
        }
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
