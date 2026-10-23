package app.storefront.data

import java.io.File
import java.nio.file.Files
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

/** `appearance.fonts`: each role decoded on its own, Argon's font (null) when invalid. */
class FontsTest {
    private val gs = "https://fonts.gstatic.com/s"

    private fun fonts(json: String) = RemoteSettings.decode("""{"appearance":{"mode":"system","fonts":$json}}""")!!.fonts

    @Test
    fun decodesBothRoles() {
        val f = fonts(
            """{"heading":{"family":"Playfair Display","files":{"400":"$gs/a.ttf","700":"$gs/b.ttf"}},
               "body":{"family":"Assistant","files":{"400":"$gs/c.ttf","500":"$gs/d.ttf","600":"$gs/e.ttf","700":"$gs/f.ttf"}}}""",
        )!!
        assertEquals(RemoteFont("Playfair Display", mapOf(400 to "$gs/a.ttf", 700 to "$gs/b.ttf")), f.heading)
        assertEquals("Assistant", f.body!!.family)
        assertEquals(listOf(400, 500, 600, 700), f.body!!.files.keys.toList())
    }

    @Test
    fun aUrlOffGoogleFontsDropsOnlyItsRole() {
        val f = fonts(
            """{"heading":{"family":"X","files":{"400":"$gs/a.ttf","700":"https://evil.example/b.ttf"}},
               "body":{"family":"Y","files":{"400":"$gs/c.ttf"}}}""",
        )!!
        assertNull(f.heading)
        assertEquals("Y", f.body!!.family)
        assertNull(fonts("""{"body":{"family":"Y","files":{"400":"https://fonts.gstatic.com.evil.example/c.ttf"}}}"""))
    }

    @Test
    fun missingOrEmptyFontsAreNull() {
        assertNull(RemoteSettings.decode("""{"appearance":{"mode":"dark"}}""")!!.fonts)
        assertNull(RemoteSettings.decode("{}")!!.fonts)
        assertNull(fonts("{}"))
        assertNull(fonts("[]"))
        assertNull(fonts("""{"heading":{"family":" ","files":{"400":"$gs/a.ttf"}}}"""))
        assertNull(fonts("""{"heading":{"family":"X","files":{}}}"""))
        assertNull(fonts("""{"heading":{"family":"X"}}"""))
    }

    @Test
    fun badWeightKeysAreIgnored() {
        val f = fonts("""{"body":{"family":"Y","files":{"400":"$gs/a.ttf","bold":"$gs/b.ttf","950":"$gs/c.ttf","450":"$gs/d.ttf","0":"x"}}}""")!!
        assertEquals(mapOf(400 to "$gs/a.ttf"), f.body!!.files)
        assertNull(fonts("""{"body":{"family":"Y","files":{"bold":"$gs/b.ttf"}}}"""))
    }

    @Test
    fun aFontTheAppWasBuiltWithIsInTheCacheFromTheFirstLaunch() {
        val dir = Files.createTempDirectory("fonts").toFile()
        val ttf = byteArrayOf(0, 1, 0, 0, 9, 9)
        val asked = mutableListOf<String>()
        val cache = FontCache(File(dir, "fonts"), OkHttpClient()) { name -> asked += name; if (asked.size == 1) ttf else "<html>".toByteArray() }
        runCatching { cache.family(RemoteFont("X", mapOf(400 to "$gs/a.ttf", 700 to "$gs/b.ttf"))) }
        assertEquals(2, asked.size)
        assertTrue(asked.all { Regex("[0-9a-f]{64}[.]ttf").matches(it) })
        val written = File(dir, "fonts").listFiles().orEmpty()
        assertEquals("only a real font is kept", listOf(asked[0]), written.map { it.name })
        dir.deleteRecursively()
    }
}
