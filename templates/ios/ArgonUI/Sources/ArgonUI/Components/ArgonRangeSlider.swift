import SwiftUI

/// The range slider's rules, apart from the view so they can be tested.
public enum ArgonRange {
    /// `value` inside `bounds`, snapped to the nearest `step` counted from the lower bound (never past the upper one).
    public static func snap(_ value: Double, bounds: ClosedRange<Double>, step: Double?) -> Double {
        var result = min(max(value, bounds.lowerBound), bounds.upperBound)
        if let step = step, step > 0 {
            result = bounds.lowerBound + ((result - bounds.lowerBound) / step).rounded() * step
            if result > bounds.upperBound { result -= step }
        }
        return result
    }

    /// The lower thumb dragged to `value`: snapped into bounds, and stopped at `upper`.
    public static func moveLower(_ value: Double, upper: Double, bounds: ClosedRange<Double>, step: Double?) -> Double {
        min(snap(value, bounds: bounds, step: step), snap(upper, bounds: bounds, step: step))
    }

    /// The upper thumb dragged to `value`: snapped into bounds, and stopped at `lower`.
    public static func moveUpper(_ value: Double, lower: Double, bounds: ClosedRange<Double>, step: Double?) -> Double {
        max(snap(value, bounds: bounds, step: step), snap(lower, bounds: bounds, step: step))
    }
}

/// Two thumbs on one track, for a range such as a price filter (iOS's slider holds one value). A drag moves the
/// nearer thumb; when they meet, the drag's direction picks one. VoiceOver adjusts each thumb by `step`.
@MainActor
public struct ArgonRangeSlider: View {
    let lower: Double
    let upper: Double
    let bounds: ClosedRange<Double>
    let step: Double?
    let onChange: (Double, Double) -> Void
    @State private var dragging: Thumb? = nil
    @Environment(\.argonTheme) private var theme

    private enum Thumb { case lower, upper }
    private let thumb: CGFloat = 28

    public init(lower: Double, upper: Double, bounds: ClosedRange<Double>, step: Double? = nil, onChange: @escaping (Double, Double) -> Void) {
        self.lower = lower
        self.upper = upper
        self.bounds = bounds
        self.step = step
        self.onChange = onChange
    }

    public var body: some View {
        GeometryReader { geometry in
            let track = max(geometry.size.width - thumb, 1)
            let lowerX = x(lower, track), upperX = x(upper, track)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.border).frame(height: 4)
                Capsule().fill(theme.colors.accent).frame(width: max(upperX - lowerX, 0), height: 4).offset(x: lowerX)
                knob.offset(x: lowerX - thumb / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Minimum")
                    .accessibilityValue(Text(verbatim: format(lower)))
                    .accessibilityAdjustableAction { direction in
                        onChange(ArgonRange.moveLower(lower + delta(direction), upper: upper, bounds: bounds, step: step), upper)
                    }
                knob.offset(x: upperX - thumb / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Maximum")
                    .accessibilityValue(Text(verbatim: format(upper)))
                    .accessibilityAdjustableAction { direction in
                        onChange(lower, ArgonRange.moveUpper(upper + delta(direction), lower: lower, bounds: bounds, step: step))
                    }
            }
            .padding(.horizontal, thumb / 2)
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let value = self.value(drag.location.x - thumb / 2, track)
                        if dragging == nil {
                            let toLower = abs(drag.startLocation.x - thumb / 2 - lowerX)
                            let toUpper = abs(drag.startLocation.x - thumb / 2 - upperX)
                            let picked: Thumb = toLower < toUpper ? .lower : toUpper < toLower ? .upper
                                : drag.translation.width < 0 ? .lower : .upper
                            dragging = picked
                        }
                        if dragging == .lower {
                            onChange(ArgonRange.moveLower(value, upper: upper, bounds: bounds, step: step), upper)
                        } else {
                            onChange(lower, ArgonRange.moveUpper(value, lower: lower, bounds: bounds, step: step))
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .frame(height: 44)
    }

    private var knob: some View {
        Circle()
            .fill(theme.colors.surface)
            .overlay { Circle().strokeBorder(theme.colors.accent, lineWidth: 2) }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(width: thumb, height: thumb)
    }

    private var span: Double { bounds.upperBound - bounds.lowerBound }

    /// The x of `value` along a track `width` wide.
    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        span > 0 ? CGFloat((min(max(value, bounds.lowerBound), bounds.upperBound) - bounds.lowerBound) / span) * width : 0
    }

    /// The value at `x` along a track `width` wide.
    private func value(_ x: CGFloat, _ width: CGFloat) -> Double {
        bounds.lowerBound + Double(min(max(x / width, 0), 1)) * span
    }

    private func delta(_ direction: AccessibilityAdjustmentDirection) -> Double {
        let amount = step ?? span / 20
        switch direction {
        case .increment: return amount
        case .decrement: return -amount
        @unknown default: return 0
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
