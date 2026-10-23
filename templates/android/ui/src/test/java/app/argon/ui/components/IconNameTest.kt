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
    fun everyIconHasAFilledDrawingItsOwnOrTheSame() {
        val drawables = Class.forName("app.argon.ui.R\$drawable")
        for (icon in ArgonIconName.entries) {
            val own = "argon_ic_${snake(icon.name)}_fill"
            val file = File("src/main/res/drawable/$own.xml")
            if (file.isFile) assertEquals(icon.name, drawables.getField(own).getInt(null), icon.filled)
            else assertEquals("${icon.name} draws filled as it is", icon.drawable, icon.filled)
        }
        assertTrue(File("src/main/res/drawable/argon_ic_home_fill.xml").isFile)
    }

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
        val drawables = Class.forName("app.argon.ui.R\$drawable")
        val mapped = ArgonIconName.entries.flatMap { listOf(it.drawable, it.filled) }.toSet()
        assertEquals(bundled, bundled.filter { drawables.getField(it).getInt(null) in mapped }.toSet())
    }
}
