package app.storefront.ui.account

import app.storefront.data.Customer
import app.storefront.data.CustomerAddress
import app.storefront.data.CustomerAddressInput
import app.storefront.data.Money
import app.storefront.data.StoreCreditAccount

// The account pages' rules, kept free of UI so they can be tested (and read side by side with iOS).

/**
 * The avatar's letters: the first of each name ("AL"), of the one name there is ("A"), else of the email. Null when there
 * is nothing to go by (the avatar then shows its person icon).
 */
fun initials(firstName: String?, lastName: String?, email: String?): String? {
    fun first(text: String?) = text?.trim()?.firstOrNull()?.takeIf { it.isLetterOrDigit() }?.uppercase()
    return listOfNotNull(first(firstName), first(lastName)).joinToString("").ifEmpty { first(email) }
}

/** What to call the customer: their name, else Shopify's display name (often the email), else the email; null with none of them. */
fun accountName(customer: Customer): String? =
    listOf(customer.name, customer.displayName, customer.email.orEmpty()).map { it.trim() }.firstOrNull { it.isNotEmpty() }

/** Whether the "Email offers" switch is on: subscribed, or waiting for the customer to confirm by email (PENDING). */
fun isSubscribed(marketingState: String?): Boolean = marketingState == "SUBSCRIBED" || marketingState == "PENDING"

/** An amount above zero (Shopify sends "0.0" for none). */
fun Money?.isPositive(): Boolean = this?.amount?.toBigDecimalOrNull()?.signum() == 1

/** The store credit there is to spend: the balances above zero, one per currency. */
fun creditBalances(accounts: List<StoreCreditAccount>): List<Money> = accounts.map { it.balance }.filter { it.isPositive() }

/** An address as lines: Shopify's own formatting, or its parts when that is missing. */
fun addressLines(address: CustomerAddress): List<String> = address.formatted.ifEmpty {
    listOf(
        listOfNotNull(address.firstName, address.lastName).joinToString(" "),
        address.company.orEmpty(),
        address.address1.orEmpty(),
        address.address2.orEmpty(),
        listOfNotNull(address.city, address.zoneCode ?: address.province, address.zip).joinToString(" "),
        address.country ?: address.countryCode.orEmpty(),
    ).map { it.trim() }.filter { it.isNotEmpty() }
}

/** The fields the address form checks itself. */
enum class AddressField { Address1, City, Country }

/** The address form as typed. [countryCode]: the country picked (ISO code), null until one is. */
data class AddressForm(
    val firstName: String = "",
    val lastName: String = "",
    val company: String = "",
    val address1: String = "",
    val address2: String = "",
    val city: String = "",
    val zoneCode: String = "",
    val zip: String = "",
    val countryCode: String? = null,
    val phone: String = "",
    val isDefault: Boolean = false,
) {
    /**
     * What stops the form from being sent, by field; empty when it can go. Only what every country needs: Shopify checks
     * the rest (a postal code's format, a province that exists, a phone number) and its messages show under the form.
     */
    fun errors(): Map<AddressField, String> = buildMap {
        if (address1.isBlank()) put(AddressField.Address1, "Enter an address")
        if (city.isBlank()) put(AddressField.City, "Enter a city")
        if (countryCode.isNullOrBlank()) put(AddressField.Country, "Choose a country")
    }

    /**
     * The form as the API's input, trimmed. A field left empty is left out, except one that [original] (the address being
     * edited) had a value for: that one is sent empty, or the update would keep the old value. The province code goes in
     * capitals and the phone number without its spaces and punctuation ("+1 613 555-0123" is "+16135550123").
     */
    fun toInput(original: CustomerAddress? = null): CustomerAddressInput {
        fun text(value: String, was: String?): String? = value.trim().ifEmpty { if (was.isNullOrBlank()) null else "" }
        return CustomerAddressInput(
            firstName = text(firstName, original?.firstName),
            lastName = text(lastName, original?.lastName),
            company = text(company, original?.company),
            address1 = text(address1, original?.address1),
            address2 = text(address2, original?.address2),
            city = text(city, original?.city),
            zoneCode = text(zoneCode.uppercase(), original?.zoneCode),
            zip = text(zip, original?.zip),
            countryCode = countryCode?.trim()?.uppercase()?.ifEmpty { null },
            phoneNumber = text(phone.filterNot { it.isWhitespace() || it in "-().·" }, original?.phoneNumber),
        )
    }

    companion object {
        /** The form for [address]; empty for a new one. */
        fun of(address: CustomerAddress?): AddressForm = if (address == null) AddressForm() else AddressForm(
            firstName = address.firstName.orEmpty(),
            lastName = address.lastName.orEmpty(),
            company = address.company.orEmpty(),
            address1 = address.address1.orEmpty(),
            address2 = address.address2.orEmpty(),
            city = address.city.orEmpty(),
            zoneCode = address.zoneCode.orEmpty(),
            zip = address.zip.orEmpty(),
            countryCode = address.countryCode,
            phone = address.phoneNumber.orEmpty(),
            isDefault = address.isDefault,
        )
    }
}
