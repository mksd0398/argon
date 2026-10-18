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

/**
 * An order in the customer's list. [titles] and [images]: its first three lines'; [itemCount]: how many items were
 * ordered, over all lines. [latestShipmentStatus] (IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, ...) and
 * [estimatedDeliveryAt]: its latest shipment's, null while nothing has shipped. [deliveredAt]: when that shipment was
 * delivered.
 */
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
    @Serializable(with = NodesSerializer::class) private val fulfillments: List<Shipment> = emptyList(),
) {
    val images: List<Img> get() = lineItems.take(3).mapNotNull { it.image }
    val titles: List<String> get() = lineItems.take(3).mapNotNull { it.title }
    // ponytail: sums the first 50 lines (Orders.graphql), so an order of more lines undercounts. Upgrade: page lineItems.
    val itemCount: Int? get() = lineItems.sumOf { it.quantity }
    val latestShipmentStatus: String? get() = fulfillments.firstOrNull()?.latestShipmentStatus
    val estimatedDeliveryAt: String? get() = fulfillments.firstOrNull()?.estimatedDeliveryAt
    val deliveredAt: String? get() = fulfillments.firstOrNull()?.takeIf { it.latestShipmentStatus == "DELIVERED" }?.updatedAt

    @Serializable
    data class LineItem(val title: String? = null, val quantity: Int = 0, val image: Img? = null)

    @Serializable
    data class Shipment(val latestShipmentStatus: String? = null, val estimatedDeliveryAt: String? = null, val updatedAt: String? = null)
}

/**
 * One order in full. [edited]: the merchant changed it after it was placed. [purchasingCompany]: the company it was
 * bought for (B2B), with its [poNumber]. [hasReturnableItems]: something on it can still be returned (`returnOptions`
 * says what).
 */
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
    val edited: Boolean = false,
    val requiresShipping: Boolean = true,
    val note: String? = null,
    val poNumber: String? = null,
    // a PurchasingCompany, or the Customer (of which the document selects nothing)
    private val purchasingEntity: Purchaser? = null,
    val shippingLine: OrderShippingLine? = null,
    val paymentInformation: OrderPaymentInformation? = null,
    val transactions: List<OrderTransaction> = emptyList(),
    val refunds: List<OrderRefund> = emptyList(),
    @Serializable(with = NodesSerializer::class) val returns: List<Return> = emptyList(),
    private val returnInformation: Returnable? = null,
) {
    val purchasingCompany: PurchasingCompany?
        get() {
            val company = purchasingEntity?.company ?: return null
            return PurchasingCompany(company, purchasingEntity.location ?: return null)
        }

    val hasReturnableItems: Boolean get() = returnInformation?.returnableLineItems.orEmpty().any { it.quantity > 0 }

    @Serializable
    data class Purchaser(val company: Company? = null, val location: CompanyLocation? = null)

    @Serializable
    data class Returnable(@Serializable(with = NodesSerializer::class) val returnableLineItems: List<Quantity> = emptyList())

    @Serializable
    data class Quantity(val quantity: Int = 0)
}

/** [title]: the delivery method the shopper chose. */
@Serializable
data class OrderShippingLine(val title: String? = null, val originalPrice: Money? = null)

/** B2B payment terms ("Net 30") and when the next payment is due. */
@Serializable
data class PaymentTerms(val paymentTermsName: String? = null, val nextDueAt: String? = null, val overdue: Boolean? = null)

/** [paymentCollectionUrl]: where an outstanding amount is paid. */
@Serializable
data class OrderPaymentInformation(
    val paymentStatus: String? = null,
    val totalPaidAmount: Money? = null,
    val totalOutstandingAmount: Money? = null,
    val paymentCollectionUrl: String? = null,
    val paymentTerms: PaymentTerms? = null,
)

/** An amount in the currency the customer paid in. */
@Serializable
data class MoneyBag(val presentmentMoney: Money? = null)

/**
 * A payment or refund on an order. [kind]: SALE, REFUND, ...; [type]: CARD, GIFT_CARD, ...; [cardBrand] and [last4]: of
 * the card it was paid with; [giftCardLast4]: of the gift card.
 */
@Serializable
data class OrderTransaction(
    val id: String,
    val kind: String? = null,
    val status: String? = null,
    val type: String? = null,
    val processedAt: String? = null,
    private val transactionAmount: MoneyBag? = null,
    // CardPaymentDetails; any other payment details type has neither field
    private val paymentDetails: Details? = null,
    private val giftCardDetails: Details? = null,
) {
    val amount: Money? get() = transactionAmount?.presentmentMoney
    val cardBrand: String? get() = paymentDetails?.cardBrand
    val last4: String? get() = paymentDetails?.last4
    val giftCardLast4: String? get() = giftCardDetails?.last4

    @Serializable
    data class Details(val cardBrand: String? = null, val last4: String? = null)
}

/** [returnName]: the return it paid back, if any. */
@Serializable
data class OrderRefund(val id: String, val createdAt: String? = null, val returnName: String? = null, val totalRefunded: Money? = null)

/** [refundableQuantity]: how many of [quantity] haven't been refunded. */
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
    val sku: String? = null,
    val refundableQuantity: Int? = null,
    val totalDiscount: Money? = null,
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

/**
 * [status]: SUCCESS, CANCELLED, ...; [latestShipmentStatus]: IN_TRANSIT, DELIVERED, ...; [events]: what the carrier
 * reported, oldest first.
 */
@Serializable
data class Fulfillment(
    val id: String,
    val status: String? = null,
    val createdAt: String? = null,
    val estimatedDeliveryAt: String? = null,
    val latestShipmentStatus: String? = null,
    val trackingInformation: List<Tracking> = emptyList(),
    @Serializable(with = NodesSerializer::class) val fulfillmentLineItems: List<LineItem> = emptyList(),
    val isPickedUp: Boolean = false,
    @Serializable(with = NodesSerializer::class) val events: List<FulfillmentEvent> = emptyList(),
) {
    @Serializable
    data class Tracking(val company: String? = null, val number: String? = null, val url: String? = null)

    /** [lineItem]: the order line it fulfils. */
    @Serializable
    data class LineItem(val quantity: Int, val lineItem: Ref)

    @Serializable
    data class Ref(val id: String)
}

/** A step of a shipment. [status]: CONFIRMED, IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, ... */
@Serializable
data class FulfillmentEvent(val status: String, val happenedAt: String? = null)

/**
 * What of an order can be returned, what a return costs, and its returns so far. [fees]: what the customer pays for it
 * ([hasRestockingFee], [hasReturnShippingFee]); [returnShippingMethods]: MERCHANT_PROVIDED_LABEL,
 * CUSTOMER_PROVIDED_LABEL, ..., with the store's [returnShippingMethodNote]; [nonReturnableSummary]: why some items
 * aren't offered.
 */
@Serializable
data class OrderReturnOptions(
    val id: String,
    private val returnInformation: ReturnInformation? = null,
    @Serializable(with = NodesSerializer::class) val returns: List<Return> = emptyList(),
    @SerialName("name") val orderName: String? = null,
) {
    val returnableLineItems: List<ReturnableLineItem> get() = returnInformation?.returnableLineItems.orEmpty()
    val hasRestockingFee: Boolean get() = returnInformation?.hasRestockingFee == true
    val hasReturnShippingFee: Boolean get() = returnInformation?.hasReturnShippingFee == true
    val returnShippingMethods: List<String> get() = returnInformation?.returnShippingMethods.orEmpty()
    val returnShippingMethodNote: String? get() = returnInformation?.returnShippingMethodNote
    val fees: List<ReturnFee> get() = returnInformation?.returnFees.orEmpty()
    val nonReturnableSummary: String? get() = returnInformation?.nonReturnableSummary?.nonReturnableReasons.orEmpty()
        .map(::nonReturnableReason).distinct().joinToString(" ").ifEmpty { null }

    @Serializable
    data class ReturnInformation(
        @Serializable(with = NodesSerializer::class) val returnableLineItems: List<ReturnableLineItem> = emptyList(),
        val hasRestockingFee: Boolean = false,
        val hasReturnShippingFee: Boolean = false,
        val returnShippingMethods: List<String> = emptyList(),
        val returnShippingMethodNote: String? = null,
        val returnFees: List<ReturnFee> = emptyList(),
        val nonReturnableSummary: Summary? = null,
    )

    @Serializable
    data class Summary(val nonReturnableReasons: List<String> = emptyList())
}

/** Why some of an order can't be returned, from one of Shopify's NonReturnableReason values. */
fun nonReturnableReason(reason: String): String = when (reason) {
    "RETURNED" -> "Some items were already returned."
    "FINAL_SALE" -> "Final sale items can't be returned."
    "RETURN_WINDOW_EXPIRED" -> "The return window has closed."
    "UNFULFILLED" -> "Items that haven't shipped can't be returned yet."
    else -> "Some items can't be returned."
}

/** A fee of a return. [kind]: ReturnShippingFee or RestockingFee. */
@Serializable
data class ReturnFee(@SerialName("__typename") val kind: String = "", val title: String? = null, private val amountSet: MoneyBag? = null) {
    val amount: Money? get() = amountSet?.presentmentMoney
}

/** [quantity]: how many can still be returned. */
@Serializable
data class ReturnableLineItem(val quantity: Int, val lineItem: LineItem) {
    /**
     * The order line as the returns flow shows it. [suggestedReturnReasonDefinitions]: the reasons to offer; send one's
     * id as `returnReasonDefinitionId`. [productId] and [variantId]: for picking what to exchange it for.
     */
    @Serializable
    data class LineItem(
        val id: String,
        val title: String,
        val image: Img? = null,
        @Serializable(with = NodesSerializer::class) val suggestedReturnReasonDefinitions: List<ReturnReason> = emptyList(),
        val variantTitle: String? = null,
        val sku: String? = null,
        val productId: String? = null,
        val variantId: String? = null,
        val price: Money? = null,
    )
}

@Serializable
data class ReturnReason(val id: String, val handle: String, val name: String)

/**
 * [status]: REQUESTED, OPEN, CLOSED, DECLINED, ... [lines], [exchangeLines] and [closedAt] where the document
 * selects them (Order).
 */
@Serializable
data class Return(
    val id: String,
    val name: String? = null,
    val status: String,
    val createdAt: String? = null,
    val closedAt: String? = null,
    @SerialName("returnLineItems") @Serializable(with = NodesSerializer::class) val lines: List<ReturnLine> = emptyList(),
    @SerialName("exchangeLineItems") @Serializable(with = NodesSerializer::class) val exchangeLines: List<ExchangeLine> = emptyList(),
)

/** [quantity] of an order line ([lineItemId], with its [title], [variantTitle] and [image]) sent back, and why ([reason]). */
@Serializable
data class ReturnLine(
    val id: String,
    val quantity: Int,
    private val returnReasonDefinition: Reason? = null,
    private val lineItem: Line? = null,
) {
    val reason: String? get() = returnReasonDefinition?.name
    val lineItemId: String? get() = lineItem?.id
    val title: String? get() = lineItem?.title
    val variantTitle: String? get() = lineItem?.variantTitle
    val image: Img? get() = lineItem?.image

    @Serializable
    data class Reason(val name: String? = null)

    @Serializable
    data class Line(val id: String? = null, val title: String? = null, val variantTitle: String? = null, val image: Img? = null)
}

/** What the customer gets instead of a returned item. */
@Serializable
data class ExchangeLine(val id: String, val title: String, val variantTitle: String? = null, val quantity: Int, val image: Img? = null)

/** The customer as a contact of a B2B [company], with the locations they may buy for. */
@Serializable
data class CompanyContact(val id: String, val title: String? = null, val company: Company)

/** Credit the store owes the customer, spent at checkout. */
@Serializable
data class StoreCreditAccount(val id: String, val balance: Money)

@Serializable
data class RequestedLineItemInput(val lineItemId: String, val quantity: Int, val returnReasonDefinitionId: String? = null, val customerNote: String? = null)
