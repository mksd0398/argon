import CoreText
import Foundation

/// The bundled OFL fonts: Instrument Serif (display) and Hanken Grotesk (text, a variable font on the `wght` axis).
public enum ArgonFonts {
    static let displayName = "InstrumentSerif-Regular"
    static let textName = "HankenGrotesk-Regular"
    private static let files = ["InstrumentSerif-Regular", "HankenGrotesk-Variable"]
    private static let weightAxis = 0x7767_6874 // 'wght'

    /// Registers the fonts for this process (once, however often it's called). False when either isn't available:
    /// text then uses the system font.
    @discardableResult
    public static func register() -> Bool { registered }

    private static let registered: Bool = {
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            // fails as "already registered" when another copy of the library got there first; the check below decides
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { _ = error?.takeRetainedValue() }
        }
        return isAvailable(displayName) && isAvailable(textName)
    }()

    // CoreText substitutes a fallback for an unknown name, so the name it hands back tells whether the font is there.
    private static func isAvailable(_ name: String) -> Bool {
        CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name
    }

    /// Instrument Serif at `size` points; nil when it isn't available.
    public static func display(size: CGFloat) -> CTFont? {
        register() ? CTFontCreateWithName(displayName as CFString, size, nil) : nil
    }

    /// Hanken Grotesk at `size` points and `weight` (CSS scale, 100...900); nil when it isn't available.
    public static func text(size: CGFloat, weight: Int) -> CTFont? {
        guard register() else { return nil }
        let attributes = [
            kCTFontNameAttribute as String: textName,
            kCTFontVariationAttribute as String: [weightAxis: weight],
        ] as [String: Any]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
}
