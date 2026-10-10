import SwiftUI

/// The dates from `lower` to `upper` (open ends unbounded); an `upper` before `lower` collapses to `lower` rather than
/// crash the picker.
func argonDateRange(_ lower: Date?, _ upper: Date?) -> ClosedRange<Date> {
    let from = lower ?? .distantPast
    return from...max(from, upper ?? .distantFuture)
}

/// A date: the native compact date picker, limited to `minDate`...`maxDate`.
@MainActor
public struct ArgonDatePicker: View {
    let label: String
    @Binding var selection: Date
    let minDate: Date?
    let maxDate: Date?
    @Environment(\.argonTheme) private var theme

    public init(label: String = "Date", selection: Binding<Date>, minDate: Date? = nil, maxDate: Date? = nil) {
        self.label = label
        _selection = selection
        self.minDate = minDate
        self.maxDate = maxDate
    }

    public var body: some View {
        DatePicker(label, selection: $selection, in: argonDateRange(minDate, maxDate), displayedComponents: .date)
            .font(theme.type.body)
            .foregroundStyle(theme.colors.ink)
            .tint(theme.colors.accent)
    }
}

/// A date range (iOS has no range picker): two linked native pickers, the start never after the end.
@MainActor
public struct ArgonDateRangePicker: View {
    @Binding var start: Date
    @Binding var end: Date
    let minDate: Date?
    let maxDate: Date?
    let startLabel: String
    let endLabel: String
    @Environment(\.argonTheme) private var theme

    public init(
        start: Binding<Date>,
        end: Binding<Date>,
        minDate: Date? = nil,
        maxDate: Date? = nil,
        startLabel: String = "From",
        endLabel: String = "To"
    ) {
        _start = start
        _end = end
        self.minDate = minDate
        self.maxDate = maxDate
        self.startLabel = startLabel
        self.endLabel = endLabel
    }

    public var body: some View {
        VStack(spacing: theme.spacing.s) {
            DatePicker(startLabel, selection: $start, in: argonDateRange(minDate, end), displayedComponents: .date)
            DatePicker(endLabel, selection: $end, in: argonDateRange(start, maxDate), displayedComponents: .date)
        }
        .font(theme.type.body)
        .foregroundStyle(theme.colors.ink)
        .tint(theme.colors.accent)
    }
}
