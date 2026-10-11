package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BuyerStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private val ottawa = "gid://shopify/CompanyLocation/9200001"
    private val toronto = "gid://shopify/CompanyLocation/9200002"

    /** What was asked of the Storefront API, in order: operation name and variables. Every operation answers its fixture. */
    private val calls = mutableListOf<Pair<String, JsonObject>>()
    private val names get() = calls.map { it.first }
    private val storefront = StorefrontApi({ name, vars -> calls += name to vars; fixture(name) })

    /** The fixture customer: a contact of Analytical Engines Ltd, which has an Ottawa and a Toronto location. */
    private val fixtureContacts = runBlocking { CustomerAccountApi { name, _ -> fixture(name) }.companies() }

    private var token: String? = "tok"
    private var contacts: suspend () -> List<CompanyContact> = { fixtureContacts }
    private var companyCalls = 0

    private fun prefs(name: String): DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { File(tmp.root, "$name.preferences_pb") }
    private val buyerPrefs by lazy { prefs("buyer") }
    private val cart by lazy { CartStore(storefront, prefs("cart"), accessToken = { token }) }

    private fun store(sample: Boolean = false) =
        BuyerStore(storefront, cart, buyerPrefs, accessToken = { token }, companies = { companyCalls++; contacts() }, sample = { sample })

    private val JsonObject.identity get() = getValue("buyerIdentity").toString()

    @Test
    fun aCompanyContactShopsAsTheirCompany() = runBlocking {
        cart.add("v1", 1)
        val s = store()
        assertNull("retail until the company is known", s.company.value)
        s.refresh()

        val company = s.company.value!!
        assertEquals("gid://shopify/CompanyContact/9000001", company.contactId)
        assertEquals("Analytical Engines Ltd", company.companyName)
        assertEquals(listOf("Ottawa head office", "Toronto warehouse"), company.locations.map { it.name })
        assertEquals("the first location until one is chosen", ottawa, company.locationId)
        assertEquals("Ottawa head office", company.location?.name)

        assertEquals(Buyer("tok", ottawa), storefront.buyer)
        // the cart that was there is now the company's, and Storefront calls carry the buyer
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate"), names)
        assertEquals("""{"customerAccessToken":"tok","companyLocationId":"$ottawa"}""", calls[1].second.identity)
        assertEquals("""{"customerAccessToken":"tok","companyLocationId":"$ottawa"}""", calls[1].second["buyer"].toString())
    }

    @Test
    fun aNewCartIsCreatedForTheCompany() = runBlocking {
        store().refresh()
        assertTrue("no cart yet: nothing to attach", calls.isEmpty())
        cart.add("v1", 1)
        assertEquals("""{"customerAccessToken":"tok","companyLocationId":"$ottawa"}""", calls.single().second.getValue("input").let { (it as JsonObject).identity })
    }

    @Test
    fun theChosenLocationIsRememberedWhileItIsStillOffered() = runBlocking {
        val s = store()
        s.refresh()
        s.select(toronto)
        assertEquals(toronto, s.company.value?.locationId)
        assertEquals(Buyer("tok", toronto), storefront.buyer)

        // the next launch
        val next = store()
        next.refresh()
        assertEquals(toronto, next.company.value?.locationId)

        // the customer no longer buys for Toronto: back to the first one offered
        contacts = { fixtureContacts.map { it.copy(company = it.company.copy(locations = it.company.locations.take(1))) } }
        next.refresh()
        assertEquals(ottawa, next.company.value?.locationId)
        assertEquals(Buyer("tok", ottawa), storefront.buyer)
    }

    @Test
    fun theCartIsAttachedOnlyWhenTheBuyerChanges() = runBlocking {
        cart.add("v1", 1)
        val s = store()
        s.refresh()
        s.refresh()
        s.select(ottawa)
        assertEquals("the same buyer: nothing new to tell the cart", listOf("CartCreate", "CartBuyerIdentityUpdate"), names)
        s.select(toronto)
        assertEquals(listOf("CartCreate", "CartBuyerIdentityUpdate", "CartBuyerIdentityUpdate"), names)
        assertEquals("""{"customerAccessToken":"tok","companyLocationId":"$toronto"}""", calls.last().second.identity)
    }

    @Test
    fun aRetailCustomerAndASignedOutShopperStayRetail() = runBlocking {
        val s = store()
        contacts = { emptyList() }
        s.refresh()
        assertNull(s.company.value)
        assertNull(storefront.buyer)

        // a contact whose company offers no location has nothing to buy for
        contacts = { fixtureContacts.map { it.copy(company = it.company.copy(locations = emptyList())) } }
        s.refresh()
        assertNull(s.company.value)

        token = null
        contacts = { fixtureContacts }
        companyCalls = 0
        s.refresh()
        assertNull(s.company.value)
        assertEquals("signed out: the Customer Account API isn't asked", 0, companyCalls)
    }

    @Test
    fun aRefreshedTokenReplacesTheBuyers() = runBlocking {
        cart.add("v1", 1)
        val s = store()
        s.refresh()
        token = "tok2"
        s.refresh()
        assertEquals(Buyer("tok2", ottawa), storefront.buyer)
        assertEquals("""{"customerAccessToken":"tok2","companyLocationId":"$ottawa"}""", calls.last().second.identity)
    }

    @Test
    fun aFailureLeavesTheRetailContextAndIsNotThrown() = runBlocking {
        val s = store()
        s.refresh()
        assertEquals(Buyer("tok", ottawa), storefront.buyer)

        contacts = { throw ArgonApiError.Http(503) }
        s.refresh()
        assertNull(s.company.value)
        assertNull(storefront.buyer)

        // it recovers with the next refresh, and a preferences file that can't be written only loses the choice at restart
        contacts = { fixtureContacts }
        s.refresh()
        assertEquals(ottawa, s.company.value?.locationId)
        val broken = BuyerStore(storefront, cart, failingStore(IOException("disk")), accessToken = { token }, companies = contacts)
        broken.select(toronto)
        assertEquals(toronto, broken.company.value?.locationId)
        assertEquals(Buyer("tok", toronto), storefront.buyer)
    }

    @Test
    fun clearGoesBackToRetailAndKeepsTheLocationForTheNextSignIn() = runBlocking {
        val s = store()
        s.refresh()
        s.select(toronto)
        s.clear()
        assertNull(s.company.value)
        assertNull(storefront.buyer)

        s.refresh()
        assertEquals(toronto, s.company.value?.locationId)
        assertEquals(Buyer("tok", toronto), storefront.buyer)
    }

    @Test
    fun theSampleAccountShowsItsCompanyButShopsRetail() = runBlocking {
        token = null
        cart.add("v1", 1)
        val s = store(sample = true)
        s.refresh()
        assertEquals("Analytical Engines Ltd", s.company.value?.companyName)
        assertNull("no token: prices stay the store's own", storefront.buyer)
        assertEquals("the cart isn't touched", listOf("CartCreate"), names)
        s.select(toronto)
        assertEquals("Toronto warehouse", s.company.value?.location?.name)
    }
}
