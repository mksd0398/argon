import Foundation

// The app shell from the merchant's settings (screens v2 spec, "App shell"): the tab bar, the top bar, the drawer, the
// announcement strip and light/dark. Each part is decoded leniently on its own; what is missing or invalid is the app's
// built-in behaviour, so empty settings change nothing. The same on Android (Shell.kt).

/// One tab of the bar. `id`: `home`, `shop`, `search`, `wishlist`, `cart`, `account`, or `screen:<handle>` (a custom
/// page); `icon`: a name of Argon's icon set (`home`, `grid`, `search`, `heart`, `bag`, `person`, `star`, `tag`, `menu`).
struct ShellTab: Equatable, Sendable {
    let id: String
    let title: String
    let icon: String

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
            let icon = tab["icon"]?.string.flatMap { icons.contains($0) ? $0 : nil } ?? defaultIcons[id] ?? "star"
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
/// in `color` (`#RRGGBB`), closable for the session when `dismissible`.
struct Announcement: Equatable, Sendable {
    let messages: [AnnouncementMessage]
    var background = "#111111"
    var color = "#FFFFFF"
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
            background: settings.color("background", "#111111"),
            color: settings.color("color", "#FFFFFF"),
            interval: Int(settings.number("interval", 5, 3...15)),
            dismissible: settings.boolean("dismissible", true)
        )
    }
}

/// Light or dark: `system` (the device's), `light` or `dark`.
enum Appearance: String, Equatable, Sendable {
    case system, light, dark

    /// `json` (the settings' `appearance`); nil without a known `mode`.
    static func decode(_ json: JSONValue?) -> Appearance? {
        json?["mode"]?.string.flatMap { Appearance(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }
}
