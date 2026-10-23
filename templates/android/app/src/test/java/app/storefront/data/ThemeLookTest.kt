package app.storefront.data

import androidx.compose.ui.graphics.toArgb
import app.argon.ui.argonColors
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

/** The theme's vectors (contract/fixtures/theme/vectors.json): what contract/theme.js, iOS and Krypton's previews compute too. */
class ThemeLookTest {
    private val vectors = Json.parseToJsonElement(javaClass.getResource("/fixtures/theme/vectors.json")!!.readText()) as JsonArray

    @Test
    fun colorsCornersAndButtonsAsTheContractMakesThem() {
        for (vector in vectors.map { it.jsonObject }) {
            val given = vector["appearance"]!!.jsonObject
            val dark = vector["dark"]!!.jsonPrimitive.boolean
            val want = vector["tokens"]!!.jsonObject
            // the settings' shape: `colors.background`, `colors.text`, `corners`, `buttons` (the accent is `brand.accent`)
            val appearance = JsonObject(
                buildMap {
                    put("colors", JsonObject(listOfNotNull(given["background"]?.let { "background" to it }, given["text"]?.let { "text" to it }).toMap()))
                    given["corners"]?.let { put("corners", it) }
                    given["buttons"]?.let { put("buttons", it) }
                },
            )
            val look = ThemeLook.decode(appearance)!!
            val colors = argonColors(given["accent"]?.jsonPrimitive?.content, dark, look.background, look.text)
            val hex = { c: androidx.compose.ui.graphics.Color -> "#%06X".format(c.toArgb() and 0xFFFFFF) }
            val tokens = mapOf(
                "ink" to colors.ink, "muted" to colors.muted, "paper" to colors.paper, "surface" to colors.surface, "border" to colors.border,
                "sale" to colors.sale, "success" to colors.success, "accent" to colors.accent, "onAccent" to colors.onAccent,
            )
            for ((name, color) in tokens) assertEquals("$given dark=$dark $name", want[name]!!.jsonPrimitive.content, hex(color))
            val radius = want["radius"]!!.jsonObject
            assertEquals("$given corners", listOf("s", "m", "l").map { radius[it]!!.jsonPrimitive.int }, look.corners.dp)
            assertEquals("$given buttons", want["button"]!!.jsonPrimitive.int, look.buttons.dp)
        }
    }

    @Test
    fun noAppearanceIsArgonsOwn() {
        assertEquals(ThemeLook(), ThemeLook.decode(JsonObject(emptyMap())))
        assertEquals(null, RemoteSettings.decode("{}")!!.look)
    }
}
