import SwiftUI
import UIKit

public enum ArgonKeyboard: Sendable {
    case text, email, number, phone
}

/// A single-line field: the native text (or secure) field with a label above and the helper, or the error, below.
@MainActor
public struct ArgonInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String?
    let helper: String?
    let error: String?
    let keyboard: ArgonKeyboard
    let isSecure: Bool
    let leadingIcon: ArgonIconName?
    let trailingIcon: ArgonIconName?
    @FocusState private var focused: Bool
    @Environment(\.argonTheme) private var theme

    public init(
        label: String,
        text: Binding<String>,
        placeholder: String? = nil,
        helper: String? = nil,
        error: String? = nil,
        keyboard: ArgonKeyboard = .text,
        isSecure: Bool = false,
        leadingIcon: ArgonIconName? = nil,
        trailingIcon: ArgonIconName? = nil
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.helper = helper
        self.error = error
        self.keyboard = keyboard
        self.isSecure = isSecure
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            // the field itself carries the label for VoiceOver
            Text(label).font(theme.type.label).foregroundStyle(theme.colors.ink).accessibilityHidden(true)
            HStack(spacing: theme.spacing.s) {
                if let leadingIcon = leadingIcon { ArgonIcon(name: leadingIcon, size: 18, tint: theme.colors.muted) }
                field
                    .font(theme.type.body)
                    .foregroundStyle(theme.colors.ink)
                    .keyboardType(keyboardType)
                    .textContentType(contentType)
                    .textInputAutocapitalization(keyboard == .text ? TextInputAutocapitalization.sentences : .never)
                    .autocorrectionDisabled(keyboard != .text || isSecure)
                    .focused($focused)
                if let trailingIcon = trailingIcon { ArgonIcon(name: trailingIcon, size: 18, tint: theme.colors.muted) }
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(minHeight: 48)
            .argonFieldBox(theme: theme, focused: focused, isError: error != nil)
            ArgonFieldMessage(helper: helper, error: error)
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = placeholder.map { Text($0) }
        if isSecure {
            SecureField(label, text: $text, prompt: prompt)
        } else {
            TextField(label, text: $text, prompt: prompt)
        }
    }

    private var keyboardType: UIKeyboardType {
        switch keyboard {
        case .text: return .default
        case .email: return .emailAddress
        case .number: return .numberPad
        case .phone: return .phonePad
        }
    }

    private var contentType: UITextContentType? {
        switch keyboard {
        case .email: return .emailAddress
        case .phone: return .telephoneNumber
        case .text, .number: return nil
        }
    }
}

/// A multi-line field that grows from `minLines`; with `maxLength` it stops there and counts the characters.
@MainActor
public struct ArgonTextArea: View {
    let label: String
    @Binding var text: String
    let placeholder: String?
    let minLines: Int
    let maxLength: Int?
    let helper: String?
    let error: String?
    @FocusState private var focused: Bool
    @Environment(\.argonTheme) private var theme

    public init(
        label: String,
        text: Binding<String>,
        placeholder: String? = nil,
        minLines: Int = 3,
        maxLength: Int? = nil,
        helper: String? = nil,
        error: String? = nil
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.minLines = minLines
        self.maxLength = maxLength
        self.helper = helper
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(label).font(theme.type.label).foregroundStyle(theme.colors.ink).accessibilityHidden(true)
            TextField(label, text: $text, prompt: placeholder.map { Text($0) }, axis: .vertical)
                .lineLimit(max(minLines, 1)...)
                .font(theme.type.body)
                .foregroundStyle(theme.colors.ink)
                .focused($focused)
                .padding(theme.spacing.m)
                .argonFieldBox(theme: theme, focused: focused, isError: error != nil)
                .onChange(of: text) { _, new in
                    if let maxLength = maxLength, new.count > maxLength { text = String(new.prefix(maxLength)) }
                }
            HStack(alignment: .top) {
                ArgonFieldMessage(helper: helper, error: error)
                Spacer(minLength: theme.spacing.s)
                if let maxLength = maxLength {
                    Text(verbatim: "\(text.count)/\(maxLength)").font(theme.type.caption).foregroundStyle(theme.colors.muted)
                }
            }
        }
    }
}

/// The helper text, or the error in the sale colour.
@MainActor
struct ArgonFieldMessage: View {
    let helper: String?
    let error: String?
    @Environment(\.argonTheme) var theme

    var body: some View {
        if let message = error ?? helper {
            Text(message).font(theme.type.caption).foregroundStyle(error != nil ? theme.colors.sale : theme.colors.muted)
        }
    }
}

extension View {
    /// The field's box: surface fill, a border that darkens with focus and turns sale-red on error.
    func argonFieldBox(theme: ArgonTheme, focused: Bool, isError: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.m)
        let border = isError ? theme.colors.sale : focused ? theme.colors.ink : theme.colors.border
        return background(theme.colors.surface, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: focused || isError ? 1.5 : 1) }
    }
}
