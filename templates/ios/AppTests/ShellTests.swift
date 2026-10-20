import SwiftUI
import XCTest
@testable import ArgonStorefront

/// The app shell from the merchant's settings (Shell.swift): each part decoded leniently, the built-in behaviour for
/// anything missing or invalid.
final class ShellTests: XCTestCase {
    private func navigation(_ json: String) -> Navigation? { Navigation.decode(JSONValue(json: json)) }

    private func tabs(_ json: String) -> [ShellTab]? { Navigation.tabs(JSONValue(json: json)) }

    func testTheSpecsExampleDecodes() throws {
        let settings = try XCTUnwrap(RemoteSettings(json: Data("""
        {
          "navigation": {
            "tabs": [{ "id": "home", "title": "Home", "icon": "home" }, { "id": "shop" }, { "id": "search" }, { "id": "wishlist" }, { "id": "account" }],
            "labels": false,
            "topBar": { "style": "centered_logo", "transparentOnHome": true },
            "drawer": { "enabled": true, "menu": "footer" }
          },
          "announcement": {
            "enabled": true, "messages": [{ "text": "Free shipping over $75", "link": "/collections/all" }],
            "background": "#111111", "color": "#ffffff", "interval": 7, "dismissible": false
          },
          "appearance": { "mode": "dark" }
        }
        """.utf8)))
        let navigation = try XCTUnwrap(settings.navigation)
        XCTAssertEqual(navigation.tabs.map { $0.id }, ["home", "shop", "search", "wishlist", "account"])
        XCTAssertEqual(navigation.tabs.map { $0.title }, ["Home", "Shop", "Search", "Wishlist", "Account"])
        XCTAssertEqual(navigation.tabs.map { $0.icon }, ["home", "grid", "search", "heart", "person"])
        XCTAssertFalse(navigation.labels)
        XCTAssertEqual(navigation.topBarStyle, "centered_logo")
        XCTAssertTrue(navigation.transparentOnHome)
        XCTAssertEqual(navigation.drawerMenu, "footer")
        XCTAssertFalse(navigation.hasTab("cart"))
        XCTAssertEqual(settings.announcement, Announcement(
            messages: [AnnouncementMessage(text: "Free shipping over $75", link: "/collections/all")],
            background: "#111111", color: "#FFFFFF", interval: 7, dismissible: false
        ))
        XCTAssertEqual(settings.appearance, .dark)
    }

    func testEmptySettingsChangeNothing() throws {
        let settings = try XCTUnwrap(RemoteSettings(json: Data("{}".utf8)))
        XCTAssertNil(settings.navigation)
        XCTAssertNil(settings.announcement)
        XCTAssertNil(settings.appearance)
        let builtIn = Navigation()
        XCTAssertEqual(builtIn.tabs.map { $0.id }, ["home", "shop", "wishlist", "cart", "account"])
        XCTAssertEqual(builtIn.tabs.map { $0.icon }, ["home", "grid", "heart", "bag", "person"])
        XCTAssertTrue(builtIn.labels)
        XCTAssertNil(builtIn.topBarStyle)
        XCTAssertFalse(builtIn.transparentOnHome)
        XCTAssertNil(builtIn.drawerMenu)
        // parts of the wrong type are left out, the rest still read
        let json = ##"{"navigation": [], "announcement": "x", "appearance": {"mode": "sepia"}, "brand": {"accent": "#1F6FEB"}}"##
        let wrong = try XCTUnwrap(RemoteSettings(json: Data(json.utf8)))
        XCTAssertNil(wrong.navigation)
        XCTAssertNil(wrong.announcement)
        XCTAssertNil(wrong.appearance)
        XCTAssertEqual(wrong.accent, "#1F6FEB")
    }

    func testAnInvalidTabListIsTheBuiltInFive() {
        XCTAssertNil(tabs(#"[{"id": "home"}]"#), "one tab")
        XCTAssertNil(tabs(#"[{"id": "home"}, {"id": "shop"}, {"id": "cart"}, {"id": "account"}, {"id": "wishlist"}, {"id": "search"}]"#), "six")
        XCTAssertNil(tabs(#"[{"id": "shop"}, {"id": "home"}]"#), "home not first")
        XCTAssertNil(tabs(#"[{"id": "home"}, {"id": "shop"}, {"id": "shop"}]"#), "a repeat")
        XCTAssertNil(tabs(#"[{"id": "home"}, {"id": "blog"}]"#), "an unknown id")
        XCTAssertNil(tabs(#"[{"id": "home"}, {"id": "screen:About Us"}]"#), "not a handle")
        XCTAssertNil(tabs(#"[{"id": "home"}, "shop"]"#), "not an object")
        XCTAssertNil(tabs(#"{"id": "home"}"#), "not a list")
        XCTAssertEqual(navigation(#"{"tabs": [{"id": "home"}]}"#)?.tabs, Navigation.builtInTabs)
    }

    func testTabTitlesAndIcons() throws {
        let decoded = try XCTUnwrap(tabs("""
        [{"id": "home", "title": "  Start  ", "icon": "star"}, {"id": "screen:size-guide"},
         {"id": "cart", "title": "A title much longer than sixteen", "icon": "rocket"}]
        """))
        XCTAssertEqual(decoded, [
            ShellTab(id: "home", title: "Start", icon: "star"),
            ShellTab(id: "screen:size-guide", title: "Size guide", icon: "star"),
            ShellTab(id: "cart", title: "A title much lon", icon: "bag"),
        ])
        XCTAssertEqual(decoded[1].screen, "size-guide")
        XCTAssertNil(decoded[0].screen)
    }

    func testUploadedIconsComeFromTheStoresFilesOnly() throws {
        let icon = "https://cdn.shopify.com/s/files/1/0001/files/sizes.png?v=1"
        let decoded = try XCTUnwrap(tabs("""
        [{"id": "home", "icon": "\(icon)"}, {"id": "cart", "icon": "https://example.com/x.png"}]
        """))
        XCTAssertEqual(decoded[0].iconUrl, icon)
        XCTAssertEqual(decoded[1], ShellTab(id: "cart", title: "Cart", icon: "bag"), "another host is the id's own icon")
        XCTAssertNil(decoded[1].iconUrl)
    }

    func testTopBarAndDrawerValues() {
        XCTAssertNil(navigation(#"{"topBar": {"style": "fancy"}}"#)?.topBarStyle)
        XCTAssertEqual(navigation(#"{"topBar": {"style": "search"}}"#)?.topBarStyle, "search")
        XCTAssertNil(navigation(#"{"drawer": {"enabled": false, "menu": "main-menu"}}"#)?.drawerMenu)
        XCTAssertEqual(navigation(#"{"drawer": {"enabled": true}}"#)?.drawerMenu, "main-menu")
        XCTAssertEqual(navigation(#"{"drawer": {"enabled": true, "menu": " "}}"#)?.drawerMenu, "main-menu")
        XCTAssertEqual(navigation(#"{"labels": "no"}"#)?.labels, true)
        XCTAssertNil(navigation("[]"))
    }

    func testBarColoursAreReadAndABadOneIsTheThemes() throws {
        let colours = try XCTUnwrap(navigation("""
        {"topBar": {"background": "#ffffff", "foreground": "#111111"}, "tabBar": {"background": "#FAFAFA", "active": "#1f6feb", "inactive": "#8A8A8A"}}
        """))
        XCTAssertEqual(colours.topBarBackground, "#FFFFFF")
        XCTAssertEqual(colours.topBarForeground, "#111111")
        XCTAssertEqual(colours.tabBarBackground, "#FAFAFA")
        XCTAssertEqual(colours.tabBarActive, "#1F6FEB")
        XCTAssertEqual(colours.tabBarInactive, "#8A8A8A")
        let bad = try XCTUnwrap(navigation("""
        {"topBar": {"background": "white", "foreground": 17}, "tabBar": {"background": "#FFF", "active": "#GGGGGG", "inactive": null}}
        """))
        XCTAssertNil(bad.topBarBackground)
        XCTAssertNil(bad.topBarForeground)
        XCTAssertNil(bad.tabBarBackground)
        XCTAssertNil(bad.tabBarActive)
        XCTAssertNil(bad.tabBarInactive)
        XCTAssertNil(navigation(#"{"tabBar": "dark"}"#)?.tabBarBackground)
        // unset: the theme's (the built-in navigation has none)
        XCTAssertNil(Navigation().topBarBackground)
        XCTAssertNil(Navigation().tabBarActive)
    }

    func testAnnouncementFallbacks() {
        func announcement(_ json: String) -> Announcement? { Announcement.decode(JSONValue(json: json)) }
        XCTAssertNil(announcement(#"{"enabled": false, "messages": [{"text": "Hi"}]}"#))
        XCTAssertNil(announcement(#"{"messages": []}"#))
        XCTAssertNil(announcement(#"{"messages": [{"text": "  "}, {"link": "/cart"}]}"#), "no message has words")
        XCTAssertEqual(
            announcement(#"{"messages": [{"text": "Hi", "link": ""}, "x"], "background": "red", "color": 3, "interval": 60}"#),
            Announcement(messages: [AnnouncementMessage(text: "Hi")], background: "#111111", color: "#FFFFFF", interval: 15, dismissible: true)
        )
        XCTAssertEqual(announcement(#"{"messages": [{"text": "Hi"}], "interval": 1}"#)?.interval, 3)
    }

    func testAppearance() {
        XCTAssertEqual(Appearance.decode(JSONValue(json: #"{"mode": "light"}"#)), .light)
        XCTAssertEqual(Appearance.decode(JSONValue(json: #"{"mode": " System "}"#)), .system)
        XCTAssertNil(Appearance.decode(JSONValue(json: #"{"mode": "sepia"}"#)))
        XCTAssertNil(Appearance.decode(nil))
        XCTAssertNil(Appearance.system.colorScheme)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }

    func testIconNames() {
        XCTAssertEqual(Navigation.icons.map { shellIcon($0) }.count, 9)
        XCTAssertEqual(shellIcon("heart"), .heart)
        XCTAssertEqual(shellIcon("star"), .star)
        XCTAssertEqual(shellIcon("unknown"), .star)
    }

    // MARK: Fonts

    private func fonts(_ json: String) -> MerchantFonts? { RemoteSettings(json: Data(json.utf8))?.fonts }

    func testBothFontRolesDecode() throws {
        let fonts = try XCTUnwrap(fonts("""
        {"appearance": {"mode": "system", "fonts": {
          "heading": {"family": "Playfair Display", "files": {"400": "https://fonts.gstatic.com/s/a.ttf", "700": "https://fonts.gstatic.com/s/b.ttf"}},
          "body": {"family": " Assistant ", "files": {"400": "https://fonts.gstatic.com/s/c.ttf", "600": "https://fonts.gstatic.com/s/d.ttf"}}
        }}}
        """))
        XCTAssertEqual(fonts.heading, MerchantFont(family: "Playfair Display", files: [400: "https://fonts.gstatic.com/s/a.ttf", 700: "https://fonts.gstatic.com/s/b.ttf"]))
        XCTAssertEqual(fonts.body, MerchantFont(family: "Assistant", files: [400: "https://fonts.gstatic.com/s/c.ttf", 600: "https://fonts.gstatic.com/s/d.ttf"]))
    }

    func testAFontOffGstaticDropsOnlyItsRole() throws {
        let fonts = try XCTUnwrap(fonts("""
        {"appearance": {"fonts": {
          "heading": {"family": "Evil", "files": {"400": "https://fonts.gstatic.com/s/a.ttf", "700": "https://example.com/b.ttf"}},
          "body": {"family": "Assistant", "files": {"400": "https://fonts.gstatic.com/s/c.ttf"}}
        }}}
        """))
        XCTAssertNil(fonts.heading)
        XCTAssertEqual(fonts.body?.family, "Assistant")
    }

    func testMissingOrEmptyFontsAreNil() {
        XCTAssertNil(fonts("{}"))
        XCTAssertNil(fonts(#"{"appearance": {"mode": "dark"}}"#))
        XCTAssertNil(fonts(#"{"appearance": {"fonts": "x"}}"#))
        XCTAssertNil(fonts(#"{"appearance": {"fonts": {"heading": {"family": "", "files": {"400": "https://fonts.gstatic.com/s/a.ttf"}}}}}"#))
        XCTAssertNil(fonts(#"{"appearance": {"fonts": {"body": {"family": "Assistant", "files": {}}}}}"#))
        XCTAssertEqual(RemoteSettings(json: Data(#"{"appearance": {"mode": "dark", "fonts": 1}}"#.utf8))?.appearance, .dark)
    }

    func testBadWeightKeysAreSkipped() throws {
        let body = try XCTUnwrap(fonts("""
        {"appearance": {"fonts": {"body": {"family": "Assistant", "files": {
          "bold": "https://fonts.gstatic.com/s/x.ttf", "1000": "https://fonts.gstatic.com/s/y.ttf", "500": "https://fonts.gstatic.com/s/z.ttf"
        }}}}}
        """)?.body)
        XCTAssertEqual(body.files, [500: "https://fonts.gstatic.com/s/z.ttf"])
        XCTAssertNil(fonts(#"{"appearance": {"fonts": {"body": {"family": "Assistant", "files": {"bold": "https://fonts.gstatic.com/s/x.ttf"}}}}}"#))
    }
}
