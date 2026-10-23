import ArgonUI
import XCTest
@testable import ArgonStorefront

final class ThemeTests: XCTestCase {
    func testLightBrandColoursTakeBlackLabelsAndDarkOnesWhite() {
        XCTAssertTrue(brandIsLight("#FFFFFF"))
        XCTAssertTrue(brandIsLight("#FFEB3B"), "yellow")
        XCTAssertFalse(brandIsLight("#000000"))
        XCTAssertTrue(brandIsLight("#1E88E5"), "mid blue: black contrasts more")
        XCTAssertTrue(brandIsLight("#808080"), "mid grey: black contrasts more")
        XCTAssertFalse(brandIsLight("#1A237E"), "navy")
    }

    func testNoReadableBrandColourKeepsWhiteLabels() {
        XCTAssertFalse(brandIsLight(nil))
        XCTAssertFalse(brandIsLight("not a colour"))
        XCTAssertFalse(brandIsLight("#FFF"))
    }

    /// The theme's vectors (contract/fixtures/theme/vectors.json), which contract/theme.js, Android and Krypton's
    /// previews are tested against too.
    func testColorsCornersAndButtonsAsTheContractMakesThem() throws {
        let vectors = try XCTUnwrap(JSONValue(json: contractFixture("theme/vectors.json"))?.array)
        for vector in vectors {
            let given = vector["appearance"]?.object ?? [:]
            let dark = vector["dark"]?.bool ?? false
            let want = try XCTUnwrap(vector["tokens"]?.object)
            var appearance: [String: JSONValue] = ["colors": .object(given.filter { ["background", "text"].contains($0.key) })]
            if let corners = given["corners"] { appearance["corners"] = corners }
            if let buttons = given["buttons"] { appearance["buttons"] = buttons }
            if let secondary = given["secondary"], case var .object(colors)? = appearance["colors"] {
                colors["secondary"] = secondary
                appearance["colors"] = .object(colors)
            }
            if let scale = given["scale"] { appearance["type"] = .object(["scale": scale]) }
            if let icons = given["icons"] { appearance["icons"] = icons }
            let look = try XCTUnwrap(ThemeLook.decode(.object(appearance))).argon(accent: given["accent"]?.string)
            let p = dark ? ArgonPalette.dark : ArgonPalette.themed(look)
            let accent = ArgonTheme.rgb(hex: look.accentHex) != nil ? look.accentHex!.uppercased() : p.ink
            let tokens = ["ink": p.ink, "muted": p.muted, "paper": p.paper, "surface": p.surface, "border": p.border,
                          "sale": p.sale, "success": p.success, "accent": accent, "onAccent": ArgonTheme.onAccentHex(accent),
                          "secondary": look.hex("secondary", dark: dark)!, "onSecondary": ArgonTheme.onAccentHex(look.hex("secondary", dark: dark)!)]
            for (name, value) in tokens { XCTAssertEqual(value, want[name]?.string, "\(given) dark=\(dark) \(name)") }
            let radius = ArgonRadius(corners: look.corners, buttons: look.buttons)
            XCTAssertEqual([radius.s, radius.m, radius.l], ["s", "m", "l"].map { CGFloat(want["radius"]?[$0]?.number ?? -1) }, "\(given)")
            XCTAssertEqual(radius.button, CGFloat(want["button"]?.number ?? -1), "\(given)")
            XCTAssertEqual(look.scale, want["scale"]?.number ?? -1, accuracy: 0.0001, "\(given)")
            XCTAssertEqual(look.icons.rawValue, want["icons"]?.string, "\(given)")
        }
    }

    func testAColourByNameFollowsTheThemeAndAHexStaysItself() {
        let look = ArgonLook(accentHex: "#8A3B12", backgroundHex: "#F7F3EE", textHex: "#2B2118", secondaryHex: "#2A9D8F")
        XCTAssertEqual(["accent", "secondary", "background", "text", "#abcdef", "nope"].map { look.hex($0, dark: false) },
                       ["#8A3B12", "#2A9D8F", "#F7F3EE", "#2B2118", "#ABCDEF", nil])
        XCTAssertEqual(look.hex("background", dark: true), ArgonPalette.dark.paper, "dark keeps Argon's palette")
        XCTAssertEqual(colorValue("accent"), "accent")
        XCTAssertNil(colorValue("Accent"))
    }

    func testNoAppearanceIsArgonsOwn() {
        XCTAssertEqual(ThemeLook.decode(.object([:])), ThemeLook())
        XCTAssertEqual(ArgonPalette.themed(ThemeLook().argon(accent: nil)).paper, ArgonPalette.light.paper)
    }
}
