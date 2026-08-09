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
    var recipes: [Recipe] = []
    var onApplyRecipe: (Recipe) -> Void = { _ in }
    var onSaveRecipe: () -> Void = {}
    var onDeleteRecipe: (Recipe) -> Void = { _ in }

    @State private var batteryLevel: Float = -1

    var body: some View {
        VStack(spacing: 8) {
            statusline
            rail
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.accent.opacity(0.18))
                .frame(height: 1)
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            batteryLevel = UIDevice.current.batteryLevel
        }
    }

    // MARK: - Statusline

    private var statusline: some View {
        let pipelineText = RailLabels.pipeline(raw: engine.formatSelection.raw,
                                                heifCompanion: engine.formatSelection.heifCompanion,
                                                processing: engine.processingLevel)
        let pipelineColor: Color = engine.formatSelection.raw != .off
            ? Theme.accent : Color.white.opacity(0.42)
        return HStack(spacing: 8) {
            Text(pipelineText)
                .foregroundStyle(pipelineColor)
            Spacer()
            if batteryLevel >= 0 {
                Text("BAT \(Int(batteryLevel * 100))")
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            recipeMenu
            assistMenu
        }
        .font(Theme.valueFont(8.5))
        .tracking(1.2)
    }

    private var recipeMenu: some View {
        let recipeColor: Color = !recipes.isEmpty ? Theme.accent : Color.white.opacity(0.42)
        return Menu {
            ForEach(recipes) { recipe in
                Button(recipe.name) { onApplyRecipe(recipe) }
            }
            Divider()
            Button("Save current…") { onSaveRecipe() }
            if !recipes.isEmpty {
                Menu("Delete") {
                    ForEach(recipes) { recipe in
                        Button(recipe.name, role: .destructive) { onDeleteRecipe(recipe) }
                    }
                }
            }
        } label: {
            Text("RCP")
                .foregroundStyle(recipeColor)
        }
    }

    // MARK: - Rail

    private var rail: some View {
        HStack(spacing: 1) {
            railCell(label: "FMT", value: engine.formatSelection.raw.rawValue,
                     active: engine.formatSelection.raw != .off, action: cycleFormat)
            railCell(label: "PROC", value: engine.processingLevel.rawValue,
                     active: engine.processingLevel != .standard) {
                engine.processingLevel = engine.processingLevel.next
            }
            railCell(label: "FLASH", value: engine.flashOn ? "ON" : "—",
                     active: engine.flashOn) {
                engine.flashOn.toggle()
            }
            railCell(label: "TIMER", value: RailLabels.timer(timerDuration),
                     active: timerDuration > 0) {
                timerDuration = timerDuration == 0 ? 3 : timerDuration == 3 ? 10 : 0
            }
            railCell(label: "BKT", value: RailLabels.bracket(engine.bracketCount),
                     active: engine.bracketCount != nil) {
                engine.bracketCount = engine.bracketCount == nil ? 3
                    : engine.bracketCount == 3 ? 5 : nil
            }
            if longAvailable {
                railCell(label: "LONG", value: RailLabels.long(engine.longMode),
                         active: engine.longMode != .off) {
                    engine.longMode = engine.longMode.next
                }
                if engine.longMode != .off {
                    railCell(label: "BLEND", value: engine.longBlend.rawValue, active: true) {
                        engine.longBlend = engine.longBlend == .nd ? .trails : .nd
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func railCell(label: String, value: String, active: Bool,
                           action: @escaping () -> Void) -> some View {
        let valueColor: Color = active ? Theme.accent : Color.white.opacity(0.8)
        let fill: Color = active ? Theme.accent.opacity(0.10) : Color.white.opacity(0.05)
        let content = VStack(spacing: 2) {
            Text(label)
                .font(Theme.valueFont(7))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.38))
            Text(value)
                .font(Theme.valueFont(10))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .animation(Theme.motion(Theme.springStandard), value: value)
        }
        .rotatesWithDevice(rotation)
        return Button {
            action()
            Haptics.light()
        } label: {
            content
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(fill)
                .overlay(alignment: .bottom) {
                    if active {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(height: 2)
                            .padding(.horizontal, 12)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Assist menu

    private var assistMenu: some View {
        Menu {
            Picker("Aspect", selection: $aspect) {
                ForEach(AspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            Toggle("Histogram", isOn: overlayBinding(\.histogramEnabled))
            Toggle("Waveform", isOn: overlayBinding(\.waveformEnabled))
            Toggle("Focus Peaking", isOn: overlayBinding(\.peakingEnabled))
            Toggle("Zebra", isOn: overlayBinding(\.zebraEnabled))
            Toggle("Grid", isOn: $showGrid)
            Toggle("Level", isOn: $showLevel)
            Toggle("HEIF companion", isOn: Binding(
                get: { engine.formatSelection.heifCompanion },
                set: { engine.formatSelection.heifCompanion = $0 }))
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14))
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
