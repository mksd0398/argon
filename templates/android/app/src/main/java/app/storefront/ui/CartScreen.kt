package app.storefront.ui

import android.content.Context
import android.content.ContextWrapper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storefront.AppGraph
import app.storefront.data.Cart
import app.storefront.data.CartLine
import coil3.compose.AsyncImage
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

@OptIn(ExperimentalMaterial3Api::class)
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
        val processor = object : DefaultCheckoutEventProcessor(host) {
            override fun onCheckoutCompleted(checkoutCompletedEvent: CheckoutCompletedEvent) {
                AppGraph.scope.launch { AppGraph.cart.completed() }
            }

            override fun onCheckoutFailed(error: CheckoutException) {
                // the cart is kept; one Shopify no longer has (expired, already paid) is dropped by loading it again
                if (error is CheckoutExpiredException) AppGraph.scope.launch { runCatching { AppGraph.cart.load() } }
                screen.launch { snackbar.showSnackbar(error.errorDescription) }
            }

            override fun onCheckoutCanceled() {}
        }
        preload?.cancel()
        ShopifyCheckoutSheetKit.present(url, host, processor)
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Cart") }) },
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
                else -> Text("Your cart is empty", Modifier.align(Alignment.Center), style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}

@Composable
private fun CartContent(cart: Cart, busy: Boolean, onQuantity: (CartLine, Int) -> Unit, onCheckout: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(16.dp), contentPadding = PaddingValues(16.dp)) {
            items(cart.lines, key = { it.id }) { line -> CartLineRow(line, busy) { onQuantity(line, it) } }
        }
        HorizontalDivider()
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Subtotal", style = MaterialTheme.typography.titleMedium)
                Text(cart.subtotal.display(), style = MaterialTheme.typography.titleMedium)
            }
            Button(onClick = onCheckout, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Checkout") }
        }
    }
}

@Composable
private fun CartLineRow(line: CartLine, busy: Boolean, onQuantity: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AsyncImage(
            model = line.image?.url,
            contentDescription = line.image?.alt ?: line.productTitle,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(88.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(line.productTitle, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
            // a product without options has Shopify's one "Default Title" variant; nothing worth showing
            if (line.variantTitle != "Default Title") {
                Text(line.variantTitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Stepper(line.quantity, busy, onQuantity)
        }
        Text(line.total.display(), style = MaterialTheme.typography.bodyLarge)
    }
}

/** − and +; at 1 the − becomes a bin, because it removes the line. */
@Composable
private fun Stepper(quantity: Int, busy: Boolean, onChange: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onChange(quantity - 1) }, enabled = !busy) {
            if (quantity <= 1) {
                Icon(Icons.Filled.Delete, "Remove from cart")
            } else {
                Text("−", Modifier.semantics { contentDescription = "Decrease quantity" }, style = MaterialTheme.typography.titleLarge)
            }
        }
        Text("$quantity", Modifier.widthIn(min = 28.dp), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyLarge)
        IconButton(onClick = { onChange(quantity + 1) }, enabled = !busy) { Icon(Icons.Filled.Add, "Increase quantity") }
    }
}
