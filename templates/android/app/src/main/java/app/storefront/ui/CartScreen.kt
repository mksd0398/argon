package app.storefront.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.Cart
import app.storefront.data.CartLine
import app.storefront.data.CartLineComponent
import app.storefront.data.QuantityRule
import com.shopify.checkoutsheetkit.CheckoutException
import com.shopify.checkoutsheetkit.CheckoutExpiredException
import com.shopify.checkoutsheetkit.DefaultCheckoutEventProcessor
import com.shopify.checkoutsheetkit.ShopifyCheckoutSheetKit
import com.shopify.checkoutsheetkit.lifecycleevents.CheckoutCompletedEvent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Checkout Kit needs a ComponentActivity; the composition's context may be a wrapper around one. */
private tailrec fun Context.componentActivity(): ComponentActivity? = when (this) {
    is ComponentActivity -> this
    is ContextWrapper -> baseContext.componentActivity()
    else -> null
}

/**
 * Shows Shopify's checkout for [url] (`CartStore.checkoutUrl`) over [host]: the cart screen's "Checkout" and the product
 * page's "Buy now". A placed order spends the cart. A checkout that fails keeps it and hands the reason to [onError];
 * one Shopify no longer has (expired, already paid) is dropped by loading the cart again.
 */
internal fun presentCheckout(url: String, host: ComponentActivity, onError: (String) -> Unit) {
    val processor = object : DefaultCheckoutEventProcessor(host) {
        override fun onCheckoutCompleted(checkoutCompletedEvent: CheckoutCompletedEvent) {
            AppGraph.scope.launch { AppGraph.cart.completed() }
        }

        override fun onCheckoutFailed(error: CheckoutException) {
            if (error is CheckoutExpiredException) AppGraph.scope.launch { runCatching { AppGraph.cart.load() } }
            onError(error.errorDescription)
        }

        override fun onCheckoutCanceled() {}
    }
    ShopifyCheckoutSheetKit.present(url, host, processor)
}

/** "Men's T-shirt · Small / Olive × 1": a bundle's part on a cart line (the variant left out when it is "Default Title"). */
internal fun componentLabel(part: CartLineComponent): String =
    listOfNotNull(part.productTitle.takeIf { it.isNotBlank() }, part.variantTitle.takeIf { it != "Default Title" }).joinToString(" · ") + " × ${part.quantity}"

@Composable
fun CartScreen() {
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
        Box(Modifier.padding(padding).fillMaxSize()) {
            val current = cart
            val error = failure
            when {
                current != null && current.lines.isNotEmpty() -> CartContent(
                    current,
                    busy,
                    onQuantity = { line, quantity -> act(AppGraph.scope) { AppGraph.cart.update(line.id, quantity) } },
                    onCheckout = { activity?.let(::checkout) },
                )
                loading && current == null -> Spinner()
                error != null && current == null -> ErrorView(error) { attempt++ }
                else -> Text("Your cart is empty", Modifier.align(Alignment.Center), style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
            }
        }
    }
}

@Composable
private fun CartContent(cart: Cart, busy: Boolean, onQuantity: (CartLine, Int) -> Unit, onCheckout: () -> Unit) {
    val spacing = ArgonTheme.spacing
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.l), contentPadding = PaddingValues(spacing.l)) {
            items(cart.lines, key = { it.id }) { line -> CartLineRow(line, busy) { onQuantity(line, it) } }
        }
        ArgonDivider()
        Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Subtotal", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
                Text(cart.subtotal.display(), style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
            }
            ArgonButton("Checkout", isEnabled = !busy, fullWidth = true, action = onCheckout)
        }
    }
}

/**
 * A cart line: image, product, variant, the selling plan it is bought on, a bundle's parts, then the quantity on the
 * variant's quantity rule (its minimum, maximum and increments) with a bin beside it that removes the line.
 * [onQuantity] gets the new quantity; 0 removes the line.
 */
@Composable
private fun CartLineRow(line: CartLine, busy: Boolean, onQuantity: (Int) -> Unit) {
    val spacing = ArgonTheme.spacing
    val type = ArgonTheme.type
    val colors = ArgonTheme.colors
    val rule = line.merchandise.quantityRule ?: QuantityRule()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
        StoreImage(line.image, line.productTitle, Modifier.size(88.dp).clip(ArgonTheme.radius.m))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.xxs)) {
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                Text(line.productTitle, Modifier.weight(1f), style = type.label, color = colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(line.total.display(), style = type.label, color = colors.ink, maxLines = 1)
            }
            // a product without options has Shopify's one "Default Title" variant; nothing worth showing
            if (line.variantTitle != "Default Title") Text(line.variantTitle, style = type.caption, color = colors.muted)
            line.sellingPlanName?.let { Text(it, style = type.caption, color = colors.muted) }
            for (part in line.components) Text(componentLabel(part), style = type.caption, color = colors.muted)
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
