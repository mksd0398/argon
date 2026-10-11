package app.storefront.ui

import app.storefront.data.ArgonApiError
import app.storefront.data.Brand
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.HomeTemplate
import app.storefront.data.Metaobject
import app.storefront.data.Route
import app.storefront.data.Section
import app.storefront.data.fixtureStorefront
import app.storefront.data.toBrand
import app.storefront.ui.home.heroBanners
import app.storefront.ui.home.routeOf
import app.storefront.ui.home.title
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeContentTest {
    private val api = fixtureStorefront()
    private val brand: Brand = runBlocking { api.shop().toBrand("mock.shop") }

    /** Runs [homeContent] with the fixtures; [calls] records which queries ran. */
    private fun content(
        calls: MutableList<String> = mutableListOf(),
        template: HomeTemplate = HomeTemplate.Fashion,
        fallback: suspend () -> List<CollectionCard> = { api.fallbackHome() },
        home: suspend () -> List<Metaobject>,
    ): HomeContent = runBlocking {
        homeContent(template, brand, home = { calls += "home"; home() }, fallback = { calls += "fallback"; fallback() })
    }

    @Test
    fun theStoresOwnSectionsShowAndItsCollectionsFillTheRest() {
        val calls = mutableListOf<String>()
        val content = content(calls) { api.homeScreen() }
        assertEquals("both queries run, whatever the first answers", setOf("home", "fallback"), calls.toSet())
        assertEquals("the store's banner, not the stock ones", listOf("New season"), content.banners.map { it.heading })
        assertEquals(listOf("Featured"), content.rails.map { it.heading })
        assertEquals(listOf("men", "women", "unisex"), content.categories.map { it.handle })
    }

    @Test
    fun aStoreWithoutAHomeScreenGetsItsTemplatesBannersAndItsCollections() {
        val content = content(template = HomeTemplate.Grocery) { emptyList() }
        assertEquals(listOf("Fresh today", "Fill your basket", "Baked this morning"), content.banners.map { it.heading })
        assertEquals(listOf("men", "women", "unisex"), content.categories.map { it.handle })
        assertEquals(listOf("Men", "Women", "Unisex"), content.rails.map { it.heading })
    }

    @Test
    fun aRefusedHomeScreenQueryCountsAsNoSections() {
        // e.g. a token without metaobject access: a 200 response carrying errors
        val content = content(template = HomeTemplate.B2B) { throw ArgonApiError.GraphQL(listOf("Access denied for metaobject")) }
        assertEquals("Stocked and ready to ship", content.banners.first().heading)
        assertEquals(3, content.rails.size)
    }

    @Test
    fun httpFailuresAreRethrownNotReplacedByTheCollections() {
        val e = assertThrows(ArgonApiError.Http::class.java) { content { throw ArgonApiError.Http(503) } }
        assertEquals(503, e.status)
    }

    @Test
    fun invalidResponsesAreRethrown() {
        assertThrows(ArgonApiError.Decoding::class.java) { content { throw ArgonApiError.Decoding("HomeScreen", "no data") } }
    }

    @Test
    fun aFailingCollectionsQueryFailsTheHomeEvenWithItsOwnSections() {
        val e = assertThrows(ArgonApiError.Http::class.java) { content(fallback = { throw ArgonApiError.Http(500) }) { api.homeScreen() } }
        assertEquals("HTTP 500", e.message)
    }

    @Test
    fun aStoreWithNothingToSellKeepsTheBanners() {
        val content = content(fallback = { emptyList() }) { emptyList() }
        assertTrue(content.isEmpty)
        assertEquals(3, content.banners.size)
    }

    @Test
    fun viewAllOpensTheRailsCollectionElseTheWholeCatalogue() {
        val collections = content { emptyList() }
        assertEquals("a rail made from a collection", Route.Collection("women"), collections.routeOf(collections.rails[1]))
        val own = content { api.homeScreen() }
        assertEquals("the store's own rail names no collection", Route.Collection("all"), own.routeOf(own.rails[0]))
    }

    @Test
    fun aRailWithoutAHeadingStillHasATitle() {
        assertEquals("Featured", Section.Products(null, "carousel", emptyList()).title)
        assertEquals("Featured", Section.Products(" ", "carousel", emptyList()).title)
        assertEquals("New in", Section.Products("New in", "carousel", emptyList()).title)
    }

    @Test
    fun theHeroLeavesTheSecondBannerForTheCard() {
        val banners = content { emptyList() }.banners
        assertEquals(listOf(banners[0], banners[2]), heroBanners(banners))
        assertEquals("a lone banner is the hero", banners.take(1), heroBanners(banners.take(1)))
        assertTrue(heroBanners(emptyList()).isEmpty())
    }
}
