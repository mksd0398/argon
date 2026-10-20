import ArgonUI
import CoreText
import UIKit
import XCTest

final class ArgonUITests: XCTestCase {
    // MARK: OTP

    /// Feeds the field's successive texts through the reducer the view uses; returns the final code and each completion.
    private func enter(_ texts: [String], from start: String = "", length: Int = 6) -> (code: String, completions: [String]) {
        var code = start
        var completions: [String] = []
        for text in texts {
            let result = ArgonOTP.update(old: code, new: text, length: length)
            code = result.code
            if let completed = result.completed { completions.append(completed) }
        }
        return (code, completions)
    }

    func testOtpTypingCompletesOnceAtTheLastDigit() {
        let typed = enter(["1", "12", "123", "1234", "12345", "123456", "1234567"])
        XCTAssertEqual(typed.code, "123456", "a seventh digit is ignored")
        XCTAssertEqual(typed.completions, ["123456"])
    }

    func testOtpDeletingThenRetypingCompletesAgain() {
        let typed = enter(["12345", "123459"], from: "123456")
        XCTAssertEqual(typed.code, "123459")
        XCTAssertEqual(typed.completions, ["123459"], "deleting doesn't complete; the new last digit does")
    }

    func testOtpPastingAFullCodeCompletesOnce() {
        XCTAssertEqual(enter(["482913"]).completions, ["482913"])
        XCTAssertEqual(enter(["Your code: 482-913"]).completions, ["482913"], "SMS text and separators are stripped")
    }

    func testOtpIgnoresNonDigits() {
        XCTAssertEqual(ArgonOTP.sanitize("1a2 b3-٤", length: 6), "123", "letters, spaces and non-ASCII digits go")
        XCTAssertEqual(enter(["1", "1x"]).code, "1")
        XCTAssertEqual(enter(["1", "1x"]).completions, [])
    }

    func testOtpCleanupPassDoesNotCompleteTwice() {
        // the view writes the cleaned code back, which reports one more change: raw text -> clean code
        let first = ArgonOTP.update(old: "12345", new: "123456x", length: 6)
        XCTAssertEqual(first.code, "123456")
        XCTAssertEqual(first.completed, "123456")
        XCTAssertNil(ArgonOTP.update(old: "123456x", new: "123456", length: 6).completed)
    }

    // MARK: Range slider

    func testRangeThumbsStayInsideBounds() {
        XCTAssertEqual(ArgonRange.moveLower(-10, upper: 50, bounds: 0...100, step: nil), 0)
        XCTAssertEqual(ArgonRange.moveUpper(130, lower: 20, bounds: 0...100, step: nil), 100)
    }

    func testRangeLowerNeverPassesUpper() {
        XCTAssertEqual(ArgonRange.moveLower(80, upper: 50, bounds: 0...100, step: nil), 50)
        XCTAssertEqual(ArgonRange.moveUpper(10, lower: 40, bounds: 0...100, step: nil), 40)
    }

    func testRangeSnapsToStep() {
        XCTAssertEqual(ArgonRange.moveUpper(47, lower: 0, bounds: 0...100, step: 10), 50)
        XCTAssertEqual(ArgonRange.moveLower(12, upper: 100, bounds: 0...100, step: 5), 10)
        XCTAssertEqual(ArgonRange.snap(13, bounds: 10...20, step: 4), 14, "steps count from the lower bound")
        XCTAssertEqual(ArgonRange.snap(20, bounds: 0...10, step: 4), 8, "a step past the upper bound falls back inside")
    }

    // MARK: Quantity stepper

    func testQuantityStepsOneAtATimeFromTheMinimum() {
        XCTAssertEqual(steppedQuantity(1, delta: 1), 2)
        XCTAssertEqual(steppedQuantity(5, delta: -1), 4)
        XCTAssertEqual(steppedQuantity(1, delta: -1), 1, "never under the minimum")
        XCTAssertEqual(steppedQuantity(1000, delta: 1), 1001, "no maximum: no upper end")
        XCTAssertEqual(steppedQuantity(9, delta: 1, min: 1, max: 10, step: 1), 10)
        XCTAssertEqual(steppedQuantity(10, delta: 1, min: 1, max: 10, step: 1), 10, "never over the maximum")
    }

    func testQuantityStaysOnTheStepGrid() {
        // sold in twos, 2 to 40
        XCTAssertEqual(steppedQuantity(2, delta: 1, min: 2, max: 40, step: 2), 4)
        XCTAssertEqual(steppedQuantity(4, delta: -1, min: 2, max: 40, step: 2), 2)
        XCTAssertEqual(steppedQuantity(2, delta: -1, min: 2, max: 40, step: 2), 2)
        XCTAssertEqual(steppedQuantity(40, delta: 1, min: 2, max: 40, step: 2), 40)
        XCTAssertEqual(steppedQuantity(3, delta: 1, min: 2, max: 40, step: 2), 4, "a value off the grid lands back on it")
        XCTAssertEqual(steppedQuantity(3, delta: -1, min: 2, max: 40, step: 2), 2)
        // a maximum between two grid points: the last point under it
        XCTAssertEqual(steppedQuantity(7, delta: 1, min: 1, max: 9, step: 3), 7, "1, 4, 7: 10 is over the maximum")
        XCTAssertEqual(steppedQuantity(4, delta: 1, min: 1, max: 9, step: 3), 7)
    }

    func testQuantityFromZeroForACartLine() {
        // a cart line's stepper starts at 0 (which removes the line)
        XCTAssertEqual(steppedQuantity(6, delta: -1, min: 0, max: nil, step: 6), 0)
        XCTAssertEqual(steppedQuantity(0, delta: 1, min: 0, max: nil, step: 6), 6)
        XCTAssertEqual(steppedQuantity(0, delta: -1, min: 0, max: nil, step: 6), 0)
        XCTAssertEqual(steppedQuantity(1, delta: -1, min: 0), 0)
    }

    func testQuantityToleratesARuleThatMakesNoSense() {
        // stores without quantity rules send an increment of 0
        XCTAssertEqual(steppedQuantity(1, delta: 1, min: 1, max: nil, step: 0), 2, "a step of 0 is a step of 1")
        XCTAssertEqual(steppedQuantity(2, delta: -1, step: -5), 1)
        XCTAssertEqual(steppedQuantity(5, delta: 1, min: 5, max: 3, step: 1), 5, "a maximum under the minimum: the minimum")
    }

    // MARK: Rating

    func testRatingFillsEachStarInTurn() {
        XCTAssertEqual((0..<5).map { ArgonRating.fill(star: $0, value: 5) }, [1, 1, 1, 1, 1])
        XCTAssertEqual((0..<5).map { ArgonRating.fill(star: $0, value: 0) }, [0, 0, 0, 0, 0])
        XCTAssertEqual((0..<5).map { ArgonRating.fill(star: $0, value: 3.5) }, [1, 1, 1, 0.5, 0])
        XCTAssertEqual(ArgonRating.fill(star: 4, value: 4.6), 0.6, accuracy: 0.0001)
        XCTAssertEqual(ArgonRating.fill(star: 4, value: 9), 1, "a value past 5 fills no more than 5 stars")
        XCTAssertEqual(ArgonRating.fill(star: 0, value: -1), 0)
    }

    func testRatingReadsOutItsValueAndCount() {
        XCTAssertEqual(ArgonRating.accessibilityText(value: 4.6, count: 128), "4.6 out of 5, 128 reviews")
        XCTAssertEqual(ArgonRating.accessibilityText(value: 5, count: 1), "5.0 out of 5, 1 review")
        XCTAssertEqual(ArgonRating.accessibilityText(value: 3.26, count: nil), "3.3 out of 5")
        XCTAssertEqual(ArgonRating.accessibilityText(value: 4, count: 0), "4.0 out of 5, 0 reviews")
    }

    // MARK: Badge

    func testBadgeText() {
        XCTAssertNil(ArgonBadge.text(nil), "nil is a dot")
        XCTAssertEqual(ArgonBadge.text(1), "1")
        XCTAssertEqual(ArgonBadge.text(99), "99")
        XCTAssertEqual(ArgonBadge.text(100), "99+")
    }

    // MARK: Top bar

    /// `colour`'s red, green and blue against those of `hex`.
    private func assertColour(_ colour: ArgonRGBA, is hex: String, _ message: String = "", line: UInt = #line) throws {
        let expected = try XCTUnwrap(ArgonTheme.rgb(hex: hex), line: line)
        XCTAssertEqual([colour.red, colour.green, colour.blue], [expected.red, expected.green, expected.blue], message, line: line)
    }

    func testOverThePictureTheOverlayBarIsClearWithLightContentOnADarkShade() throws {
        for dark in [false, true] {
            let bar = overlayBarColors(solid: 0, dark: dark)
            XCTAssertEqual(bar.container.opacity, 0, "no background")
            try assertColour(bar.content, is: ArgonPalette.dark.ink, "light content, whatever the appearance")
            XCTAssertEqual(bar.content.opacity, 1)
            try assertColour(bar.shade, is: ArgonPalette.dark.paper)
            XCTAssertEqual(bar.shade.opacity, overlayBarShade)
        }
    }

    func testSolidTheOverlayBarIsTheThemesBar() throws {
        for dark in [false, true] {
            let theme = dark ? ArgonPalette.dark : ArgonPalette.light
            let bar = overlayBarColors(solid: 1, dark: dark)
            try assertColour(bar.container, is: theme.paper)
            XCTAssertEqual(bar.container.opacity, 1)
            try assertColour(bar.content, is: theme.ink)
            XCTAssertEqual(bar.shade.opacity, 0, "no shade left")
        }
    }

    func testInBetweenTheOverlayBarFadesIn() throws {
        let bar = overlayBarColors(solid: 0.5, dark: false)
        XCTAssertEqual(bar.container.opacity, 0.5, accuracy: 0.01)
        XCTAssertEqual(bar.shade.opacity, overlayBarShade / 2, accuracy: 0.01)
        // the content is on its way from light to the theme's dark ink
        let light = try XCTUnwrap(ArgonTheme.rgb(hex: ArgonPalette.dark.ink))
        let ink = try XCTUnwrap(ArgonTheme.rgb(hex: ArgonPalette.light.ink))
        XCTAssertTrue(bar.content.red < light.red && bar.content.red > ink.red)
    }

    func testADarkTintIsDarkContentOnALightShadeAndSolidTakesTheAppsBarColours() throws {
        let clear = overlayBarColors(solid: 0, dark: true, darkContent: true)
        try assertColour(clear.content, is: ArgonPalette.light.ink, "dark content over a light picture")
        try assertColour(clear.shade, is: ArgonPalette.light.paper)
        let solid = overlayBarColors(solid: 1, dark: false, darkContent: true, bar: ArgonBarColors(background: "#1F6FEB", foreground: "#FFFFFF"))
        try assertColour(solid.container, is: "#1F6FEB")
        try assertColour(solid.content, is: "#FFFFFF")
    }

    func testOverlayBarSolidIsClampedToItsRange() {
        XCTAssertEqual(overlayBarColors(solid: -2, dark: false), overlayBarColors(solid: 0, dark: false))
        XCTAssertEqual(overlayBarColors(solid: 7, dark: false), overlayBarColors(solid: 1, dark: false))
    }

    // MARK: Theme

    func testAccentParsing() {
        XCTAssertEqual(ArgonTheme.rgb(hex: "#FF8000")?.red, 1)
        XCTAssertEqual(ArgonTheme.rgb(hex: "ff8000")?.green ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(ArgonTheme.rgb(hex: "#FFF"))
        XCTAssertNil(ArgonTheme.rgb(hex: "brand"))
        XCTAssertNil(ArgonTheme.color(hex: nil))
        XCTAssertNotNil(ArgonTheme.color(hex: "#B23A2E"))
    }

    func testOnAccentTakesTheHigherContrast() throws {
        XCTAssertEqual(ArgonTheme.onAccentHex("#FFEB3B"), "#000000", "yellow takes black")
        XCTAssertEqual(ArgonTheme.onAccentHex("#1E88E5"), "#000000", "mid blue takes black (5.7:1 vs 3.7:1)")
        XCTAssertEqual(ArgonTheme.onAccentHex("#808080"), "#000000", "mid grey takes black")
        XCTAssertEqual(ArgonTheme.onAccentHex("#1A237E"), "#FFFFFF", "navy takes white")
        XCTAssertFalse(ArgonTheme.isLight(hex: "not a colour"))
        for rgb in stride(from: 0, through: 0xFFFFFF, by: 0x0F0F0F + 0x2) {
            let hex = String(format: "#%06X", rgb)
            let ratio = try XCTUnwrap(ArgonTheme.contrastRatio(hex, ArgonTheme.onAccentHex(hex)))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, hex)
        }
    }

    func testTextColoursMeetAA() throws {
        for palette in [ArgonPalette.light, ArgonPalette.dark] {
            for text in [palette.ink, palette.muted, palette.sale, palette.success] {
                for background in [palette.paper, palette.surface] {
                    let ratio = try XCTUnwrap(ArgonTheme.contrastRatio(text, background))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(text) on \(background)")
                }
            }
            let onSale = try XCTUnwrap(ArgonTheme.contrastRatio(palette.paper, palette.sale))
            XCTAssertGreaterThanOrEqual(onSale, 4.5, "paper on sale (badges, destructive buttons)")
            // without a brand colour the accent is ink
            let onAccent = try XCTUnwrap(ArgonTheme.contrastRatio(palette.ink, ArgonTheme.onAccentHex(palette.ink)))
            XCTAssertGreaterThanOrEqual(onAccent, 4.5, "onAccent on the default accent")
        }
    }

    func testBundledFontsRegister() throws {
        XCTAssertTrue(ArgonFonts.register())
        XCTAssertTrue(ArgonFonts.register(), "a second call is harmless")
        let display = try XCTUnwrap(ArgonFonts.display(size: 20))
        XCTAssertEqual(CTFontCopyPostScriptName(display) as String, "InstrumentSerif-Regular")
        let semibold = try XCTUnwrap(ArgonFonts.text(size: 16, weight: 600))
        XCTAssertEqual(CTFontCopyFamilyName(semibold) as String, "Hanken Grotesk")
        let variation = CTFontCopyVariation(semibold) as? [NSNumber: NSNumber] ?? [:]
        XCTAssertEqual(variation.first { $0.key.intValue == 0x7767_6874 }?.value.intValue, 600, "the wght axis is set")
    }

    func testRegisteredFontsReplaceTheBundledOnes() throws {
        XCTAssertTrue(ArgonFonts.register())
        defer { ArgonFonts.use(heading: nil, body: nil) }
        // any registered names do: the bundled ones stand in for a merchant's
        ArgonFonts.use(heading: [700: "HankenGrotesk-Regular"], body: [400: "InstrumentSerif-Regular", 700: "HankenGrotesk-Regular"])
        let name = { (font: CTFont?) in font.map { CTFontCopyPostScriptName($0) as String } }
        XCTAssertEqual(name(ArgonFonts.display(size: 20)), "HankenGrotesk-Regular", "the only heading weight")
        XCTAssertEqual(name(ArgonFonts.text(size: 16, weight: 500)), "InstrumentSerif-Regular", "nearest 500 is 400")
        XCTAssertEqual(name(ArgonFonts.text(size: 16, weight: 600)), "HankenGrotesk-Regular", "nearest 600 is 700")
        ArgonFonts.use(heading: nil, body: [:])
        XCTAssertEqual(name(ArgonFonts.display(size: 20)), "InstrumentSerif-Regular", "nothing set: the bundled font")
        XCTAssertEqual(ArgonFonts.text(size: 16, weight: 600).map { CTFontCopyFamilyName($0) as String }, "Hanken Grotesk")
    }

    // MARK: Icons

    func testEveryIconMapsToAnSFSymbol() {
        XCTAssertEqual(ArgonIconName.allCases.count, 42)
        for icon in ArgonIconName.allCases {
            XCTAssertFalse(icon.systemName.isEmpty, icon.rawValue)
            XCTAssertNotNil(UIImage(systemName: icon.systemName), "\(icon.rawValue) -> \(icon.systemName)")
        }
    }
}
