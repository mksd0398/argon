package app.storefront.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The app shell's settings (screens v2 spec, "App shell"): decoded leniently, the built-in behaviour when invalid. */
class ShellTest {
    private val spec = """
        {
          "navigation": {
            "tabs": [{ "id": "home", "title": "Home", "icon": "home" }, { "id": "shop" }, { "id": "search" }, { "id": "wishlist" }, { "id": "account" }],
            "labels": false,
            "topBar": { "style": "centered_logo", "transparentOnHome": true },
            "drawer": { "enabled": true, "menu": "footer" }
          },
          "announcement": {
            "enabled": true, "messages": [{ "text": "Free shipping over $75", "link": "/collections/all" }],
            "background": "#222222", "color": "#EEEEEE", "interval": 7, "dismissible": false
          },
          "appearance": { "mode": "dark" }
        }
    """.trimIndent()

    private fun navigation(json: String) = RemoteSettings.decode("""{"navigation":$json}""")!!.navigation!!

    @Test
    fun decodesTheSpecsExample() {
        val s = RemoteSettings.decode(spec)!!
        val nav = s.navigation!!
        assertEquals(listOf("home", "shop", "search", "wishlist", "account"), nav.tabs.map { it.id })
        assertEquals(ShellTab("search", "Search", "search"), nav.tabs[2])
        assertFalse(nav.labels)
        assertEquals("centered_logo", nav.topBarStyle)
        assertTrue(nav.transparentOnHome)
        assertEquals("footer", nav.drawerMenu)
        assertFalse("no cart tab: the cart is behind the bag button", nav.hasTab("cart"))
        assertEquals(Announcement(listOf(AnnouncementMessage("Free shipping over $75", "/collections/all")), "#222222", "#EEEEEE", 7, false), s.announcement)
        assertEquals(Appearance.Dark, s.appearance)
    }

    @Test
    fun withoutTheShellSettingsEverythingIsBuiltIn() {
        val s = RemoteSettings.decode("{}")!!
        assertNull(s.navigation)
        assertNull(s.announcement)
        assertNull(s.appearance)
        val nav = Navigation()
        assertEquals(listOf("home", "shop", "wishlist", "cart", "account"), nav.tabs.map { it.id })
        assertEquals(listOf("Home", "Shop", "Wishlist", "Cart", "Account"), nav.tabs.map { it.title })
        assertTrue(nav.labels)
        assertNull(nav.topBarStyle)
        assertFalse(nav.transparentOnHome)
        assertNull(nav.drawerMenu)
    }

    @Test
    fun anInvalidTabListIsTheBuiltInFive() {
        val builtIn = Navigation.BUILT_IN_TABS
        assertEquals("home not first", builtIn, navigation("""{"tabs":[{"id":"shop"},{"id":"home"}]}""").tabs)
        assertEquals("one tab", builtIn, navigation("""{"tabs":[{"id":"home"}]}""").tabs)
        assertEquals("six tabs", builtIn, navigation("""{"tabs":[{"id":"home"},{"id":"shop"},{"id":"search"},{"id":"wishlist"},{"id":"cart"},{"id":"account"}]}""").tabs)
        assertEquals("unknown id", builtIn, navigation("""{"tabs":[{"id":"home"},{"id":"blog"}]}""").tabs)
        assertEquals("repeated", builtIn, navigation("""{"tabs":[{"id":"home"},{"id":"home"}]}""").tabs)
        assertEquals("not a list", builtIn, navigation("""{"tabs":"home"}""").tabs)
        assertEquals("a tab that isn't an object", builtIn, navigation("""{"tabs":[{"id":"home"},"shop"]}""").tabs)
    }

    @Test
    fun customPageTabsTitlesAndIcons() {
        val tabs = navigation("""{"tabs":[{"id":"home","title":"  "},{"id":"screen:size-guide","icon":"tag"},{"id":"cart","title":"A very long cart title","icon":"rocket"}]}""").tabs
        assertEquals(ShellTab("home", "Home", "home"), tabs[0])
        assertEquals(ShellTab("screen:size-guide", "Size guide", "tag"), tabs[1])
        assertEquals("size-guide", tabs[1].screen)
        assertEquals("titles up to 16, an unknown icon is the id's own", ShellTab("cart", "A very long cart", "bag"), tabs[2])
    }

    @Test
    fun badValuesFallBackOneByOne() {
        val nav = navigation("""{"labels":"no","topBar":{"style":"floating","transparentOnHome":1},"drawer":{"enabled":true}}""")
        assertTrue(nav.labels)
        assertNull(nav.topBarStyle)
        assertFalse(nav.transparentOnHome)
        assertEquals("an enabled drawer without a menu is the main menu", "main-menu", nav.drawerMenu)
        assertNull("a drawer that isn't enabled", navigation("""{"drawer":{"menu":"main-menu"}}""").drawerMenu)

        val a = RemoteSettings.decode("""{"announcement":{"messages":[{"text":" "},{"text":"Hi","link":""},7],"background":"black","interval":99}}""")!!.announcement!!
        assertEquals(listOf(AnnouncementMessage("Hi")), a.messages)
        assertEquals("#111111", a.background)
        assertEquals(15, a.interval)
        assertTrue(a.dismissible)
        assertNull("off", RemoteSettings.decode("""{"announcement":{"enabled":false,"messages":[{"text":"Hi"}]}}""")!!.announcement)
        assertNull("nothing to say", RemoteSettings.decode("""{"announcement":{"messages":[]}}""")!!.announcement)
        assertNull(RemoteSettings.decode("""{"appearance":{"mode":"sepia"}}""")!!.appearance)
        assertEquals(Appearance.Light, RemoteSettings.decode("""{"appearance":{"mode":"Light"}}""")!!.appearance)
    }

    @Test
    fun navigationColours() {
        val nav = navigation(
            """{"topBar":{"style":"standard","background":"#ffffff","foreground":"#111111"},"tabBar":{"background":"#FAFAFA","active":"#111111","inactive":"#8A8A8A"}}""",
        )
        assertEquals("#FFFFFF" to "#111111", nav.topBarBackground to nav.topBarForeground)
        assertEquals(Triple("#FAFAFA", "#111111", "#8A8A8A"), Triple(nav.tabBarBackground, nav.tabBarActive, nav.tabBarInactive))

        val bad = navigation("""{"topBar":{"background":"white","foreground":"#12345"},"tabBar":{"background":17,"active":"#GGGGGG"}}""")
        assertEquals(listOf<String?>(null, null, null, null, null), listOf(bad.topBarBackground, bad.topBarForeground, bad.tabBarBackground, bad.tabBarActive, bad.tabBarInactive))
        assertNull("unset: the theme's", Navigation().topBarBackground)
    }
}
