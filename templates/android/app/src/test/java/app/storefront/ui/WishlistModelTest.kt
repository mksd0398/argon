package app.storefront.ui

import app.storefront.data.Money
import app.storefront.data.ProductCard
import app.storefront.data.StorefrontException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WishlistModelTest {
    private fun card(id: String) = ProductCard(id, "h-$id", "T-$id", true, null, Money("1.00", "USD"), null)

    @Test
    fun cardsFollowTheWishlistOrderNotTheOrderTheStoreAnswers() = runBlocking {
        val m = WishlistModel { ids -> ids.reversed().map(::card) }
        val ids = listOf("b", "a", "c")
        m.sync(ids)
        assertEquals(ids, m.cards(ids).map { it.id })
        assertFalse(m.pending(ids))
    }

    @Test
    fun deletedProductsAreDroppedAndNotAskedAgain() = runBlocking {
        val asked = mutableListOf<List<String>>()
        val m = WishlistModel { ids -> asked += ids; ids.filter { it != "gone" }.map(::card) }
        m.sync(listOf("a", "gone"))
        assertEquals(listOf("a"), m.cards(listOf("a", "gone")).map { it.id })
        assertFalse(m.pending(listOf("a", "gone")))
        m.sync(listOf("new", "a", "gone")) // only the unseen id is requested
        assertEquals(listOf(listOf("a", "gone"), listOf("new")), asked)
    }

    @Test
    fun aFailureShowsItsMessageUntilARetrySucceeds() = runBlocking {
        var fail = true
        val m = WishlistModel { ids -> if (fail) throw StorefrontException(listOf("HTTP 503"), 503) else ids.map(::card) }
        m.sync(listOf("a"))
        assertEquals("HTTP 503", m.error)
        assertTrue(m.pending(listOf("a")))
        fail = false
        m.sync(listOf("a"))
        assertNull(m.error)
        assertEquals(listOf("a"), m.cards(listOf("a")).map { it.id })
    }

    @Test
    fun aLongWishlistIsRequestedInBatchesOfTheApiLimit() = runBlocking {
        val sizes = mutableListOf<Int>()
        val m = WishlistModel { ids -> sizes += ids.size; ids.map(::card) }
        m.sync((1..300).map { "p$it" })
        assertEquals(listOf(250, 50), sizes)
    }
}
