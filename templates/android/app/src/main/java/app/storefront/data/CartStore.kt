package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Shopify refused a cart change (a `userErrors` entry); the message is Shopify's, meant for the shopper. */
class CartException(message: String) : Exception(message)

/**
 * The shopper's cart through the Storefront Cart API. Only the cart id is kept on the device; [cart] is whatever the last
 * response said. [query] runs a named GraphQL operation and returns its `data`; [accessToken] is the signed-in
 * customer's token (null when signed out), attached to the cart before checkout.
 */
class CartStore(
    private val query: suspend (String, JsonObject) -> JsonObject,
    private val prefs: DataStore<Preferences>,
    private val accessToken: suspend () -> String? = { null },
) {
    private val idKey = stringPreferencesKey("cartId")
    private val state = MutableStateFlow<Cart?>(null)

    // One change at a time: two quick taps must not create two carts or interleave line updates.
    private val lock = Mutex()

    /** Null while there is no cart (none yet, not loaded yet, expired, or checked out). */
    val cart: StateFlow<Cart?> = state

    /** Fetches the stored cart. A cart Shopify no longer has (expired, completed) is forgotten without an error. */
    suspend fun load() {
        lock.withLock {
            val id = currentId() ?: return
            val found = query("Cart", buildJsonObject { put("id", id) }).obj("cart")
            if (found == null) forget() else state.value = parseCart(found)
        }
    }

    suspend fun add(variantId: String, quantity: Int) {
        lock.withLock {
            val lines = JsonArray(listOf(buildJsonObject { put("merchandiseId", variantId); put("quantity", quantity) }))
            change("CartLinesAdd", "lines", lines)
                ?: send("CartCreate", buildJsonObject { put("input", buildJsonObject { put("lines", lines) }) })
        }
    }

    /** Sets the quantity of a line; 0 (or less) removes it. */
    suspend fun update(lineId: String, quantity: Int) {
        lock.withLock {
            if (quantity <= 0) {
                removeLine(lineId)
            } else {
                change("CartLinesUpdate", "lines", JsonArray(listOf(buildJsonObject { put("id", lineId); put("quantity", quantity) })))
            }
        }
    }

    suspend fun remove(lineId: String) {
        lock.withLock { removeLine(lineId) }
    }

    /** The URL to hand to Checkout Kit, with the signed-in customer attached to the cart first. Null without a cart. */
    suspend fun checkoutUrl(): String? = lock.withLock {
        val current = state.value ?: return null
        val token = accessToken() ?: return current.checkoutUrl
        change("CartBuyerIdentityUpdate", "buyerIdentity", buildJsonObject { put("customerAccessToken", token) })?.checkoutUrl
    }

    /** The order was placed: the cart is spent, so the next add starts a new one. */
    suspend fun completed() {
        lock.withLock { forget() }
    }

    private suspend fun removeLine(lineId: String) {
        change("CartLinesRemove", "lineIds", JsonArray(listOf(JsonPrimitive(lineId))))
    }

    private suspend fun currentId(): String? = state.value?.id ?: prefs.safeData().first()[idKey]

    /** Runs a mutation on the current cart; null (nothing run) when there is no cart. */
    private suspend fun change(name: String, key: String, value: JsonElement): Cart? {
        val id = currentId() ?: return null
        return send(name, buildJsonObject { put("cartId", id); put(key, value) })
    }

    /** Runs mutation [name], keeps the cart it returns (even beside userErrors), and throws the first user error. */
    private suspend fun send(name: String, variables: JsonObject): Cart {
        val payload = query(name, variables).obj(name.replaceFirstChar { it.lowercase() })
            ?: throw StorefrontException(listOf("Invalid response"), null)
        val returned = payload.obj("cart")?.let(::parseCart)
        if (returned != null) {
            if (returned.id != state.value?.id) saveId(returned.id)
            state.value = returned
        }
        payload.objects("userErrors").firstOrNull()?.let { throw CartException(it.str("message") ?: "The cart could not be updated") }
        return returned ?: throw CartException("The cart is unavailable")
    }

    private suspend fun forget() {
        state.value = null
        saveId(null)
    }

    // ponytail: a failed write (IOException) only costs the cart across an app restart: the id stays in memory for this run.
    // A mutation that fails because the cart expired mid-session keeps failing until the next load() drops the id.
    private suspend fun saveId(id: String?) {
        try {
            prefs.edit { if (id == null) it.remove(idKey) else it[idKey] = id }
        } catch (e: IOException) {
            // see above
        }
    }
}
