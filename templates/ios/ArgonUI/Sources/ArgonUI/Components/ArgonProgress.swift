import SwiftUI

/// A progress bar: the native linear progress view for `value` (0...1); nil sweeps a segment along the track (iOS draws
/// no indeterminate bar), which holds still under Reduce Motion.
@MainActor
public struct ArgonProgressBar: View {
    let value: Double?
    @State private var sweeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.argonTheme) private var theme

    public init(value: Double?) {
        self.value = value
    }

    public var body: some View {
        if let value = value {
            ProgressView(value: min(max(value, 0), 1)).tint(theme.colors.accent)
        } else {
            GeometryReader { geometry in
                let segment = geometry.size.width * 0.3
                Capsule()
                    .fill(theme.colors.accent)
                    .frame(width: segment)
                    .offset(x: sweeping ? geometry.size.width : reduceMotion ? 0 : -segment)
            }
            .frame(height: 4)
            .background(theme.colors.border)
            .clipShape(Capsule())
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { sweeping = true }
            }
            .accessibilityElement()
            .accessibilityLabel("Loading")
        }
    }
}

/// A spinner: the native circular progress view at a small, medium or large size.
@MainActor
public struct ArgonSpinner: View {
    let size: ArgonSize
    @Environment(\.argonTheme) private var theme

    public init(size: ArgonSize = .m) {
        self.size = size
    }

    public var body: some View {
        ProgressView()
            .controlSize(size == .s ? .small : size == .m ? .regular : .large)
            .tint(theme.colors.accent)
    }
}
