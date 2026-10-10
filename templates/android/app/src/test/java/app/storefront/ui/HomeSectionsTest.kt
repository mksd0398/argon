package app.storefront.ui

import app.storefront.data.ArgonApiError
import app.storefront.data.Brand
import app.storefront.data.Metaobject
import app.storefront.data.Section
import app.storefront.data.fixtureStorefront
import app.storefront.data.toBrand
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeSectionsTest {
    private val api = fixtureStorefront()
    private val brand: Brand = runBlocking { api.shop().toBrand("mock.shop") }

    /** Runs [homeSections] with the fixtures; [calls] records which queries ran. */
    private fun home(calls: MutableList<String>, homeResponse: suspend () -> List<Metaobject>): List<Section> = runBlocking {
        homeSections(
            brand,
            home = { calls += "home"; homeResponse() },
            fallback = { calls += "fallback"; api.fallbackHome() },
        )
    }

    @Test
    fun theStoresScreenIsUsedWhenItHasSections() {
        val calls = mutableListOf<String>()
        val sections = home(calls) { api.homeScreen() }
        assertEquals(listOf("home"), calls)
        assertTrue(sections.first() is Section.Banner)
    }

    @Test
    fun noRenderableSectionsFallBack() {
        val calls = mutableListOf<String>()
        val sections = home(calls) { emptyList() }
        assertEquals(listOf("home", "fallback"), calls)
        assertTrue(sections.first() is Section.Collections)
    }

    @Test
    fun graphqlErrorsFallBack() {
        // e.g. a token without metaobject access: a 200 response carrying errors
        val calls = mutableListOf<String>()
        val sections = home(calls) { throw ArgonApiError.GraphQL(listOf("Access denied for metaobject")) }
        assertEquals(listOf("home", "fallback"), calls)
        assertTrue(sections.isNotEmpty())
    }

    @Test
    fun httpFailuresAreRethrownNotReplacedByTheFallback() {
        val calls = mutableListOf<String>()
        val e = assertThrows(ArgonApiError.Http::class.java) { home(calls) { throw ArgonApiError.Http(503) } }
        assertEquals(503, e.status)
        assertEquals("the fallback must not run, or Loader would cache a degraded home", listOf("home"), calls)
    }

    @Test
    fun invalidResponsesAreRethrown() {
        val calls = mutableListOf<String>()
        assertThrows(ArgonApiError.Decoding::class.java) { home(calls) { throw ArgonApiError.Decoding("HomeScreen", "no data") } }
        assertEquals(listOf("home"), calls)
    }

    @Test
    fun aFailingFallbackStillSurfacesItsError() {
        val e = assertThrows(ArgonApiError.Http::class.java) {
            runBlocking { homeSections(brand, home = { emptyList() }, fallback = { throw ArgonApiError.Http(500) }) }
        }
        assertEquals("HTTP 500", e.message)
    }
}
