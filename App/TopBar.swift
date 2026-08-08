// App/TopBar.swift
import SwiftUI
import SnapFlexCore

enum AspectRatio: CaseIterable {
    case fourThree, sixteenNine, square

    var label: String {
        switch self {
        case .fourThree: "3:4"
        case .sixteenNine: "16:9"
        case .square: "1:1"
        }
    }

    /// Height of the visible band for a given preview width (portrait orientation).
    func heightFraction(ofWidth width: CGFloat) -> CGFloat {
        switch self {
        case .fourThree: width * 4 / 3
        case .sixteenNine: width * 16 / 9
        case .square: width
        }
    }
}

struct AspectMask: View {
    let aspect: AspectRatio

    var body: some View {
        GeometryReader { geo in
            let visible = min(geo.size.height, aspect.heightFraction(ofWidth: geo.size.width))
            let band = max(0, (geo.size.height - visible) / 2)
            VStack(spacing: 0) {
                Color.black.opacity(0.45).frame(height: band)
                Color.clear
                Color.black.opacity(0.45).frame(height: band)
            }
        }
        .allowsHitTesting(false)
    }
}

struct TopBar: View {
    let engine: CameraEngine
    @Binding var aspect: AspectRatio
    @Binding var timerDuration: Int
    @Binding var showGrid: Bool
    @Binding var showLevel: Bool
    var rotation: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            chip(engine.formatSelection.raw.rawValue) { cycleFormat() }
            chip(engine.flashOn ? "FLASH ON" : "FLASH OFF") { engine.flashOn.toggle() }
            chip(aspect.label) { aspect = next(aspect, in: AspectRatio.allCases) }
            chip(timerDuration == 0 ? "TIMER OFF" : "\(timerDuration)s") {
                timerDuration = timerDuration == 0 ? 3 : timerDuration == 3 ? 10 : 0
            }
            chip(engine.bracketCount.map { "BKT \($0)" } ?? "BKT OFF") {
                engine.bracketCount = engine.bracketCount == nil ? 3
                    : engine.bracketCount == 3 ? 5 : nil
            }
            Spacer()
            assistMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.chrome)
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(Theme.valueFont(10))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .rotatesWithDevice(rotation)
        }
        .buttonStyle(.plain)
    }

    private var assistMenu: some View {
        Menu {
            Toggle("Histogram", isOn: overlayBinding(\.histogramEnabled))
            Toggle("Focus Peaking", isOn: overlayBinding(\.peakingEnabled))
            Toggle("Zebra", isOn: overlayBinding(\.zebraEnabled))
            Toggle("Grid", isOn: $showGrid)
            Toggle("Level", isOn: $showLevel)
            Toggle("HEIF companion", isOn: Binding(
                get: { engine.formatSelection.heifCompanion },
                set: { engine.formatSelection.heifCompanion = $0 }))
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(Theme.accent)
                .padding(6)
                .rotatesWithDevice(rotation)
        }
    }

    private func overlayBinding(_ keyPath: WritableKeyPath<OverlaySettings, Bool>) -> Binding<Bool> {
        Binding(get: { engine.overlaySettings[keyPath: keyPath] },
                set: { engine.overlaySettings[keyPath: keyPath] = $0 })
    }

    private func cycleFormat() {
        var modes = RAWMode.allCases
        if !engine.capabilities.supportsProRAW { modes.removeAll { $0 == .proRAW } }
        engine.formatSelection.raw = next(engine.formatSelection.raw, in: modes)
    }

    private func next<T: Equatable>(_ value: T, in cases: [T]) -> T {
        guard let index = cases.firstIndex(of: value) else { return cases[0] }
        return cases[(index + 1) % cases.count]
    }
}
