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

/**
 * The shopper's cart through the Storefront Cart API. Only the cart id is kept on the device; [cart] is whatever the last
 * response said. [accessToken] is the signed-in customer's token (null when signed out), attached to the cart before
 * checkout. A change Shopify refuses throws [ArgonApiError.UserErrors]; its message is Shopify's, meant for the shopper.
 */
class CartStore(
    private val api: StorefrontApi,
    private val prefs: DataStore<Preferences>,
    private val accessToken: suspend () -> String? = { null },
) {
    private val idKey = stringPreferencesKey("cartId")

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests (android.util.Log does not)
    private val log = Logger.getLogger("CartStore")
    private val state = MutableStateFlow<Cart?>(null)

    // One change at a time: two quick taps must not create two carts or interleave line updates.
    private val lock = Mutex()

    // The company location the signed-in buyer purchases for (B2B); null: a retail cart.
    private var companyLocationId: String? = null

    /** Null while there is no cart (none yet, not loaded yet, expired, or checked out). */
    val cart: StateFlow<Cart?> = state

    /** Fetches the stored cart. A cart Shopify no longer has (expired, completed) is forgotten without an error. */
    suspend fun load() {
        lock.withLock {
            val id = currentId() ?: return
            val found = api.cart(id)
            if (found == null) forget() else state.value = found
        }
    }

    suspend fun add(variantId: String, quantity: Int) {
        lock.withLock {
            val lines = listOf(CartLineInput(variantId, quantity))
            val create: suspend () -> Cart = { keep { api.cartCreate(CartInput(lines = lines, buyerIdentity = newCartBuyer())) } }
            // a stored cart that has expired is replaced by a new one holding these lines
            change({ api.addLines(it, lines) }, ifGone = create) ?: create()
        }
    }

    /**
     * The company location the signed-in customer buys for ([BuyerStore]), or null for a retail shopper. It goes on the
     * cart with the customer's token, so its lines take the company's prices: now when there is a cart, with every new
     * cart, and before checkout. Null only forgets the location (signing out drops the cart itself).
     */
    suspend fun setBuyer(companyLocationId: String?) {
        lock.withLock {
            this.companyLocationId = companyLocationId
            if (companyLocationId == null || currentId() == null) return
            val token = accessToken() ?: return
            change({ api.updateBuyerIdentity(it, CartBuyerIdentityInput(customerAccessToken = token, companyLocationId = companyLocationId)) })
        }
    }

    /**
     * A company's cart starts with its buyer, or its first lines would show retail prices; anyone else is attached at
     * checkout (null). A token that can't be had now doesn't stop the add: checkout attaches the buyer again.
     */
    private suspend fun newCartBuyer(): CartBuyerIdentityInput? {
        val location = companyLocationId ?: return null
        val token = try {
            accessToken()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.log(Level.WARNING, "company buyer not attached to the new cart", e)
            null
        }
        return token?.let { CartBuyerIdentityInput(customerAccessToken = it, companyLocationId = location) }
    }

    /** Sets the quantity of a line; 0 (or less) removes it. */
    suspend fun update(lineId: String, quantity: Int) {
        lock.withLock {
            if (quantity <= 0) {
                removeLine(lineId)
            } else {
                change({ api.updateLines(it, listOf(CartLineUpdateInput(lineId, quantity))) })
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
            change({ api.updateBuyerIdentity(it, CartBuyerIdentityInput(customerAccessToken = token, companyLocationId = companyLocationId)) })?.checkoutUrl
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // the token provider threw, Shopify refused the token (UserErrors), or the request failed (another ArgonApiError)
            log.log(Level.WARNING, "customer not attached to the cart; checking out as a guest", e)
            state.value?.checkoutUrl // null if the cart turned out to be gone
        }
    }

    /** The order was placed: the cart is spent, so the next add starts a new one. */
    suspend fun completed() {
        lock.withLock { forget() }
    }

    private suspend fun removeLine(lineId: String) {
        change({ api.removeLines(it, listOf(lineId)) })
    }

    private suspend fun currentId(): String? = state.value?.id ?: prefs.safeData().first()[idKey]

    /**
     * Runs [mutation] on the current cart; null (nothing run) when there is no cart. When it is refused and no cart comes
     * back, the cart lookup tells a cart Shopify no longer has (forgotten, then [ifGone] runs if given) from a change it
     * refused (the error is rethrown).
     */
    private suspend fun change(mutation: suspend (cartId: String) -> Cart, ifGone: (suspend () -> Cart)? = null): Cart? {
        val id = currentId() ?: return null
        return try {
            keep { mutation(id) }
        } catch (e: ArgonApiError.UserErrors) {
            if (e.cart != null || api.cart(id) != null) throw e
            forget()
            ifGone?.invoke() ?: throw e
        }
    }

    /** Runs a cart mutation and keeps the cart it returns, also the one Shopify sends beside `userErrors` (then rethrown). */
    private suspend fun keep(mutation: suspend () -> Cart): Cart {
        val returned = try {
            mutation()
        } catch (e: ArgonApiError.UserErrors) {
            e.cart?.let { save(it) }
            throw e
        }
        save(returned)
        return returned
    }

    private suspend fun save(cart: Cart) {
        if (cart.id != state.value?.id) saveId(cart.id)
        state.value = cart
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
