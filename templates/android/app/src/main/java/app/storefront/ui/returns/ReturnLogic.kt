package app.storefront.ui.returns

import app.storefront.data.Money
import app.storefront.data.OrderReturnOptions
import app.storefront.data.Product
import app.storefront.data.ProductOption
import app.storefront.data.RequestedLineItemInput
import app.storefront.data.ReturnFee
import app.storefront.data.ReturnableLineItem
import app.storefront.data.Variants
import app.storefront.ui.display
import app.storefront.ui.orders.variantLabel

// The returns flow's rules, kept free of UI so they can be tested (and read side by side with iOS).

/** The most Shopify takes as a return line's note (`customerNote`). */
const val NOTE_LIMIT = 300

/** The flow's three steps. */
val RETURN_STEPS = listOf("Choose items", "Refund or exchange", "Review")

/**
 * What the shopper chose for one returnable item. [quantity]: how many go back (0: the item isn't chosen); [exchange]:
 * a replacement instead of a refund; [reasonId]: the return reason picked; [note]: their own words; [wanted]: what they
 * want instead (an exchange), as the store will read it: the variant picked ([exchangeItem]) or, when the product's
 * options couldn't be loaded, what they typed; [selection]: the options picked in the replacement picker.
 */
data class ReturnChoice(
    val quantity: Int = 0,
    val exchange: Boolean = false,
    val reasonId: String? = null,
    val note: String = "",
    val wanted: String = "",
    val selection: Map<String, String> = emptyMap(),
)

/**
 * A replacement as the store reads it: "Men's Crewneck - Large / Olive (SKU MC-LO)". The SKU part is left out when there
 * is none, and the variant part for a product without options (Shopify's "Default Title").
 */
fun exchangeItem(productTitle: String, variantTitle: String?, sku: String?): String {
    val variant = variantLabel(variantTitle)?.let { " - $it" }.orEmpty()
    val code = sku?.trim()?.takeIf { it.isNotEmpty() }?.let { " (SKU $it)" }.orEmpty()
    return productTitle.trim() + variant + code
}

/**
 * The note of a return line that is an exchange: "Exchange for: <wanted>", then on a new line the shopper's [note] when
 * they wrote one. The Customer Account API has no exchange input: the store reads the wanted item here and completes the
 * exchange in its admin.
 */
fun exchangeNote(wanted: String, note: String): String =
    listOf("Exchange for: ${wanted.trim()}", note.trim()).filter { it.isNotEmpty() }.joinToString("\n")

/** [exchangeNote] for a picked variant: "Exchange for: <product title> - <variant title> (SKU <sku>)", then the note. */
fun exchangeNote(productTitle: String, variantTitle: String?, sku: String?, note: String): String =
    exchangeNote(exchangeItem(productTitle, variantTitle, sku), note)

/** How long the shopper's own note may be: an exchange's note starts with what they want instead, which counts too. */
fun noteLimit(choice: ReturnChoice): Int =
    if (choice.exchange) (NOTE_LIMIT - exchangeNote(choice.wanted, "").length - 1).coerceAtLeast(0) else NOTE_LIMIT

/**
 * The lines of the return request: one per chosen item of [items] ([choices] by line item id, quantity above 0), with at
 * most the quantity that can go back, the reason, and the note (an exchange's says what is wanted, [exchangeNote]) cut to
 * what Shopify takes.
 */
fun returnLines(items: List<ReturnableLineItem>, choices: Map<String, ReturnChoice>): List<RequestedLineItemInput> = items.mapNotNull { item ->
    val choice = choices[item.lineItem.id]?.takeIf { it.quantity > 0 && item.quantity > 0 } ?: return@mapNotNull null
    val note = if (choice.exchange) exchangeNote(choice.wanted, choice.note) else choice.note.trim()
    RequestedLineItemInput(
        lineItemId = item.lineItem.id,
        quantity = choice.quantity.coerceAtMost(item.quantity),
        returnReasonDefinitionId = choice.reasonId,
        customerNote = note.take(NOTE_LIMIT).ifEmpty { null },
    )
}

/** What a chosen item still needs before the review, in the shopper's words; null when it is complete. */
fun choiceProblem(item: ReturnableLineItem, choice: ReturnChoice): String? = when {
    item.lineItem.suggestedReturnReasonDefinitions.isNotEmpty() && choice.reasonId == null -> "Choose a reason"
    choice.exchange && choice.wanted.isBlank() -> "Choose what you'd like instead"
    else -> null
}

/**
 * What stops the flow from leaving [step] (an index into [RETURN_STEPS]) with these [chosen] items and their choices:
 * nothing chosen (step 1), the first chosen item that is incomplete (step 2); null when it can go on.
 */
fun stepProblem(step: Int, chosen: List<Pair<ReturnableLineItem, ReturnChoice>>): String? = when (step) {
    0 -> "Choose at least one item".takeIf { chosen.isEmpty() }
    1 -> chosen.firstNotNullOfOrNull { (item, choice) -> choiceProblem(item, choice) }
    else -> null
}

/**
 * The items of an order that can go back, each order line once: Shopify may list a line more than once (it shipped in
 * parts), and the flow keeps one choice per line. Lines with nothing left to return are left out.
 */
fun returnableItems(options: OrderReturnOptions): List<ReturnableLineItem> = options.returnableLineItems
    .groupBy { it.lineItem.id }
    .map { (_, same) -> same.first().copy(quantity = same.sumOf { it.quantity }) }
    .filter { it.quantity > 0 }

/**
 * The lines under a chosen item in the review: its variant, "Qty N", "Refund" or "Exchange for: ...", the reason, and
 * the shopper's note.
 */
fun reviewDetails(item: ReturnableLineItem, choice: ReturnChoice): List<String> = listOfNotNull(
    variantLabel(item.lineItem.variantTitle),
    "Qty ${choice.quantity.coerceAtMost(item.quantity)}",
    if (choice.exchange) exchangeNote(choice.wanted, "") else "Refund",
    item.lineItem.suggestedReturnReasonDefinitions.firstOrNull { it.id == choice.reasonId }?.name,
    choice.note.trim().ifEmpty { null },
)

/** A fee's name: the store's title for it, else by its kind. */
fun feeLabel(fee: ReturnFee): String = fee.title?.takeIf { it.isNotBlank() } ?: when (fee.kind) {
    "ReturnShippingFee" -> "Return shipping"
    "RestockingFee" -> "Restocking fee"
    else -> "Fee"
}

/**
 * What a return costs, as label and amount: each fee the store lists, and "Applies" for a fee it says there is without
 * listing an amount. [money] formats an amount.
 */
fun feeRows(options: OrderReturnOptions, money: (Money) -> String = { it.display() }): List<Pair<String, String>> {
    val listed = options.fees.map { feeLabel(it) to (it.amount?.let(money) ?: "Applies") }
    val kinds = options.fees.map { it.kind }
    return listed +
        listOfNotNull(
            ("Return shipping" to "Applies").takeIf { options.hasReturnShippingFee && "ReturnShippingFee" !in kinds },
            ("Restocking fee" to "Applies").takeIf { options.hasRestockingFee && "RestockingFee" !in kinds },
        )
}

/** The options a shopper chooses between: all but Shopify's lone "Title: Default Title" of a product without options. */
fun choosableOptions(product: Product): List<ProductOption> =
    product.options.filterNot { it.name == "Title" && it.values == listOf("Default Title") }

/**
 * Where the replacement picker starts: the options of the variant being returned (the shopper then changes the size),
 * else of the first available variant, else of the first.
 */
fun startSelection(product: Product, variantId: String?): Map<String, String> {
    val variants = product.variants
    return (variants.firstOrNull { it.id == variantId } ?: variants.firstOrNull { it.available } ?: variants.firstOrNull())?.options.orEmpty()
}

/** What [selection] asks for, as the exchange note names it ([exchangeItem]); empty when no variant has those options or it is sold out. */
fun wantedVariant(product: Product, selection: Map<String, String>): String =
    Variants.match(product.variants, selection)?.takeIf { it.available }?.let { exchangeItem(product.title, it.title, it.sku) }.orEmpty()
