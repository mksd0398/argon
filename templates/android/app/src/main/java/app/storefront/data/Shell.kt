package app.storefront.data

import app.argon.ui.ArgonButtonShape
import app.argon.ui.ArgonCorners
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

// The app shell from the merchant's settings (screens v2 spec, "App shell"): the tab bar, the top bar, the drawer, the
// announcement strip and light/dark. Each part is decoded leniently on its own; what is missing or invalid is the app's
// built-in behaviour, so empty settings change nothing.

/**
 * One tab of the bar. [id]: `home`, `shop`, `search`, `wishlist`, `cart`, `account`, or `screen:<handle>` (a custom
 * page); [icon]: a name of Argon's icon set (`home`, `grid`, `search`, `heart`, `bag`, `person`, `star`, `tag`, `menu`), or
 * the merchant's own icon: an image in the store's Files (`https://cdn.shopify.com/...`), drawn in the tab's colours.
 */
data class ShellTab(val id: String, val title: String, val icon: String) {
    /** The merchant's own icon's URL; null for one of Argon's icons. */
    val iconUrl: String? get() = icon.takeIf { isIconUrl(it) }

    /** The custom page's handle of a `screen:<handle>` tab; null for the others. */
    val screen: String? get() = id.removePrefix("screen:").takeIf { id.startsWith("screen:") }
}

/**
 * The tab bar and the top bar. [labels]: tab titles shown; [topBarStyle]: `standard`, `centered_logo` or `search` (null:
 * the home template's own bar); [transparentOnHome]: the home's bar lies over its first section, solid on scroll;
 * [drawerMenu]: the handle of the Shopify menu the home's menu button opens (null: no drawer). The colours (`#RRGGBB`,
 * null for the theme's): [topBarBackground] and [topBarForeground], the solid top bar and its title and icons on every
 * screen; [tabBarBackground], [tabBarActive] and [tabBarInactive], the tab bar and its selected and other tabs.
 */
data class Navigation(
    val tabs: List<ShellTab> = BUILT_IN_TABS,
    val labels: Boolean = true,
    val topBarStyle: String? = null,
    val transparentOnHome: Boolean = false,
    val drawerMenu: String? = null,
    val topBarBackground: String? = null,
    val topBarForeground: String? = null,
    val tabBarBackground: String? = null,
    val tabBarActive: String? = null,
    val tabBarInactive: String? = null,
) {
    fun hasTab(id: String): Boolean = tabs.any { it.id == id }

    companion object {
        val ICONS = setOf("home", "grid", "search", "heart", "bag", "person", "star", "tag", "menu")
        private val IDS = mapOf("home" to "Home", "shop" to "Shop", "search" to "Search", "wishlist" to "Wishlist", "cart" to "Cart", "account" to "Account")
        private val DEFAULT_ICONS = mapOf("home" to "home", "shop" to "grid", "search" to "search", "wishlist" to "heart", "cart" to "bag", "account" to "person")
        private val SCREEN = Regex("^screen:([a-z0-9_-]{1,100})$")
        private val STYLES = setOf("standard", "centered_logo", "search")

        /** The app's own five tabs: what an app without settings, or with an invalid list, shows. */
        val BUILT_IN_TABS = listOf("home", "shop", "wishlist", "cart", "account").map { ShellTab(it, IDS.getValue(it), DEFAULT_ICONS.getValue(it)) }

        /** [json] (the settings' `navigation`) read value by value; null without it. */
        fun decode(json: JsonObject?): Navigation? {
            json ?: return null
            val topBar = json.obj("topBar")
            val drawer = json.obj("drawer")
            val tabBar = json.obj("tabBar")
            return Navigation(
                tabs = tabs(json["tabs"]) ?: BUILT_IN_TABS,
                labels = json.bool("labels") ?: true,
                topBarStyle = topBar?.str("style")?.takeIf { it in STYLES },
                transparentOnHome = topBar?.bool("transparentOnHome") ?: false,
                drawerMenu = if (drawer?.bool("enabled") == true) drawer.str("menu")?.trim()?.ifEmpty { null } ?: "main-menu" else null,
                topBarBackground = topBar?.hex("background"),
                topBarForeground = topBar?.hex("foreground"),
                tabBarBackground = tabBar?.hex("background"),
                tabBarActive = tabBar?.hex("active"),
                tabBarInactive = tabBar?.hex("inactive"),
            )
        }

        /** The tabs of [json]: 2 to 5, `home` first, each id known and once; null (the built-in five) otherwise. */
        internal fun tabs(json: Any?): List<ShellTab>? {
            val list = (json as? JsonArray)?.map { it as? JsonObject ?: return null } ?: return null
            val tabs = list.map { tab ->
                val id = tab.str("id")?.trim() ?: return null
                val screen = SCREEN.find(id)?.groupValues?.get(1)
                if (id !in IDS && screen == null) return null
                val title = tab.str("title")?.trim()?.take(16)?.ifEmpty { null }
                    ?: IDS[id] ?: screen!!.replace('-', ' ').replace('_', ' ').replaceFirstChar { it.uppercase() }
                ShellTab(id, title, tab.str("icon")?.takeIf { it in ICONS || isIconUrl(it) } ?: DEFAULT_ICONS[id] ?: "star")
            }
            if (tabs.size !in 2..5 || tabs.first().id != "home" || tabs.map { it.id }.toSet().size != tabs.size) return null
            return tabs
        }
    }
}

/** An uploaded icon: only the store's Files, where Krypton puts it. */
internal fun isIconUrl(icon: String) = icon.startsWith("https://cdn.shopify.com/")

/** One message of the announcement strip; [link] goes through [Links.resolve]. */
data class AnnouncementMessage(val text: String, val link: String? = null)

/**
 * The strip above the top bar on every tab root: [messages] rotating every [interval] seconds (3-15), on [background]
 * in [color] (`#RRGGBB`), closable for the session when [dismissible].
 */
data class Announcement(
    val messages: List<AnnouncementMessage>,
    val background: String = "#111111",
    val color: String = "#FFFFFF",
    val interval: Int = 5,
    val dismissible: Boolean = true,
) {
    companion object {
        /** [json] (the settings' `announcement`); null when it is off, or has no message to show. */
        fun decode(json: JsonObject?): Announcement? {
            json ?: return null
            if (json.bool("enabled") == false) return null
            val messages = (json["messages"] as? JsonArray).orEmpty().mapNotNull { message ->
                val obj = message as? JsonObject ?: return@mapNotNull null
                val text = obj.str("text")?.trim()?.ifEmpty { null } ?: return@mapNotNull null
                AnnouncementMessage(text, obj.str("link")?.trim()?.ifEmpty { null })
            }
            if (messages.isEmpty()) return null
            return Announcement(
                messages,
                background = json.str("background")?.takeIf { HEX.matches(it) } ?: "#111111",
                color = json.str("color")?.takeIf { HEX.matches(it) } ?: "#FFFFFF",
                interval = json.num("interval")?.toInt()?.coerceIn(3, 15) ?: 5,
                dismissible = json.bool("dismissible") ?: true,
            )
        }
    }
}

/** Light or dark: `system` (the device's), `light` or `dark`. */
enum class Appearance(val value: String) {
    System("system"), Light("light"), Dark("dark");

    companion object {
        fun decode(json: JsonObject?): Appearance? = json?.str("mode")?.let { mode -> entries.firstOrNull { it.value == mode.trim().lowercase() } }
    }
}

/**
 * The theme's own look (`appearance`: `colors.background`, `colors.text`, `corners`, `buttons`), as ArgonTheme takes it:
 * null colours and Argon's corners and pill buttons when unset or not one of theirs.
 */
data class ThemeLook(
    val background: String? = null,
    val text: String? = null,
    val corners: ArgonCorners = ArgonCorners.Rounded,
    val buttons: ArgonButtonShape = ArgonButtonShape.Pill,
) {
    companion object {
        fun decode(json: JsonObject?): ThemeLook? = json?.let {
            ThemeLook(
                background = it.obj("colors")?.hex("background"),
                text = it.obj("colors")?.hex("text"),
                corners = ArgonCorners.entries.firstOrNull { c -> c.name.lowercase() == it.str("corners") } ?: ArgonCorners.Rounded,
                buttons = ArgonButtonShape.entries.firstOrNull { b -> b.name.lowercase() == it.str("buttons") } ?: ArgonButtonShape.Pill,
            )
        }
    }
}

private val HEX = Regex("^#[0-9A-Fa-f]{6}$")

/** A `#RRGGBB` colour (upper case); null when missing or not one. */
private fun JsonObject.hex(key: String) = str(key)?.takeIf { HEX.matches(it) }?.uppercase()
private fun JsonObject.obj(key: String) = this[key] as? JsonObject
private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
private fun JsonObject.num(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
