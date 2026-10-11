package app.storefront.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonProgressBar
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.Cart
import app.storefront.data.CartDiscount
import app.storefront.data.CartLine
import app.storefront.data.CartLineComponent
import app.storefront.data.Money
import app.storefront.data.ProductCard
import app.storefront.data.QuantityRule
import app.storefront.data.Route
import app.storefront.data.beginCheckout
import app.storefront.data.checkoutStep
import app.storefront.data.purchase
import app.storefront.data.viewCart
import com.shopify.checkoutsheetkit.CheckoutException
import com.shopify.checkoutsheetkit.CheckoutExpiredException
import com.shopify.checkoutsheetkit.DefaultCheckoutEventProcessor
import com.shopify.checkoutsheetkit.ShopifyCheckoutSheetKit
import com.shopify.checkoutsheetkit.lifecycleevents.CheckoutCompletedEvent
import com.shopify.checkoutsheetkit.pixelevents.PixelEvent
import java.math.BigDecimal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The activity a composition runs in (Checkout Kit needs a ComponentActivity); its context may be a wrapper around one. */
internal tailrec fun Context.componentActivity(): ComponentActivity? = when (this) {
    is ComponentActivity -> this
    is ContextWrapper -> baseContext.componentActivity()
    else -> null
}

/**
 * Shows Shopify's checkout for [url] (`CartStore.checkoutUrl`) over [host]: the cart screen's "Checkout" and the product
 * page's "Buy now". A placed order spends the cart. A checkout that fails keeps it and hands the reason to [onError];
 * one Shopify no longer has (expired, already paid) is dropped by loading the cart again.
 *
 * Analytics hears of the whole way from here: `begin_checkout` as the sheet opens (the app has the whole cart), the
 * shipping and payment steps from the checkout's web pixel events, and the purchase from the completed order, which
 * comes once (the pixel's `checkout_completed` is left alone).
 */
internal fun presentCheckout(url: String, host: ComponentActivity, onError: (String) -> Unit) {
    val processor = object : DefaultCheckoutEventProcessor(host) {
        override fun onCheckoutCompleted(checkoutCompletedEvent: CheckoutCompletedEvent) {
            AppGraph.analytics.track(purchase(checkoutCompletedEvent.orderDetails))
            AppGraph.scope.launch { AppGraph.cart.completed() }
        }

        override fun onWebPixelEvent(event: PixelEvent) {
            checkoutStep(event)?.let { AppGraph.analytics.track(it) }
        }

        override fun onCheckoutFailed(error: CheckoutException) {
            if (error is CheckoutExpiredException) AppGraph.scope.launch { runCatching { AppGraph.cart.load() } }
            onError(error.errorDescription)
        }

        override fun onCheckoutCanceled() {}
    }
    AppGraph.cart.cart.value?.let { AppGraph.analytics.track(beginCheckout(it)) }
    ShopifyCheckoutSheetKit.present(url, host, processor)
}

/** "Men's T-shirt · Small / Olive × 1": a bundle's part on a cart line (the variant left out when it is "Default Title"). */
internal fun componentLabel(part: CartLineComponent): String =
    listOfNotNull(part.productTitle.takeIf { it.isNotBlank() }, part.variantTitle.takeIf { it != "Default Title" }).joinToString(" · ") + " × ${part.quantity}"

private fun Money.value(): BigDecimal = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO

private val Money.isZero: Boolean get() = value().signum() == 0

/** How far a cart is from free shipping: what is still to add ([remaining], zero once reached) and the [progress] to it, 0...1. */
data class FreeShipping(val remaining: Money, val progress: Float) {
    val reached: Boolean get() = remaining.isZero
}

/**
 * Free shipping for a cart worth [subtotal] (its total after discounts) in a store that ships free from [threshold];
 * null for a store without one (`FREE_SHIPPING_THRESHOLD` unset), or an amount that can't be read.
 * ponytail: the threshold is one number, compared with the cart in whatever currency the shopper buys in. Upgrade: one
 * threshold per currency, if stores selling in several ask for it.
 */
fun freeShipping(subtotal: Money, threshold: Double?): FreeShipping? {
    val goal = threshold?.takeIf { it > 0 && it.isFinite() }?.toBigDecimal() ?: return null
    val have = subtotal.amount.toBigDecimalOrNull() ?: return null
    val remaining = (goal - have).max(BigDecimal.ZERO)
    return FreeShipping(Money(remaining.toPlainString(), subtotal.currencyCode), (have.toDouble() / goal.toDouble()).toFloat().coerceIn(0f, 1f))
}

/** What [line] would cost at its compare-at price; null when it has none above its price. */
internal fun compareAtTotal(line: CartLine): Money? {
    val was = line.compareAtUnitPrice ?: return null
    if (was.value() <= line.unitPrice.value()) return null
    return Money((was.value() * line.quantity.toBigDecimal()).toPlainString(), was.currencyCode)
}

/** "WELCOME10 −$12.00": a discount on a line, by its code or its title, and what it takes off. */
internal fun discountLabel(discount: CartDiscount): String = "${discount.label} −${discount.amount.display()}"

/**
 * The cart's totals as its summary shows them: [subtotal] is the lines before discounts, [discounts] what codes and
 * automatic discounts take off, [savings] that plus what the compare-at prices say is saved, [total] what Shopify asks
 * for. [discounts] and [savings] are zero when there are none (their rows then hide).
 */
data class CartSummary(val subtotal: Money, val discounts: Money, val savings: Money, val total: Money)

fun cartSummary(cart: Cart): CartSummary {
    fun money(amount: BigDecimal) = Money(amount.toPlainString(), cart.total.currencyCode)
    val discounts = cart.lines.sumOf { line -> line.discounts.sumOf { it.amount.value() } }
    val marked = cart.lines.sumOf { line -> compareAtTotal(line)?.let { it.value() - line.subtotal.value() }?.max(BigDecimal.ZERO) ?: BigDecimal.ZERO }
    return CartSummary(money(cart.lines.sumOf { it.subtotal.value() }), money(discounts), money(marked + discounts), cart.total)
}

/** The products to suggest under a cart: the [recommended] ones that aren't in the [cart] already. */
internal fun suggestions(recommended: List<ProductCard>, cart: Cart?): List<ProductCard> {
    val inCart = cart?.lines.orEmpty().map { it.productId }.toSet()
    return recommended.filter { it.id !in inCart }
}

/**
 * The Cart tab: one scrolling list (free-shipping progress, the lines, the discount code, "You may also like") over a
 * pinned summary with "Checkout"; an empty cart offers "Start shopping".
 */
@Composable
fun CartScreen(nav: NavController) {
    val cart by AppGraph.cart.cart.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    val screen = rememberCoroutineScope()
    val activity = LocalContext.current.componentActivity()
    var busy by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }

    // The app loaded the cart at start; load again on each visit so the screen is current (and Retry has something to run).
    LaunchedEffect(attempt) {
        loading = true
        failure = null
        try {
            AppGraph.cart.load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failure = e.message ?: e.toString()
        } finally {
            loading = false
        }
        // analytics' `view_cart`: once per visit, of the cart as it is now (the last known one when the load failed)
        AppGraph.cart.cart.value?.takeIf { it.lines.isNotEmpty() }?.let { AppGraph.analytics.track(viewCart(it)) }
    }

    // Warm up checkout once the shopper is looking at a non-empty cart, and again after every change to it.
    // The delay is a debounce: tapping the stepper quickly restarts this effect, so only the last cart is preloaded.
    // Presenting checkout cancels it: a preload landing on the open sheet would cut it off from its events.
    var preload by remember { mutableStateOf<Job?>(null) }
    LaunchedEffect(cart) {
        preload = coroutineContext[Job]
        if (activity == null || cart?.lines.isNullOrEmpty()) return@LaunchedEffect
        delay(500)
        try {
            AppGraph.cart.checkoutUrl()?.let { ShopifyCheckoutSheetKit.preload(it, activity) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // preloading is only a hint: checkout still works without it, and Checkout reports real problems
        }
    }

    /** Runs [block] on [scope] with the screen busy; a failure shows as a snackbar once the screen is usable again. */
    fun act(scope: CoroutineScope, block: suspend () -> Unit) {
        busy = true
        scope.launch {
            val message = try {
                block()
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                e.message ?: e.toString()
            }
            busy = false
            // from the screen's scope, not [scope]: a snackbar is only shown while the screen is there (the process-wide
            // scope would suspend in showSnackbar forever if the shopper had left)
            message?.let { screen.launch { snackbar.showSnackbar(it) } }
        }
    }

    fun checkout(host: ComponentActivity) = act(screen) {
        val url = AppGraph.cart.checkoutUrl() ?: return@act
        preload?.cancel()
        presentCheckout(url, host) { screen.launch { snackbar.showSnackbar(it) } }
    }

    Scaffold(
        topBar = { ArgonTopBar("Cart") },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        // imePadding: typing a discount code, the list ends at the keyboard
        Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding().fillMaxSize()) {
            val current = cart
            val error = failure
            when {
                current != null && current.lines.isNotEmpty() -> CartContent(
                    current,
                    busy,
                    onOpen = { nav.open(it) },
                    onQuantity = { line, quantity -> act(AppGraph.scope) { AppGraph.cart.update(line.id, quantity) } },
                    onCheckout = { activity?.let(::checkout) },
                )
                loading && current == null -> Spinner()
                error != null && current == null -> ErrorView(error) { attempt++ }
                else -> EmptyCart()
            }
        }
    }
}

@Composable
private fun EmptyCart() = Column(
    Modifier.fillMaxSize().padding(ArgonTheme.spacing.xxl),
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.l, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    Text("Your cart is empty", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
    ArgonButton("Start shopping") { AppGraph.tabs.select(AppTab.Shop) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CartContent(cart: Cart, busy: Boolean, onOpen: (Route) -> Unit, onQuantity: (CartLine, Int) -> Unit, onCheckout: () -> Unit) {
    val spacing = ArgonTheme.spacing
    val gutter = Modifier.padding(horizontal = spacing.l)
    val shipping = freeShipping(cart.total, AppGraph.freeShippingThreshold)
    val alsoLike = alsoLike(cart)
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.l), contentPadding = PaddingValues(vertical = spacing.l)) {
            if (shipping != null) item(key = "free-shipping") { FreeShippingBar(shipping, gutter) }
            items(cart.lines, key = { it.id }) { line -> CartLineRow(line, busy, gutter) { onQuantity(line, it) } }
            item(key = "discount-code") { DiscountCode(cart, gutter) }
            if (alsoLike.isNotEmpty()) {
                item(key = "also-like") {
                    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
                        SectionHeader("You may also like", gutter)
                        ProductCardRow(alsoLike, { onOpen(Route.Product(it.handle)) }, style = ProductCardStyle.Compact, cardWidth = 132.dp)
                    }
                }
            }
        }
        // While the keyboard is up (the discount code) the list has the room; the summary is back when it is gone.
        if (!WindowInsets.isImeVisible) Summary(cartSummary(cart), busy, onCheckout)
    }
}

/**
 * "You may also like": the products related to the cart's first product, without those in the cart when they are
 * loaded (one added from here stays, with its stepper). Empty until they load, and when they can't be.
 */
@Composable
private fun alsoLike(cart: Cart): List<ProductCard> {
    val productId = cart.lines.firstOrNull()?.productId.orEmpty()
    val cards by produceState(emptyList<ProductCard>(), productId) {
        value = try {
            if (productId.isEmpty()) emptyList() else suggestions(AppGraph.storefront.recommendations(productId), AppGraph.cart.cart.value)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
    }
    return cards
}

/** "Add $30.00 more for free shipping" over a bar of how far the cart is; "You've unlocked free shipping" once it is there. */
@Composable
private fun FreeShippingBar(shipping: FreeShipping, modifier: Modifier) {
    val colors = ArgonTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
            ArgonIcon(ArgonIconName.Truck, size = 20.dp, tint = if (shipping.reached) colors.success else colors.ink)
            Text(
                if (shipping.reached) "You've unlocked free shipping" else "Add ${shipping.remaining.display()} more for free shipping",
                style = ArgonTheme.type.label,
                color = if (shipping.reached) colors.success else colors.ink,
            )
        }
        ArgonProgressBar(shipping.progress)
    }
}

/**
 * A cart line: image, product, variant, the selling plan it is bought on, a bundle's parts and each discount on the
 * line, with its price (and, struck under it, what it would cost at its compare-at price) at the end; then the quantity
 * on the variant's quantity rule (its minimum, maximum and increments) with a bin beside it that removes the line.
 * [onQuantity] gets the new quantity; 0 removes the line.
 */
@Composable
private fun CartLineRow(line: CartLine, busy: Boolean, modifier: Modifier, onQuantity: (Int) -> Unit) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    val rule = line.merchandise.quantityRule ?: QuantityRule()
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
        StoreImage(line.image, line.productTitle, Modifier.size(88.dp).clip(ArgonTheme.radius.m))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.xxs)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                Text(line.productTitle, Modifier.weight(1f), style = type.label, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Column(horizontalAlignment = Alignment.End) {
                    Text(line.total.display(), style = type.label, color = colors.ink, maxLines = 1)
                    compareAtTotal(line)?.display()?.let { was ->
                        Text(
                            was,
                            Modifier.semantics { contentDescription = "Was $was" },
                            style = type.caption,
                            color = colors.muted,
                            textDecoration = TextDecoration.LineThrough,
                            maxLines = 1,
                        )
                    }
                }
            }
            // a product without options has Shopify's one "Default Title" variant; nothing worth showing
            if (line.variantTitle != "Default Title") Text(line.variantTitle, style = type.caption, color = colors.muted)
            line.sellingPlanName?.let { Text(it, style = type.caption, color = colors.muted) }
            for (part in line.components) Text(componentLabel(part), style = type.caption, color = colors.muted)
            for (discount in line.discounts) Text(discountLabel(discount), style = type.caption, color = colors.success)
            Row(Modifier.padding(top = spacing.xs), horizontalArrangement = Arrangement.spacedBy(spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                ArgonQuantityStepper(line.quantity, onQuantity, min = rule.min, max = rule.maximum, step = rule.step, size = ArgonSize.S, isEnabled = !busy)
                Box(
                    Modifier.size(44.dp).alpha(if (busy) 0.4f else 1f).clickable(enabled = !busy, role = Role.Button) { onQuantity(0) },
                    contentAlignment = Alignment.Center,
                ) {
                    ArgonIcon(ArgonIconName.Trash, size = 20.dp, tint = colors.muted, contentDescription = "Remove from cart")
                }
            }
        }
    }
}

/**
 * The discount code: a field with "Apply", and under it the cart's codes as tags, each with its ✕ (a code that has
 * stopped counting, after the cart changed, is the unfilled one). A code that can't be used on this cart says so under
 * the field. Writes run on the app's scope: leaving the tab doesn't drop them.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DiscountCode(cart: Cart, modifier: Modifier) {
    val spacing = ArgonTheme.spacing
    val focus = LocalFocusManager.current
    var code by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var applying by remember { mutableStateOf(false) }

    /** Runs a change of the cart's codes; what it returns, or how it failed, shows under the field. */
    fun write(change: suspend () -> String?) {
        applying = true
        error = null
        AppGraph.scope.launch {
            error = try {
                change()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                e.message ?: e.toString()
            }
            applying = false
        }
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(spacing.s)) {
        Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.Top) {
            ArgonInput("Discount code", code, { code = it; error = null }, Modifier.weight(1f), error = error, isEnabled = !applying)
            ArgonButton(
                "Apply",
                // beside the field's box, which starts under the room its label floats in
                Modifier.padding(top = FIELD_LABEL_ROOM).height(FIELD_HEIGHT),
                style = ArgonButtonStyle.Secondary,
                isLoading = applying,
                isEnabled = code.isNotBlank(),
            ) {
                val entered = code.trim()
                // the keyboard goes, so the answer (a tag, or the note under the field) and the summary are in view
                focus.clearFocus()
                write {
                    if (AppGraph.cart.applyDiscount(entered)) {
                        code = ""
                        null
                    } else {
                        "This code can't be used on your cart"
                    }
                }
            }
        }
        if (cart.discountCodes.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                for (discount in cart.discountCodes) {
                    ArgonTag(
                        discount.code,
                        style = ArgonTagStyle.Input,
                        isSelected = discount.applicable,
                        onRemove = { write { AppGraph.cart.removeDiscount(discount.code); null } },
                    )
                }
            }
        }
    }
}

// Material's outlined text field: 56 dp tall, under 8 dp of room for its floating label.
private val FIELD_LABEL_ROOM = 8.dp
private val FIELD_HEIGHT = 56.dp

/** The pinned summary: the totals, the note about what checkout adds, and "Checkout". */
@Composable
private fun Summary(summary: CartSummary, busy: Boolean, onCheckout: () -> Unit) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    ArgonDivider()
    Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
        SummaryRow("Subtotal", summary.subtotal.display(), type.body, colors.muted, colors.ink)
        if (!summary.discounts.isZero) SummaryRow("Discounts", "−${summary.discounts.display()}", type.body, colors.muted, colors.ink)
        if (!summary.savings.isZero) SummaryRow("You save", summary.savings.display(), type.body, colors.success, colors.success)
        SummaryRow("Total", summary.total.display(), type.headline, colors.ink, colors.ink)
        Text("Taxes and shipping are calculated at checkout", style = type.caption, color = colors.muted)
        ArgonButton("Checkout", Modifier.padding(top = spacing.xs), isEnabled = !busy, fullWidth = true, action = onCheckout)
    }
}

@Composable
private fun SummaryRow(label: String, value: String, style: TextStyle, labelColor: Color, valueColor: Color) =
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = style, color = labelColor)
        Text(value, style = style, color = valueColor)
    }
