package app.storefront.data

import java.time.ZoneOffset
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Every case of contract/fixtures/liquid/cases.json (the lenient ones too), the cases liquidjs passes in `npm test`. */
class LiquidTest {
    private val file = json(LiquidTest::class.java.getResource("/fixtures/liquid/cases.json")!!.readText())

    // a case's `context` is merged over the shared one, map by map
    @Suppress("UNCHECKED_CAST")
    private fun merge(base: Map<String, Any?>, over: Map<String, Any?>): Map<String, Any?> = base + over.mapValues { (key, value) ->
        val under = base[key]
        if (value is Map<*, *> && under is Map<*, *>) merge(under as Map<String, Any?>, value as Map<String, Any?>) else value
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun everyCaseGivesItsExpectedOutput() {
        val shared = Liquid.value(file["context"]!!) as Map<String, Any?>
        val cases = file["cases"]!!.jsonArray.map { it.jsonObject }
        assertTrue(cases.size >= 60)
        val wrong = cases.mapNotNull { case ->
            val context = (case["context"] as? JsonObject)?.let { merge(shared, Liquid.value(it) as Map<String, Any?>) } ?: shared
            val template = case["template"]!!.jsonPrimitive.content
            val expected = case["expected"]!!.jsonPrimitive.content
            val got = Liquid.render(template, context, ZoneOffset.UTC)
            if (got == expected) null else "${case["name"]!!.jsonPrimitive.content}: got ${Json.encodeToString(got)}, expected ${Json.encodeToString(expected)}"
        }
        assertEquals(emptyList<String>(), wrong)
    }

    @Test
    fun textWithoutLiquidIsNotParsed() {
        assertEquals("{ not } liquid %", Liquid.render("{ not } liquid %", emptyMap()))
    }

    @Test
    fun aBrokenBlockRendersTheTextWithoutItsLiquid() {
        assertEquals("a b", Liquid.render("a {% if x %}b", emptyMap()))
        assertEquals("ab", Liquid.render("a{% endif %}b", emptyMap()))
    }

    @Test
    fun aValueNoFilterCanTakeRendersTheTextWithoutItsLiquid() {
        val nan = mapOf("x" to Double.NaN, "big" to Double.POSITIVE_INFINITY)
        assertEquals("a b", Liquid.render("a {{ x | round }}b", nan))
        assertEquals("a b", Liquid.render("a {{ big | money }}b", nan))
        assertEquals("a b", Liquid.render("a {{ 99999999999999999 | date: '%Y' }}b", emptyMap(), ZoneOffset.UTC))
    }

    @Test
    fun runawayTemplatesStopAtTheBudget() {
        val grow = "{% assign s = 'ab' %}" + "{% assign s = s | append: s %}".repeat(40) + "[{{ s | size }}]"
        val loops = "{% assign xs = '" + "x,".repeat(5_000) + "' | split: ',' %}{% for a in xs %}{% for b in xs %}.{% endfor %}{% endfor %}done"
        for (template in listOf(grow, loops)) {
            val started = System.nanoTime()
            val out = Liquid.render(template, emptyMap())
            assertTrue("took ${(System.nanoTime() - started) / 1_000_000} ms", System.nanoTime() - started < 5_000_000_000L)
            assertEquals(Liquid.withoutLiquid(template), out)
        }
    }
}
