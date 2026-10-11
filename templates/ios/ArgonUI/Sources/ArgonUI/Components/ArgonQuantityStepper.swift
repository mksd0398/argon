import SwiftUI

/// `value` moved `delta` steps (+1, -1) and kept on the quantity grid: `min`, `min + step`, `min + 2 * step`, ... up to
/// `max` (nil: no limit). A value off the grid lands on the grid point below where the move takes it.
public func steppedQuantity(_ value: Int, delta: Int, min: Int = 1, max: Int? = nil, step: Int = 1) -> Int {
    let step = Swift.max(1, step)
    // the highest grid point that `max` allows (never below `min`)
    let top = max.map { min + Swift.max(0, $0 - min) / step * step }
    var next = value + delta * step
    if next > min { next = min + (next - min) / step * step }
    next = Swift.max(min, next)
    if let top = top { next = Swift.min(top, next) }
    return next
}

/// A quantity with a minus and a plus: each tap moves it one `step` between `min` and `max` (`steppedQuantity`) and
/// reports it; a button that can't move it is off. The caller owns the value.
@MainActor
public struct ArgonQuantityStepper: View {
    let value: Int
    let onChange: (Int) -> Void
    let min: Int
    let max: Int?
    let step: Int
    let size: ArgonSize
    let isEnabled: Bool
    @Environment(\.argonTheme) private var theme

    public init(
        value: Int,
        onChange: @escaping (Int) -> Void,
        min: Int = 1,
        max: Int? = nil,
        step: Int = 1,
        size: ArgonSize = .m,
        isEnabled: Bool = true
    ) {
        self.value = value
        self.onChange = onChange
        self.min = min
        self.max = max
        self.step = step
        self.size = size
        self.isEnabled = isEnabled
    }

    public var body: some View {
        let side: CGFloat = size == .s ? 32 : size == .m ? 40 : 48
        HStack(spacing: 0) {
            button(.minus, "Decrease quantity", delta: -1, side: side)
            Text(verbatim: "\(value)")
                .font(theme.type.label)
                .monospacedDigit()
                .foregroundStyle(theme.colors.ink)
                .frame(minWidth: side * 0.8)
                .accessibilityLabel("Quantity \(value)")
            button(.plus, "Increase quantity", delta: 1, side: side)
        }
        .overlay { Capsule().strokeBorder(theme.colors.border, lineWidth: 1) }
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func button(_ icon: ArgonIconName, _ label: String, delta: Int, side: CGFloat) -> some View {
        let next = steppedQuantity(value, delta: delta, min: min, max: max, step: step)
        // at the end of the grid there is nowhere to go
        let isOn = next != value
        return Button {
            onChange(next)
        } label: {
            ArgonIcon(name: icon, size: side * 0.4, tint: theme.colors.ink)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(ArgonPressStyle())
        .disabled(!isEnabled || !isOn)
        .opacity(isOn ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}
