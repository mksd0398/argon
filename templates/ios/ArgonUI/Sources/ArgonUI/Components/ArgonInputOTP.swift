import SwiftUI

/// The one-time-code rules, apart from the view so they can be tested.
public enum ArgonOTP {
    /// `text` cut to its ASCII digits, at most `length` of them.
    public static func sanitize(_ text: String, length: Int) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(max(length, 0)))
    }

    /// The field's text changed from `old` to `new`: the code to keep, and the code again when this change completed it
    /// (so `onComplete` fires once per completed code, not again while it stays complete).
    public static func update(old: String, new: String, length: Int) -> (code: String, completed: String?) {
        let before = sanitize(old, length: length), code = sanitize(new, length: length)
        return (code, code.count == length && code != before ? code : nil)
    }
}

/// A one-time code: a box per digit over one hidden native field, which takes typing, deleting, pasting and the
/// keyboard's code autofill.
@MainActor
public struct ArgonInputOTP: View {
    let length: Int
    @Binding var code: String
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool
    @Environment(\.argonTheme) private var theme

    public init(length: Int = 6, code: Binding<String>, onComplete: @escaping (String) -> Void) {
        self.length = length
        _code = code
        self.onComplete = onComplete
    }

    public var body: some View {
        let digits = Array(code)
        HStack(spacing: theme.spacing.s) {
            ForEach(0..<max(length, 0), id: \.self) { index in
                let current = focused && index == min(digits.count, length - 1)
                Text(index < digits.count ? String(digits[index]) : "")
                    .font(theme.type.headline)
                    .foregroundStyle(theme.colors.ink)
                    .frame(maxWidth: 48, minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .argonFieldBox(theme: theme, focused: current, isError: false)
                    .accessibilityHidden(true) // VoiceOver reads the field
            }
        }
        .background {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.01)
                .accessibilityLabel("Code")
                .accessibilityValue(code)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: code) { old, new in
            let result = ArgonOTP.update(old: old, new: new, length: length)
            // the field may hold letters or extra digits for a moment: the cleaned code replaces them
            if result.code != new { code = result.code }
            if let completed = result.completed { onComplete(completed) }
        }
    }
}
