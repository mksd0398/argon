package app.storefront.ui

import app.storefront.data.Brand
import app.storefront.data.Section
import app.storefront.data.StorefrontException
import app.storefront.data.fixture
import app.storefront.data.json
import app.storefront.data.obj
import app.storefront.data.parseBrand
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeSectionsTest {
    private val brand: Brand = parseBrand(fixture("shop").obj("shop")!!, "mock.shop")

    /** Runs [homeSections] with canned responses; [calls] records which queries ran. */
    private fun home(calls: MutableList<String>, homeResponse: () -> JsonObject): List<Section> = runBlocking {
        homeSections(
            brand,
            home = { calls += "home"; homeResponse() },
            fallback = { calls += "fallback"; fixture("fallback_home") },
        )
    }

    @Test
    fun theStoresScreenIsUsedWhenItHasSections() {
        val calls = mutableListOf<String>()
        val sections = home(calls) { fixture("home_screen") }
        assertEquals(listOf("home"), calls)
        assertTrue(sections.first() is Section.Banner)
    }

    @Test
    fun noRenderableSectionsFallBack() {
        val calls = mutableListOf<String>()
        val sections = home(calls) { json("""{"metaobject":null}""") }
        assertEquals(listOf("home", "fallback"), calls)
        assertTrue(sections.first() is Section.Collections)
    }

    @Test
    fun graphqlErrorsFallBack() {
        // e.g. a token without metaobject access: a 200 response carrying errors
        val calls = mutableListOf<String>()
        val sections = home(calls) { throw StorefrontException(listOf("Access denied for metaobject"), 200, isGraphQL = true) }
        assertEquals(listOf("home", "fallback"), calls)
        assertTrue(sections.isNotEmpty())
    }

    @Test
    fun httpFailuresAreRethrownNotReplacedByTheFallback() {
        val calls = mutableListOf<String>()
        val e = assertThrows(StorefrontException::class.java) { home(calls) { throw StorefrontException(listOf("HTTP 503"), 503) } }
        assertEquals(listOf("HTTP 503"), e.messages)
        assertEquals("the fallback must not run, or Loader would cache a degraded home", listOf("home"), calls)
    }

    @Test
    fun invalidResponsesAreRethrown() {
        val calls = mutableListOf<String>()
        assertThrows(StorefrontException::class.java) { home(calls) { throw StorefrontException(listOf("Invalid response"), 200) } }
        assertEquals(listOf("home"), calls)
    }

    @Test
    fun aFailingFallbackStillSurfacesItsError() {
        val e = assertThrows(StorefrontException::class.java) {
            runBlocking {
                homeSections(brand, home = { json("""{"metaobject":null}""") }, fallback = { throw StorefrontException(listOf("HTTP 500"), 500) })
            }
        }
        assertEquals(listOf("HTTP 500"), e.messages)
    }
}
