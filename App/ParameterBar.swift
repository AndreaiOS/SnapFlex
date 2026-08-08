import SwiftUI
import SnapFlexCore

enum SelectedParameter: CaseIterable {
    case iso, shutter, ev, focus, wb

    var label: String {
        switch self {
        case .iso: "ISO"
        case .shutter: "SHUTTER"
        case .ev: "EV"
        case .focus: "FOCUS"
        case .wb: "WB"
        }
    }
}

struct ParameterBar: View {
    let engine: CameraEngine
    @Binding var selected: SelectedParameter?
    var rotation: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SelectedParameter.allCases, id: \.self) { parameter in
                tile(parameter)
            }
        }
        .padding(.horizontal, 8)
    }

    private func tile(_ parameter: SelectedParameter) -> some View {
        let isSelected = selected == parameter
        let (value, isManual) = displayValue(parameter)
        return Button {
            if isSelected {
                revertToAuto(parameter)
                selected = nil
            } else {
                selected = parameter
            }
        } label: {
            VStack(spacing: 2) {
                Text(parameter.label)
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.inactiveText)
                Text(value)
                    .font(Theme.valueFont(13))
                    .foregroundStyle(isManual || isSelected ? Theme.accent : Theme.inactiveText)
            }
            .rotatesWithDevice(rotation)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isSelected ? Theme.accent.opacity(0.15) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func displayValue(_ parameter: SelectedParameter) -> (String, Bool) {
        let values = engine.values
        switch parameter {
        case .iso:
            return values.iso.map { (String(Int($0)), true) } ?? ("AUTO", false)
        case .shutter:
            return values.shutterSeconds.map { (Format.shutter($0), true) } ?? ("AUTO", false)
        case .ev:
            return (String(format: "%+.1f", values.evBias), values.evBias != 0)
        case .focus:
            return values.focusPosition.map { (String(format: "%.2f", $0), true) } ?? ("AF", false)
        case .wb:
            return values.wbKelvin.map { ("\($0)K", true) } ?? ("AWB", false)
        }
    }

    private func revertToAuto(_ parameter: SelectedParameter) {
        switch parameter {
        case .iso: engine.setISO(nil)
        case .shutter: engine.setShutter(nil)
        case .ev: engine.setEVBias(0)
        case .focus: engine.setFocus(nil)
        case .wb: engine.setWhiteBalance(kelvin: nil)
        }
    }
}

enum Format {
    static func shutter(_ seconds: Double) -> String {
        seconds >= 0.35 ? String(format: "%.1fs", seconds) : "1/\(Int((1.0 / seconds).rounded()))"
    }
}
