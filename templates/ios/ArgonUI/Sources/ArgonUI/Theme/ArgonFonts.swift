import CoreText
import Foundation

/// The bundled OFL fonts: Instrument Serif (display) and Hanken Grotesk (text, a variable font on the `wght` axis).
/// `use(heading:body:)` swaps in fonts the app registered (the merchant's) for either role.
public enum ArgonFonts {
    static let displayName = "InstrumentSerif-Regular"
    static let textName = "HankenGrotesk-Regular"
    private static let files = ["InstrumentSerif-Regular", "HankenGrotesk-Variable"]
    private static let weightAxis = 0x7767_6874 // 'wght'
    // the merchant's fonts (`use`): CSS weight -> PostScript name of a font registered for this process
    nonisolated(unsafe) private static var heading: [Int: String]?
    nonisolated(unsafe) private static var body: [Int: String]?

    /// Uses registered fonts in place of the bundled ones: `heading` for `display`, `body` for `text`, each a CSS weight
    /// -> PostScript name; nil or empty keeps that role's bundled font. Call it before the first view is drawn: the
    /// theme resolves its fonts when it is built.
    public static func use(heading: [Int: String]?, body: [Int: String]?) {
        self.heading = heading?.isEmpty == false ? heading : nil
        self.body = body?.isEmpty == false ? body : nil
    }

    /// The name in `names` whose weight is nearest `weight` (the lighter one on a tie).
    static func nearest(_ names: [Int: String], to weight: Int) -> String? {
        names.min { (abs($0.key - weight), $0.key) < (abs($1.key - weight), $1.key) }?.value
    }

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

    /// Instrument Serif (or the merchant's heading font, its weight nearest 400) at `size` points; nil when it isn't
    /// available.
    public static func display(size: CGFloat) -> CTFont? {
        if let name = heading.flatMap({ nearest($0, to: 400) }) { return CTFontCreateWithName(name as CFString, size, nil) }
        return register() ? CTFontCreateWithName(displayName as CFString, size, nil) : nil
    }

    /// Hanken Grotesk (or the merchant's body font, its nearest weight) at `size` points and `weight` (CSS scale,
    /// 100...900); nil when it isn't available.
    public static func text(size: CGFloat, weight: Int) -> CTFont? {
        if let name = body.flatMap({ nearest($0, to: weight) }) { return CTFontCreateWithName(name as CFString, size, nil) }
        guard register() else { return nil }
        let attributes = [
            kCTFontNameAttribute as String: textName,
            kCTFontVariationAttribute as String: [weightAxis: weight],
        ] as [String: Any]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
}
