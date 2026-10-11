package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** The company the signed-in customer buys for, and the location chosen among its [locations] ([locationId]). */
data class BuyerCompany(val contactId: String, val companyName: String, val locations: List<CompanyLocation>, val locationId: String) {
    /** The chosen location. */
    val location: CompanyLocation? get() = locations.firstOrNull { it.id == locationId }
}

/**
 * The B2B buyer: a signed-in customer who is a company's contact shops in that company's context, with its catalogue,
 * prices and quantity rules. [refresh] finds the company and puts the buyer on the Storefront API ([StorefrontApi.buyer])
 * and on the [cart]; anyone else (signed out, or not a company contact) is a retail shopper. The chosen location is kept
 * in [prefs]. [accessToken] is the customer's Customer Account API token (null when signed out), which the Storefront API
 * takes as it is (Shopify deprecated exchanging it for a Storefront customer token); [companies] lists the customer's
 * company contacts; [sample] says the sample account is on show, whose company is displayed without a buyer (it has no
 * token to send).
 *
 * A failure never reaches the shopper: it is logged, and the app stays in the retail context.
 * ponytail: the buyer's token is as fresh as the last [refresh] (sign-in, app start, back in the foreground, a token
 * change). An app kept in the foreground past the token's life keeps sending the old one. Upgrade: have the Storefront
 * transport ask for a valid token on every call.
 */
class BuyerStore(
    private val storefront: StorefrontApi,
    private val cart: CartStore,
    private val prefs: DataStore<Preferences>,
    private val accessToken: suspend () -> String?,
    private val companies: suspend () -> List<CompanyContact>,
    private val sample: () -> Boolean = { false },
) {
    private val locationKey = stringPreferencesKey("buyer.location")

    // java.util.logging: it reaches logcat on Android and also runs in JVM tests. Only exception classes are logged, never values.
    private val log = Logger.getLogger("BuyerStore")
    private val state = MutableStateFlow<BuyerCompany?>(null)

    // One change at a time: a refresh that a newer one overtakes must not apply its company last.
    private val lock = Mutex()

    /** Null for a retail shopper. */
    val company: StateFlow<BuyerCompany?> = state

    /**
     * Finds the customer's company and applies it, at the stored location while the company still offers it, else its
     * first: after sign-in, at start with a session, and when the token changes (the Storefront API and the cart hold the
     * token itself). Signed out, or without a company: retail.
     */
    suspend fun refresh() = applyCompany(chosen = null)

    /** Buys for another of the company's locations from now on (remembered across launches). */
    suspend fun select(locationId: String) {
        // ponytail: a failed write (IOException) only costs the choice across an app restart
        try {
            prefs.edit { it[locationKey] = locationId }
        } catch (e: IOException) {
            // see above
        }
        applyCompany(chosen = locationId)
    }

    /** Signed out: back to a retail shopper. The chosen location stays for the next sign-in. */
    suspend fun clear() = lock.withLock { retail() }

    private suspend fun applyCompany(chosen: String?) = lock.withLock {
        try {
            val token = accessToken()
            if (token == null && !sample()) return@withLock retail()
            // ponytail: the first company that has somewhere to buy for. A contact of several companies can't switch
            // between them: add a company picker beside the location one when a store needs it.
            val contact = companies().firstOrNull { it.company.locations.isNotEmpty() } ?: return@withLock retail()
            val stored = chosen ?: prefs.safeData().first()[locationKey]
            val locations = contact.company.locations
            val locationId = (locations.firstOrNull { it.id == stored } ?: locations.first()).id
            state.value = BuyerCompany(contact.id, contact.company.name, locations, locationId)
            val buyer = Buyer(token ?: return@withLock, locationId)
            if (storefront.buyer == buyer) return@withLock
            storefront.buyer = buyer // drops the session cache: the shop's prices are the company's from here
            cart.setBuyer(locationId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log.warning("company not applied, shopping as a retail customer (${e.javaClass.name})")
            retail()
        }
    }

    /** With the lock held. */
    private suspend fun retail() {
        state.value = null
        if (storefront.buyer != null) storefront.buyer = null
        // null only forgets the location: nothing is sent, so nothing can fail
        cart.setBuyer(null)
    }
}
