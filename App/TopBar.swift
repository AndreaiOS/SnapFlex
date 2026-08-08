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
    var longAvailable: Bool = true

    var body: some View {
        // Two semantic rows, no scrolling: row 1 is the image pipeline
        // (format, processing, flash, timer), row 2 the shooting modes.
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                chip(engine.formatSelection.raw.rawValue,
                     highlighted: engine.formatSelection.raw != .off) { cycleFormat() }
                chip(engine.processingLevel.rawValue) { engine.processingLevel = engine.processingLevel.next }
                chip("FLASH", highlighted: engine.flashOn) { engine.flashOn.toggle() }
                chip(timerDuration == 0 ? "TIMER" : "\(timerDuration)s",
                     highlighted: timerDuration > 0) {
                    timerDuration = timerDuration == 0 ? 3 : timerDuration == 3 ? 10 : 0
                }
                Spacer()
                assistMenu
            }
            HStack(spacing: 6) {
                chip(aspect.label) { aspect = next(aspect, in: AspectRatio.allCases) }
                chip(engine.bracketCount.map { "BKT \($0)" } ?? "BKT",
                     highlighted: engine.bracketCount != nil) {
                    engine.bracketCount = engine.bracketCount == nil ? 3
                        : engine.bracketCount == 3 ? 5 : nil
                }
                if longAvailable {
                    chip(engine.longMode.label, highlighted: engine.longMode != .off) {
                        engine.longMode = engine.longMode.next
                    }
                    if engine.longMode != .off {
                        chip(engine.longBlend.rawValue, highlighted: true) {
                            engine.longBlend = engine.longBlend == .nd ? .trails : .nd
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom))
    }

    private func chip(_ text: String, highlighted: Bool = false,
                      action: @escaping () -> Void) -> some View {
        let foreground: Color = highlighted ? Theme.accent : Color.white.opacity(0.92)
        let fill: Color = highlighted ? Theme.accent.opacity(0.14) : Color.white.opacity(0.08)
        let border: Color = highlighted ? Theme.accent.opacity(0.45) : Color.white.opacity(0.14)
        return Button {
            action()
            Haptics.light()
        } label: {
            Text(text)
                .font(Theme.valueFont(10))
                .tracking(0.5)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(foreground)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(border, lineWidth: 1))
                .rotatesWithDevice(rotation)
                .contentTransition(.numericText())
                .animation(Theme.motion(Theme.springStandard), value: text)
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
