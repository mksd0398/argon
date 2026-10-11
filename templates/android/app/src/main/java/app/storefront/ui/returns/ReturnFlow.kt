package app.storefront.ui.returns

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.storefront.data.OrderReturnOptions
import app.storefront.data.Product
import app.storefront.data.Return
import app.storefront.data.ReturnableLineItem

/** The product of an item being exchanged, for its options; null [product]: it couldn't be loaded (the shopper types what they want). */
class ExchangeProduct(val product: Product?)

/**
 * The returns flow of one order: the step it is on, what the shopper chose, and how the request went. Kept with the
 * screen (it is what the screen's Loader loads), so a rotation or a look at another app doesn't lose the choices.
 */
class ReturnFlow(val options: OrderReturnOptions) {
    /** The items that can go back. */
    val items: List<ReturnableLineItem> = returnableItems(options)

    /** 0, 1, 2: an index into [RETURN_STEPS]. */
    var step by mutableIntStateOf(0)

    /** By line item id. */
    var choices by mutableStateOf(emptyMap<String, ReturnChoice>())
        private set

    /** The products loaded for the replacement picker, by line item id; none yet: still loading. */
    val products = mutableStateMapOf<String, ExchangeProduct>()

    var submitting by mutableStateOf(false)

    /** Why the request was refused (Shopify's user errors) or couldn't be sent. */
    var error by mutableStateOf<String?>(null)

    /** The return Shopify created: the flow is done. */
    var submitted by mutableStateOf<Return?>(null)

    fun choice(item: ReturnableLineItem): ReturnChoice = choices[item.lineItem.id] ?: ReturnChoice()

    fun update(item: ReturnableLineItem, change: (ReturnChoice) -> ReturnChoice) {
        choices = choices + (item.lineItem.id to change(choice(item)))
    }

    /** The items chosen to go back, in the order's order. */
    val chosen: List<ReturnableLineItem> get() = items.filter { choice(it).quantity > 0 }
}
