import SwiftUI

/// A rating out of five: five stars, the last one filled partly (4.6 fills 60% of the fifth), then the number of
/// reviews as "(128)". VoiceOver reads "4.6 out of 5, 128 reviews".
@MainActor
public struct ArgonRating: View {
    let value: Double
    let count: Int?
    let size: ArgonSize
    @Environment(\.argonTheme) private var theme

    public init(value: Double, count: Int? = nil, size: ArgonSize = .s) {
        self.value = value
        self.count = count
        self.size = size
    }

    /// How much of star `index` (0...4) is filled for `value`, 0...1.
    public nonisolated static func fill(star index: Int, value: Double) -> Double {
        min(max(value - Double(index), 0), 1)
    }

    /// "4.6 out of 5, 128 reviews"; without a count, "4.6 out of 5".
    public nonisolated static func accessibilityText(value: Double, count: Int?) -> String {
        let rating = String(format: "%.1f out of 5", locale: Locale(identifier: "en_US_POSIX"), min(max(value, 0), 5))
        guard let count = count else { return rating }
        return "\(rating), \(count) \(count == 1 ? "review" : "reviews")"
    }

    public var body: some View {
        let star: CGFloat = size == .s ? 12 : size == .m ? 16 : 22
        HStack(spacing: theme.spacing.xs) {
            HStack(spacing: star / 8) {
                ForEach(0..<5, id: \.self) { index in
                    let filled = Self.fill(star: index, value: value)
                    Image(systemName: "star.fill")
                        .font(.system(size: star))
                        .foregroundStyle(theme.colors.border)
                        .overlay {
                            Image(systemName: "star.fill")
                                .font(.system(size: star))
                                .foregroundStyle(theme.colors.ink)
                                .mask(alignment: .leading) {
                                    GeometryReader { geometry in
                                        Rectangle().frame(width: geometry.size.width * filled)
                                    }
                                }
                        }
                }
            }
            if let count = count {
                Text(verbatim: "(\(count))")
                    .font(size == .l ? theme.type.label : theme.type.caption)
                    .foregroundStyle(theme.colors.muted)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityText(value: value, count: count))
    }
}
