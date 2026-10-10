package app.storefront.data

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonContentPolymorphicSerializer
import kotlinx.serialization.json.JsonElement

// Customer Account API models, decoded from the responses of contract/customer (fragments in its fragments.graphql).
// Same conventions as Models.kt.

@Serializable
data class Customer(
    val id: String,
    val firstName: String? = null,
    val lastName: String? = null,
    val displayName: String = "",
    val imageUrl: String? = null,
    val emailAddress: CustomerEmailAddress? = null,
    val phoneNumber: PhoneNumber? = null,
    val defaultAddress: CustomerAddress? = null,
) {
    /** First and last name. */
    val name: String get() = listOfNotNull(firstName, lastName).joinToString(" ")
    val email: String? get() = emailAddress?.emailAddress

    @Serializable
    data class PhoneNumber(val phoneNumber: String)
}

/** [marketingState]: SUBSCRIBED, NOT_SUBSCRIBED, PENDING, UNSUBSCRIBED, ... */
@Serializable
data class CustomerEmailAddress(val emailAddress: String? = null, val marketingState: String? = null)

/** [isDefault]: set by `addresses()`, this is the customer's default address. */
@Serializable
data class CustomerAddress(
    val id: String,
    val firstName: String? = null,
    val lastName: String? = null,
    val company: String? = null,
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val province: String? = null,
    val zoneCode: String? = null,
    val zip: String? = null,
    val country: String? = null,
    val countryCode: String? = null,
    val phoneNumber: String? = null,
    val formatted: List<String> = emptyList(),
    val isDefault: Boolean = false,
)

/** An address to create or change. Null fields are left out (an update keeps them as they are). */
@Serializable
data class CustomerAddressInput(
    val firstName: String? = null,
    val lastName: String? = null,
    val company: String? = null,
    val address1: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val zoneCode: String? = null,
    val zip: String? = null,
    val countryCode: String? = null,
    val phoneNumber: String? = null,
)

/** An order in the customer's list; [lineItems]: the first three, for their images. */
@Serializable
data class OrderSummary(
    val id: String,
    val name: String,
    val number: Int? = null,
    val processedAt: String,
    val financialStatus: String? = null,
    val fulfillmentStatus: String? = null,
    val cancelledAt: String? = null,
    @SerialName("totalPrice") val total: Money,
    @Serializable(with = NodesSerializer::class) val lineItems: List<LineItem> = emptyList(),
) {
    @Serializable
    data class LineItem(val image: Img? = null)
}

@Serializable
data class Order(
    val id: String,
    val name: String,
    val number: Int? = null,
    val confirmationNumber: String? = null,
    val processedAt: String,
    val statusPageUrl: String? = null,
    val financialStatus: String? = null,
    val fulfillmentStatus: String? = null,
    val cancelledAt: String? = null,
    val cancelReason: String? = null,
    val shippingAddress: CustomerAddress? = null,
    val billingAddress: CustomerAddress? = null,
    val subtotal: Money? = null,
    val totalShipping: Money? = null,
    val totalTax: Money? = null,
    @SerialName("totalPrice") val total: Money,
    val totalRefunded: Money? = null,
    @Serializable(with = NodesSerializer::class) val discountApplications: List<DiscountApplication> = emptyList(),
    @SerialName("lineItems") @Serializable(with = NodesSerializer::class) val lines: List<OrderLine> = emptyList(),
    /** Empty: nothing fulfilled yet. */
    @Serializable(with = NodesSerializer::class) val fulfillments: List<Fulfillment> = emptyList(),
)

@Serializable
data class OrderLine(
    val id: String? = null,
    val title: String,
    val variantTitle: String? = null,
    val quantity: Int,
    val image: Img? = null,
    val productId: String? = null,
    val variantId: String? = null,
    val price: Money? = null,
    @SerialName("totalPrice") val total: Money? = null,
)

@Serializable
data class DiscountApplication(val value: PricingValue)

/** A discount's value by `__typename`: an amount ([Money]) or a [Percentage]. */
@Serializable(with = PricingValueSerializer::class)
sealed interface PricingValue {
    @Serializable
    data class Percentage(val percentage: Double) : PricingValue

    @Serializable
    data class Other(@SerialName("__typename") val typename: String? = null) : PricingValue
}

internal object PricingValueSerializer : JsonContentPolymorphicSerializer<PricingValue>(PricingValue::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<PricingValue> = when (element.typename) {
        "MoneyV2" -> Money.serializer()
        "PricingPercentageValue" -> PricingValue.Percentage.serializer()
        else -> PricingValue.Other.serializer()
    }
}

/** [status]: SUCCESS, CANCELLED, ...; [latestShipmentStatus]: IN_TRANSIT, DELIVERED, ... */
@Serializable
data class Fulfillment(
    val id: String,
    val status: String? = null,
    val createdAt: String? = null,
    val estimatedDeliveryAt: String? = null,
    val latestShipmentStatus: String? = null,
    val trackingInformation: List<Tracking> = emptyList(),
    @Serializable(with = NodesSerializer::class) val fulfillmentLineItems: List<LineItem> = emptyList(),
) {
    @Serializable
    data class Tracking(val company: String? = null, val number: String? = null, val url: String? = null)

    /** [lineItem]: the order line it fulfils. */
    @Serializable
    data class LineItem(val quantity: Int, val lineItem: Ref)

    @Serializable
    data class Ref(val id: String)
}

/** What of an order can be returned, and its returns so far. */
@Serializable
data class OrderReturnOptions(
    val id: String,
    val returnInformation: ReturnInformation? = null,
    @Serializable(with = NodesSerializer::class) val returns: List<Return> = emptyList(),
) {
    val returnableLineItems: List<ReturnableLineItem> get() = returnInformation?.returnableLineItems.orEmpty()

    @Serializable
    data class ReturnInformation(@Serializable(with = NodesSerializer::class) val returnableLineItems: List<ReturnableLineItem> = emptyList())
}

/** [quantity]: how many can still be returned. */
@Serializable
data class ReturnableLineItem(val quantity: Int, val lineItem: LineItem) {
    /** [suggestedReturnReasonDefinitions]: the reasons to offer; send one's id as `returnReasonDefinitionId`. */
    @Serializable
    data class LineItem(
        val id: String,
        val title: String,
        val image: Img? = null,
        @Serializable(with = NodesSerializer::class) val suggestedReturnReasonDefinitions: List<ReturnReason> = emptyList(),
    )
}

@Serializable
data class ReturnReason(val id: String, val handle: String, val name: String)

/** [status]: REQUESTED, OPEN, CLOSED, DECLINED, ... */
@Serializable
data class Return(val id: String, val name: String? = null, val status: String, val createdAt: String? = null)

@Serializable
data class RequestedLineItemInput(val lineItemId: String, val quantity: Int, val returnReasonDefinitionId: String? = null, val customerNote: String? = null)
