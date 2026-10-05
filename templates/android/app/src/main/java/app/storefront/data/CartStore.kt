package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import java.util.logging.Level
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
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
open class CartException(message: String) : Exception(message)

/** A mutation that answered without a cart: the cart is gone, or the change was refused (a bad variant id). */
private class NoCart(message: String) : CartException(message)

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

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests (android.util.Log does not)
    private val log = Logger.getLogger("CartStore")
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
            val create: suspend () -> Cart = { send("CartCreate", buildJsonObject { put("input", buildJsonObject { put("lines", lines) }) }) }
            // a stored cart that has expired is replaced by a new one holding these lines
            change("CartLinesAdd", "lines", lines, ifGone = create) ?: create()
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

    /**
     * The URL to hand to Checkout Kit, with the signed-in customer attached to the cart first. Null without a cart.
     * Attaching the customer never blocks checkout: if it fails, the shopper checks out as a guest.
     */
    suspend fun checkoutUrl(): String? = lock.withLock {
        val current = state.value ?: return null
        try {
            val token = accessToken() ?: return current.checkoutUrl
            change("CartBuyerIdentityUpdate", "buyerIdentity", buildJsonObject { put("customerAccessToken", token) })?.checkoutUrl
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // the token provider threw, Shopify refused the token (CartException), or the request failed (StorefrontException, IO)
            log.log(Level.WARNING, "customer not attached to the cart; checking out as a guest", e)
            state.value?.checkoutUrl // null if the cart turned out to be gone
        }
    }

    /** The order was placed: the cart is spent, so the next add starts a new one. */
    suspend fun completed() {
        lock.withLock { forget() }
    }

    private suspend fun removeLine(lineId: String) {
        change("CartLinesRemove", "lineIds", JsonArray(listOf(JsonPrimitive(lineId))))
    }

    private suspend fun currentId(): String? = state.value?.id ?: prefs.safeData().first()[idKey]

    /**
     * Runs a mutation on the current cart; null (nothing run) when there is no cart. When no cart comes back, the cart lookup
     * tells a cart Shopify no longer has (forgotten, then [ifGone] runs if given) from a change it refused (the error is thrown).
     */
    private suspend fun change(name: String, key: String, value: JsonElement, ifGone: (suspend () -> Cart)? = null): Cart? {
        val id = currentId() ?: return null
        return try {
            send(name, buildJsonObject { put("cartId", id); put(key, value) })
        } catch (e: NoCart) {
            if (query("Cart", buildJsonObject { put("id", id) }).obj("cart") != null) throw e
            forget()
            ifGone?.invoke() ?: throw e
        }
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
        val error = payload.objects("userErrors").firstOrNull()?.let { it.str("message") ?: "The cart could not be updated" }
        if (returned == null) throw NoCart(error ?: "The cart is unavailable")
        if (error != null) throw CartException(error)
        return returned
    }

    private suspend fun forget() {
        state.value = null
        saveId(null)
    }

    // ponytail: a failed write (IOException) only costs the cart across an app restart: the id stays in memory for this run.
    private suspend fun saveId(id: String?) {
        try {
            prefs.edit { if (id == null) it.remove(idKey) else it[idKey] = id }
        } catch (e: IOException) {
            // see above
        }
    }
}
