package app.argon.ui.components

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class IconNameTest {
    private fun snake(name: String) = name.replace(Regex("(?<=[a-z])(?=[A-Z])"), "_").lowercase()

    // the spec's list; the iOS ArgonIconName has the same names
    private val spec = listOf(
        "home", "grid", "search", "bag", "heart", "heartFilled", "person", "menu", "close", "back", "chevronRight",
        "chevronDown", "chevronUp", "plus", "minus", "filter", "sort", "share", "star", "starFilled", "location", "phone",
        "mail", "check", "info", "warning", "trash", "edit", "play", "pause", "truck", "returns", "leaf", "clock", "gift",
        "lock", "globe", "calendar", "tag", "external", "eye", "eyeOff",
    )

    @Test
    fun namesMatchTheSpec() =
        assertEquals(spec, ArgonIconName.entries.map { it.name.replaceFirstChar(Char::lowercase) })

    @Test
    fun everyNameMapsToItsBundledDrawable() {
        val drawables = Class.forName("app.argon.ui.R\$drawable")
        for (icon in ArgonIconName.entries) {
            val resource = "argon_ic_${snake(icon.name)}"
            assertEquals(icon.name, drawables.getField(resource).getInt(null), icon.drawable)
            // unit tests run in the module directory
            val file = File("src/main/res/drawable/$resource.xml")
            assertTrue("$file", file.isFile && file.readText().contains("<vector"))
        }
    }

    @Test
    fun noDrawableIsLeftUnmapped() {
        val bundled = File("src/main/res/drawable").list()!!.filter { it.startsWith("argon_ic_") }.map { it.removeSuffix(".xml") }.toSet()
        assertEquals(bundled, ArgonIconName.entries.map { "argon_ic_${snake(it.name)}" }.toSet())
    }
}
