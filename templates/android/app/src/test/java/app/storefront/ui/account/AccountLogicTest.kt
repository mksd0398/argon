package app.storefront.ui.account

import app.storefront.data.Customer
import app.storefront.data.CustomerAccountApi
import app.storefront.data.CustomerAddress
import app.storefront.data.CustomerAddressInput
import app.storefront.data.CustomerEmailAddress
import app.storefront.data.Money
import app.storefront.data.StoreCreditAccount
import app.storefront.data.fixture
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountLogicTest {
    // the contract fixtures: the sample account
    private val account = CustomerAccountApi({ name, _ -> fixture(name) })
    private val addresses = runBlocking { account.addresses().items }

    // The avatar and the name

    @Test
    fun initialsAreTheFirstLetterOfEachName() {
        assertEquals("AL", initials("Ada", "Lovelace", "ada@example.com"))
        assertEquals("AL", initials(" ada ", "lovelace", null))
        assertEquals("one name", "A", initials("Ada", null, "x@example.com"))
        assertEquals("L", initials("", "Lovelace", null))
    }

    @Test
    fun withoutANameTheEmailGivesTheInitialAndWithNeitherThereIsNone() {
        assertEquals("G", initials(null, null, "grace@example.com"))
        assertEquals("G", initials(" ", "", "grace@example.com"))
        assertNull(initials(null, null, null))
        assertNull(initials("", "", " "))
        assertNull("a name that starts with a symbol gives no letter", initials("-", null, null))
    }

    @Test
    fun aCustomerGoesByTheirNameThenTheDisplayNameThenTheEmail() {
        val email = CustomerEmailAddress("ada@example.com")
        assertEquals("Ada Lovelace", accountName(Customer("c", "Ada", "Lovelace", "Ada L.", emailAddress = email)))
        assertEquals("ada@example.com", accountName(Customer("c", displayName = "ada@example.com", emailAddress = email)))
        assertEquals("ada@example.com", accountName(Customer("c", " ", null, emailAddress = email)))
        assertNull("a customer with nothing to go by", accountName(Customer("c")))
        assertEquals("the sample customer", "Ada Lovelace", accountName(runBlocking { account.customer() }))
    }

    // Email offers and store credit

    @Test
    fun emailOffersAreOnWhenSubscribedOrWaitingForConfirmation() {
        assertTrue(isSubscribed("SUBSCRIBED"))
        assertTrue(isSubscribed("PENDING"))
        assertFalse(isSubscribed("UNSUBSCRIBED"))
        assertFalse(isSubscribed("NOT_SUBSCRIBED"))
        assertFalse(isSubscribed(null))
    }

    @Test
    fun storeCreditShowsOnlyBalancesAboveZero() {
        val accounts = listOf(
            StoreCreditAccount("a", Money("25.0", "CAD")),
            StoreCreditAccount("b", Money("0.0", "USD")),
            StoreCreditAccount("c", Money("n/a", "EUR")),
        )
        assertEquals(listOf(Money("25.0", "CAD")), creditBalances(accounts))
        assertEquals(emptyList<Money>(), creditBalances(emptyList()))
        assertEquals("the sample account has credit", listOf(Money("25.0", "CAD")), creditBalances(runBlocking { account.storeCredit() }))
        assertFalse((null as Money?).isPositive())
    }

    // Addresses

    @Test
    fun anAddressReadsAsShopifyFormatsItElseFromItsParts() {
        assertEquals(listOf("Ada Lovelace", "150 Elgin St", "Suite 400", "Ottawa ON K2P 1L4", "Canada"), addressLines(addresses[0]))
        val bare = CustomerAddress("a", firstName = "Ada", address1 = "1 Front St W", city = "Toronto", province = "Ontario", zip = "M5J 2X5", countryCode = "CA")
        assertEquals(listOf("Ada", "1 Front St W", "Toronto Ontario M5J 2X5", "CA"), addressLines(bare))
        assertEquals(emptyList<String>(), addressLines(CustomerAddress("a")))
    }

    @Test
    fun theFormNeedsAnAddressACityAndACountry() {
        assertEquals(
            mapOf(AddressField.Address1 to "Enter an address", AddressField.City to "Enter a city", AddressField.Country to "Choose a country"),
            AddressForm(firstName = "Ada", address1 = "  ", countryCode = "").errors(),
        )
        assertEquals(mapOf(AddressField.City to "Enter a city"), AddressForm(address1 = "1 Front St W", countryCode = "CA").errors())
        assertEquals(emptyMap<AddressField, String>(), AddressForm(address1 = "1 Front St W", city = "Toronto", countryCode = "CA").errors())
    }

    @Test
    fun aNewAddressLeavesOutWhatWasLeftEmpty() {
        val form = AddressForm(
            firstName = " Ada ", lastName = "Lovelace", address1 = "1 Front St W", city = "Toronto", zoneCode = "on", zip = " M5J 2X5 ",
            countryCode = "ca", phone = "+1 (613) 555-0123", isDefault = true,
        )
        assertEquals(
            CustomerAddressInput(
                firstName = "Ada", lastName = "Lovelace", company = null, address1 = "1 Front St W", address2 = null, city = "Toronto",
                zoneCode = "ON", zip = "M5J 2X5", countryCode = "CA", phoneNumber = "+16135550123",
            ),
            form.toInput(),
        )
    }

    @Test
    fun anEditSendsAClearedFieldEmptySoItIsNotKept() {
        val original = addresses[0] // has "Suite 400" and a phone number, no company
        val form = AddressForm.of(original).copy(address2 = "", phone = " ", city = "Gatineau")
        val input = form.toInput(original)
        assertEquals("cleared: sent empty", "", input.address2)
        assertEquals("", input.phoneNumber)
        assertNull("was empty and still is: left out", input.company)
        assertEquals("Gatineau", input.city)
        assertEquals("150 Elgin St", input.address1)
        assertEquals("CA", input.countryCode)
    }

    @Test
    fun theFormStartsFromTheAddressBeingEdited() {
        assertEquals(
            AddressForm(
                firstName = "Ada", lastName = "Lovelace", company = "", address1 = "150 Elgin St", address2 = "Suite 400", city = "Ottawa",
                zoneCode = "ON", zip = "K2P 1L4", countryCode = "CA", phone = "+16135550123", isDefault = true,
            ),
            AddressForm.of(addresses[0]),
        )
        assertFalse("the second address isn't the default", AddressForm.of(addresses[1]).isDefault)
        assertEquals(AddressForm(), AddressForm.of(null))
        assertEquals("an unchanged form changes nothing it had", "Suite 400", AddressForm.of(addresses[0]).toInput(addresses[0]).address2)
    }
}
