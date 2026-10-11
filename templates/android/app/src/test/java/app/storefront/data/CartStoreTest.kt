package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder

class CartStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private val cartJson = fixture("Cart").getValue("cart").jsonObject
    private val cartId = cartJson.getValue("id").jsonPrimitive.content
    private val guestUrl = cartJson.getValue("checkoutUrl").jsonPrimitive.content
    private val lineId = "gid://shopify/CartLine/34639"

    /** What the store asked Shopify, in order: operation name and variables. */
    private val calls = mutableListOf<Pair<String, JsonObject>>()
    private val names get() = calls.map { it.first }

    private fun file() = File(tmp.root, "cart.preferences_pb")
    private fun disk(): DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file() }

    /** The app restarts: the old DataStore is closed (DataStore allows one per file), then the file is opened again. */
    private suspend fun restart(): DataStore<Preferences> {
        scope.coroutineContext[Job]!!.cancelAndJoin()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        return disk()
    }

    /** A mutation answer: `{<name>: {cart, userErrors}}`; the `Cart` query answers `{cart}`. */
    private fun answer(name: String, cart: JsonObject? = cartJson, vararg errors: String): JsonObject =
        if (name == "Cart") buildJsonObject { put("cart", cart ?: JsonNull) } else buildJsonObject {
            put(
                name.replaceFirstChar { it.lowercase() },
                buildJsonObject {
                    put("cart", cart ?: JsonNull)
                    put("userErrors", JsonArray(errors.map { buildJsonObject { put("message", it) } }))
                },
            )
        }

    private fun store(
        prefs: DataStore<Preferences> = disk(),
        token: String? = null,
        accessToken: suspend () -> String? = { token },
        reply: suspend (String) -> JsonObject = { answer(it) },
    ) = CartStore(StorefrontApi({ name, vars -> calls += name to vars; reply(name) }), prefs, accessToken)

    private val JsonObject.lines get() = getValue("lines").jsonArray.map { it.jsonObject }

    @Test
    fun addWithNoStoredCartCreatesOneAndRemembersIt() = runBlocking {
        store().add("gid://shopify/ProductVariant/1", 2)
        assertEquals(listOf("CartCreate"), names)
        val line = calls[0].second.getValue("input").jsonObject.lines.single()
        assertEquals("gid://shopify/ProductVariant/1", line.getValue("merchandiseId").jsonPrimitive.content)
        assertEquals(2, line.getValue("quantity").jsonPrimitive.content.toInt())

        // a new process: the id was persisted, and it is what load() asks for
        calls.clear()
        val again = store(restart())
        again.load()
        assertEquals(listOf("Cart"), names)
        assertEquals(cartId, calls[0].second.getValue("id").jsonPrimitive.content)
        assertEquals(3, again.cart.value?.totalQuantity)
    }

    @Test
    fun addToAnExistingCartUsesLinesAdd() = runBlocking {
        val s = store()
        s.add("v1", 1)
        s.add("v2", 3)
        assertEquals(listOf("CartCreate", "CartLinesAdd"), names)
        assertEquals(cartId, calls[1].second.getValue("cartId").jsonPrimitive.content)
        assertEquals(3, calls[1].second.lines.single().getValue("quantity").jsonPrimitive.content.toInt())
        assertEquals(cartId, s.cart.value?.id)
    }

    @Test
    fun addOnASellingPlanNamesThePlanAndAOneTimePurchaseNamesNone() = runBlocking {
        val s = store()
        s.add("v1", 1)
        s.add("v2", 2, sellingPlanId = "gid://shopify/SellingPlan/1")
        assertNull(calls[0].second.getValue("input").jsonObject.lines.single()["sellingPlanId"])
        assertEquals("gid://shopify/SellingPlan/1", calls[1].second.lines.single().getValue("sellingPlanId").jsonPrimitive.content)
    }

    @Test
    fun anExpiredCartIsDroppedWithoutAnError() = runBlocking {
        store().add("v1", 1)
        calls.clear()

        val s = store(restart()) { if (it == "Cart") answer(it, cart = null) else answer(it) }
        s.load()
        assertNull(s.cart.value)
        assertEquals(listOf("Cart"), names)

        // the id is gone for good: the next add creates a cart
        s.add("v1", 1)
        assertEquals(listOf("Cart", "CartCreate"), names)

        // ...and a later start has nothing to look up once the cart is completed
        s.completed()
        calls.clear()
        store(restart()).load()
        assertEquals(emptyList<String>(), names)
    }

    @Test
    fun checkoutUrlAttachesTheBuyerWhenSignedIn() = runBlocking {
        val signedIn = JsonObject(cartJson + ("checkoutUrl" to JsonPrimitive("https://shop.test/checkout?buyer=1")))
        val s = store(token = "tok") { if (it == "CartBuyerIdentityUpdate") answer(it, signedIn) else answer(it) }
        s.add("v1", 1)
        assertEquals("https://shop.test/checkout?buyer=1", s.checkoutUrl())
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate"), names)
        val vars = calls[1].second
        assertEquals(cartId, vars.getValue("cartId").jsonPrimitive.content)
        assertEquals("tok", vars.getValue("buyerIdentity").jsonObject.getValue("customerAccessToken").jsonPrimitive.content)
    }

    @Test
    fun checkoutUrlSkipsTheBuyerWhenSignedOut() = runBlocking {
        val s = store(token = null)
        assertNull("no cart, no url", s.checkoutUrl())
        s.add("v1", 1)
        assertEquals(guestUrl, s.checkoutUrl())
        assertEquals(listOf("CartCreate"), names)
    }

    @Test
    fun checkoutFallsBackToTheGuestUrlWhenTheBuyerCantBeAttached() = runBlocking {
        var tokenFailure: Exception? = IOException("token endpoint unreachable")
        var identityReply: () -> JsonObject = { answer("CartBuyerIdentityUpdate", cartJson, "Customer access token is invalid") }
        val s = store(accessToken = { tokenFailure?.let { throw it }; "tok" }) {
            if (it == "CartBuyerIdentityUpdate") identityReply() else answer(it)
        }
        s.add("v1", 1)
        val guest = guestUrl

        // the token provider throws: no identity update is tried
        assertEquals(guest, s.checkoutUrl())
        assertEquals(listOf("CartCreate"), names)

        // Shopify refuses the token (a userError), then the request itself fails
        tokenFailure = null
        assertEquals(guest, s.checkoutUrl())
        identityReply = { throw ArgonApiError.GraphQL(listOf("Throttled")) }
        assertEquals(guest, s.checkoutUrl())
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"), names)
        assertEquals("the cart is kept", cartId, s.cart.value?.id)
    }

    // B2B

    private val location = "gid://shopify/CompanyLocation/1"
    private val JsonObject.identity get() = getValue("buyerIdentity").toString()

    @Test
    fun aCompanysCartIsItsFromTheFirstLineToCheckout() = runBlocking {
        val s = store(token = "tok")
        s.setBuyer(location)
        assertEquals("no cart yet: nothing to attach", emptyList<String>(), names)

        s.add("v1", 1)
        s.checkoutUrl()
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate"), names)
        val company = """{"customerAccessToken":"tok","companyLocationId":"$location"}"""
        assertEquals(company, calls[0].second.getValue("input").jsonObject.identity)
        assertEquals(company, calls[1].second.identity)
    }

    @Test
    fun setBuyerAttachesTheCurrentCartToTheCompany() = runBlocking {
        val s = store(token = "tok")
        s.add("v1", 1)
        assertNull("a retail cart is created without a buyer", calls[0].second.getValue("input").jsonObject["buyerIdentity"])

        s.setBuyer(location)
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate"), names)
        assertEquals(cartId, calls[1].second.getValue("cartId").jsonPrimitive.content)
        assertEquals("""{"customerAccessToken":"tok","companyLocationId":"$location"}""", calls[1].second.identity)

        // back to retail: nothing is sent, and the customer alone is attached at checkout
        s.setBuyer(null)
        s.checkoutUrl()
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"), names)
        assertEquals("""{"customerAccessToken":"tok"}""", calls[2].second.identity)
    }

    @Test
    fun aSignedOutShopperHasNoCompanyCart() = runBlocking {
        val s = store(token = null)
        s.add("v1", 1)
        s.setBuyer(location)
        s.completed()
        s.add("v1", 1)
        assertEquals(listOf("CartCreate", "CartCreate"), names)
        assertNull(calls[1].second.getValue("input").jsonObject["buyerIdentity"])
    }

    @Test
    fun userErrorsAreThrown() = runBlocking {
        val s = store { answer(it, cart = if (it == "CartCreate") null else cartJson, "Not enough stock") }
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { s.add("v1", 99) } }
        assertEquals("Not enough stock", e.message)
        assertNull(s.cart.value)
    }

    @Test
    fun userErrorsOnAnUpdateKeepTheReturnedCart() = runBlocking {
        val s = store { if (it == "CartLinesUpdate") answer(it, cartJson, "Not enough stock") else answer(it) }
        s.add("v1", 1)
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { s.update(lineId, 50) } }
        assertEquals("Not enough stock", e.message)
        assertNotNull(s.cart.value)
    }

    @Test
    fun aDeadStoredCartIsReplacedOnAdd() = runBlocking {
        store().add("v1", 1)
        calls.clear()

        // a cold start whose load() never ran (offline): the id is stored, but Shopify no longer has the cart
        val s = store(restart()) {
            when (it) {
                "CartLinesAdd" -> answer(it, cart = null, "The specified cart does not exist")
                "Cart" -> answer(it, cart = null)
                else -> answer(it)
            }
        }
        s.add("gid://shopify/ProductVariant/9", 2)
        assertEquals(listOf("CartLinesAdd", "Cart", "CartCreate"), names)
        val line = calls[2].second.getValue("input").jsonObject.lines.single()
        assertEquals("gid://shopify/ProductVariant/9", line.getValue("merchandiseId").jsonPrimitive.content)
        assertEquals(2, line.getValue("quantity").jsonPrimitive.content.toInt())
        assertEquals(cartId, s.cart.value?.id)
    }

    @Test
    fun aRefusedAddOnALiveCartKeepsTheCart() = runBlocking {
        val s = store { if (it == "CartLinesAdd") answer(it, cart = null, "The merchandise does not exist") else answer(it) }
        s.add("v1", 1)
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { s.add("bad", 1) } }
        assertEquals("The merchandise does not exist", e.message)
        // the lookup found the cart, so it was not replaced
        assertEquals(listOf("CartCreate", "CartLinesAdd", "Cart"), names)
        assertEquals(cartId, s.cart.value?.id)
    }

    @Test
    fun anUpdateOnAGoneCartForgetsItAndSaysSo() = runBlocking {
        val s = store {
            when (it) {
                "CartLinesUpdate" -> answer(it, cart = null, "The specified cart does not exist")
                "Cart" -> answer(it, cart = null)
                else -> answer(it)
            }
        }
        s.add("v1", 1)
        val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { s.update(lineId, 2) } }
        assertEquals("The specified cart does not exist", e.message)
        assertNull(s.cart.value)
        assertEquals(listOf("CartCreate", "CartLinesUpdate", "Cart"), names)
    }

    @Test
    fun updateSetsTheQuantityAndZeroRemovesTheLine() = runBlocking {
        val s = store()
        s.add("v1", 1)
        s.update(lineId, 2)
        s.update(lineId, 0)
        assertEquals(listOf("CartCreate", "CartLinesUpdate", "CartLinesRemove"), names)
        val line = calls[1].second.lines.single()
        assertEquals(lineId, line.getValue("id").jsonPrimitive.content)
        assertEquals(2, line.getValue("quantity").jsonPrimitive.content.toInt())
        assertEquals(listOf(lineId), calls[2].second.getValue("lineIds").jsonArray.map { it.jsonPrimitive.content })
        s.remove(lineId)
        assertEquals("CartLinesRemove", names.last())
    }

    @Test
    fun rapidAddsShareOneCart() = runBlocking {
        val s = store { if (it == "CartCreate") delay(100); answer(it) }
        List(3) { async(Dispatchers.Default) { s.add("v1", 1) } }.awaitAll()
        assertEquals(listOf("CartCreate", "CartLinesAdd", "CartLinesAdd"), names)
    }

    @Test
    fun completedForgetsTheCart() = runBlocking {
        val s = store()
        s.add("v1", 1)
        s.completed()
        assertNull(s.cart.value)
        s.add("v1", 1)
        assertEquals(listOf("CartCreate", "CartCreate"), names)
    }

    @Test
    fun unreadableStorageStillWorksForTheSession() = runBlocking {
        val s = store(prefs = failingStore(IOException("disk")))
        s.load()
        assertNull(s.cart.value)
        s.add("v1", 1) // the id can't be saved, but the cart is usable until the app closes
        assertEquals(cartId, s.cart.value?.id)
        s.add("v2", 1)
        assertEquals(listOf("CartCreate", "CartLinesAdd"), names)
    }
}
