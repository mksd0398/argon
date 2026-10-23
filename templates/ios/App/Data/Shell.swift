import Foundation

// The app shell from the merchant's settings (screens v2 spec, "App shell"): the tab bar, the top bar, the drawer, the
// announcement strip and light/dark. Each part is decoded leniently on its own; what is missing or invalid is the app's
// built-in behaviour, so empty settings change nothing. The same on Android (Shell.kt).

/// One tab of the bar. `id`: `home`, `shop`, `search`, `wishlist`, `cart`, `account`, or `screen:<handle>` (a custom
/// page); `icon`: a name of Argon's icon set (`home`, `grid`, `search`, `heart`, `bag`, `person`, `star`, `tag`, `menu`),
/// or the merchant's own icon: an image in the store's Files (`https://cdn.shopify.com/...`), drawn in the tab's colours.
struct ShellTab: Equatable, Sendable {
    let id: String
    let title: String
    let icon: String

    /// The merchant's own icon's URL; nil for one of Argon's icons.
    var iconUrl: String? { Navigation.isIconUrl(icon) ? icon : nil }

    /// The custom page's handle of a `screen:<handle>` tab; nil for the others.
    var screen: String? { id.hasPrefix("screen:") ? String(id.dropFirst("screen:".count)) : nil }
}

/// The tab bar and the top bar. `labels`: tab titles shown; `topBarStyle`: `standard`, `centered_logo` or `search` (nil:
/// the home template's own bar); `transparentOnHome`: the home's bar lies over its first section, solid on scroll;
/// `drawerMenu`: the handle of the Shopify menu the home's menu button opens (nil: no drawer). The colours, each
/// `#RRGGBB` and nil for the theme's: `topBarBackground` and `topBarForeground`, the solid top bar and its title and
/// icons on every screen; `tabBarBackground`, `tabBarActive` (nil: the accent) and `tabBarInactive`, the tab bar and its
/// selected and other tabs.
struct Navigation: Equatable, Sendable {
    var tabs = Navigation.builtInTabs
    var labels = true
    var topBarStyle: String? = nil
    var transparentOnHome = false
    var drawerMenu: String? = nil
    var topBarBackground: String? = nil
    var topBarForeground: String? = nil
    var tabBarBackground: String? = nil
    var tabBarActive: String? = nil
    var tabBarInactive: String? = nil

    func hasTab(_ id: String) -> Bool { tabs.contains { $0.id == id } }

    static let icons: Set<String> = ["home", "grid", "search", "heart", "bag", "person", "star", "tag", "menu"]
    /// An uploaded icon: only the store's Files, where Krypton puts it.
    static func isIconUrl(_ icon: String) -> Bool { icon.hasPrefix("https://cdn.shopify.com/") }
    private static let ids = ["home": "Home", "shop": "Shop", "search": "Search", "wishlist": "Wishlist", "cart": "Cart", "account": "Account"]
    private static let defaultIcons = ["home": "home", "shop": "grid", "search": "search", "wishlist": "heart", "cart": "bag", "account": "person"]
    private static let styles: Set<String> = ["standard", "centered_logo", "search"]

    /// The app's own five tabs: what an app without settings, or with an invalid list, shows.
    static let builtInTabs = ["home", "shop", "wishlist", "cart", "account"].map {
        ShellTab(id: $0, title: ids[$0] ?? $0, icon: defaultIcons[$0] ?? "star")
    }

    /// `json` (the settings' `navigation`) read value by value; nil without it.
    static func decode(_ json: JSONValue?) -> Navigation? {
        guard let map = json?.object else { return nil }
        let topBar = map["topBar"]?.object
        let bar = SectionSettings(topBar ?? [:]), tabBar = SectionSettings(map["tabBar"]?.object ?? [:])
        let drawer = map["drawer"]?.object
        var drawerMenu: String? = nil
        if drawer?["enabled"]?.bool == true {
            let menu = drawer?["menu"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
            drawerMenu = menu.isEmpty ? "main-menu" : menu
        }
        return Navigation(
            tabs: tabs(map["tabs"]) ?? builtInTabs,
            labels: map["labels"]?.bool ?? true,
            topBarStyle: topBar?["style"]?.string.flatMap { styles.contains($0) ? $0 : nil },
            transparentOnHome: topBar?["transparentOnHome"]?.bool ?? false,
            drawerMenu: drawerMenu,
            topBarBackground: bar.hex("background"),
            topBarForeground: bar.hex("foreground"),
            tabBarBackground: tabBar.hex("background"),
            tabBarActive: tabBar.hex("active"),
            tabBarInactive: tabBar.hex("inactive")
        )
    }

    /// The tabs of `json`: 2 to 5, `home` first, each id known and once; nil (the built-in five) otherwise.
    static func tabs(_ json: JSONValue?) -> [ShellTab]? {
        guard let list = json?.array else { return nil }
        var tabs: [ShellTab] = []
        for entry in list {
            guard let tab = entry.object, let id = tab["id"]?.string?.trimmingCharacters(in: .whitespaces) else { return nil }
            let screen = screenHandle(id)
            guard ids[id] != nil || screen != nil else { return nil }
            let given = String((tab["title"]?.string?.trimmingCharacters(in: .whitespaces) ?? "").prefix(16))
            let title = !given.isEmpty ? given : ids[id] ?? (screen ?? "").replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ").capitalizedFirst
            let icon = tab["icon"]?.string.flatMap { icons.contains($0) || isIconUrl($0) ? $0 : nil } ?? defaultIcons[id] ?? "star"
            tabs.append(ShellTab(id: id, title: title, icon: icon))
        }
        guard (2...5).contains(tabs.count), tabs.first?.id == "home", Set(tabs.map { $0.id }).count == tabs.count else { return nil }
        return tabs
    }

    /// The handle of `screen:<handle>` (`[a-z0-9_-]`, up to 100); nil for anything else.
    private static func screenHandle(_ id: String) -> String? {
        guard id.hasPrefix("screen:") else { return nil }
        let handle = id.dropFirst("screen:".count)
        guard (1...100).contains(handle.count), handle.allSatisfy({ ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "_" || $0 == "-" }) else { return nil }
        return String(handle)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// One message of the announcement strip; `link` goes through `Links.resolve`.
struct AnnouncementMessage: Equatable, Sendable {
    let text: String
    var link: String? = nil
}

/// The strip above the top bar on every tab root: `messages` rotating every `interval` seconds (3-15), on `background`
/// in `color` (`#RRGGBB` or a theme colour's name; the theme inverted unless set), closable for the session when
/// `dismissible`.
struct Announcement: Equatable, Sendable {
    let messages: [AnnouncementMessage]
    var background = "text"
    var color = "background"
    var interval = 5
    var dismissible = true

    /// `json` (the settings' `announcement`); nil when it is off, or has no message to show.
    static func decode(_ json: JSONValue?) -> Announcement? {
        guard let map = json?.object, map["enabled"]?.bool != false else { return nil }
        let messages: [AnnouncementMessage] = (map["messages"]?.array ?? []).compactMap { message in
            guard let text = message["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let link = message["link"]?.string?.trimmingCharacters(in: .whitespaces)
            return AnnouncementMessage(text: text, link: link?.isEmpty == false ? link : nil)
        }
        if messages.isEmpty { return nil }
        let settings = SectionSettings(map)
        return Announcement(
            messages: messages,
            background: settings.color("background", "text"),
            color: settings.color("color", "background"),
            interval: Int(settings.number("interval", 5, 3...15)),
            dismissible: settings.boolean("dismissible", true)
        )
    }
}

/// Light or dark: `system` (the device's), `light` or `dark`.
/// The theme's own look (`appearance`: `colors.background`, `colors.text`, `colors.secondary`, `corners`, `buttons`,
/// `type.scale`, `icons`): nil colours when unset or not `#RRGGBB`, and Argon's rounded corners, pill buttons, sizes and
/// outlined icons when unset or not one of theirs (contract/theme.js).
struct ThemeLook: Equatable, Sendable {
    var background: String? = nil
    var text: String? = nil
    var corners = "rounded"
    var buttons = "pill"
    var secondary: String? = nil
    var scale = 1.0
    var icons = "outline"

    static func decode(_ json: JSONValue?) -> ThemeLook? {
        guard let json = json?.object else { return nil }
        let hex = { (value: String?) -> String? in
            guard let value, value.count == 7, value.hasPrefix("#"), UInt32(value.dropFirst(), radix: 16) != nil else { return nil }
            return value.uppercased()
        }
        let colors = json["colors"]?.object
        let corners = json["corners"]?.string ?? ""
        let buttons = json["buttons"]?.string ?? ""
        return ThemeLook(
            background: hex(colors?["background"]?.string),
            text: hex(colors?["text"]?.string),
            corners: ["square", "rounded", "round"].contains(corners) ? corners : "rounded",
            buttons: ["pill", "rounded", "square"].contains(buttons) ? buttons : "pill",
            secondary: hex(colors?["secondary"]?.string),
            scale: ["small": 0.9, "medium": 1, "large": 1.12][json["type"]?["scale"]?.string ?? ""] ?? 1,
            icons: json["icons"]?.string == "filled" ? "filled" : "outline"
        )
    }
}

enum Appearance: String, Equatable, Sendable {
    case system, light, dark

    /// `json` (the settings' `appearance`); nil without a known `mode`.
    static func decode(_ json: JSONValue?) -> Appearance? {
        json?["mode"]?.string.flatMap { Appearance(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }
}

/// One merchant font (`appearance.fonts.heading` or `.body`): a Google Fonts family and its TTF files by CSS weight
/// (100...900). Only files on fonts.gstatic.com are fetched.
struct MerchantFont: Equatable, Sendable {
    let family: String
    let files: [Int: String]

    /// `json` read leniently; nil when the family is blank, no file has a valid weight, or any file isn't on
    /// fonts.gstatic.com (the role then keeps Argon's font). A key that isn't a weight is skipped.
    static func decode(_ json: JSONValue?) -> MerchantFont? {
        guard let map = json?.object, let family = map["family"]?.string?.trimmingCharacters(in: .whitespaces),
              !family.isEmpty, let entries = map["files"]?.object else { return nil }
        var files: [Int: String] = [:]
        for (key, value) in entries {
            guard let weight = Int(key.trimmingCharacters(in: .whitespaces)), (100...900).contains(weight) else { continue }
            guard let url = value.string?.trimmingCharacters(in: .whitespaces), url.hasPrefix("https://fonts.gstatic.com/") else { return nil }
            files[weight] = url
        }
        return files.isEmpty ? nil : MerchantFont(family: family, files: files)
    }
}

/// The merchant's fonts (`appearance.fonts`): `heading` in place of Instrument Serif, `body` in place of Hanken Grotesk.
struct MerchantFonts: Equatable, Sendable {
    var heading: MerchantFont? = nil
    var body: MerchantFont? = nil

    /// `json` (the settings' `appearance`), each role on its own; nil when neither is valid.
    static func decode(_ json: JSONValue?) -> MerchantFonts? {
        let fonts = json?["fonts"]
        let decoded = MerchantFonts(heading: MerchantFont.decode(fonts?["heading"]), body: MerchantFont.decode(fonts?["body"]))
        return decoded.heading == nil && decoded.body == nil ? nil : decoded
    }
}
