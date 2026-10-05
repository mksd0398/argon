package app.storefront.ui

import android.net.Uri
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.Customer
import app.storefront.data.Route
import app.storefront.data.obj
import app.storefront.data.parseCustomer
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/** "Oct 1, 2026" in the device's zone and locale. */
internal fun displayDate(iso: String): String = runCatching {
    Instant.parse(iso).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
}.getOrDefault(iso)

/** PARTIALLY_REFUNDED -> "Partially refunded". */
internal fun displayStatus(status: String) = status.lowercase().replace('_', ' ').replaceFirstChar { it.uppercase() }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(nav: NavController) {
    Scaffold(topBar = { TopAppBar(title = { Text("Account") }) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val signedIn by AppGraph.auth.signedIn.collectAsState()
            when {
                // the CLI lets a store skip the Customer Account client: no client id, no sign-in
                AppGraph.customerClientId.isBlank() -> Centered {
                    Text("Sign-in isn't configured for this store", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                    Text(
                        "Set CUSTOMER_CLIENT_ID in android/shopify.properties",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
                // not kept: a new order shows on the next visit, and nothing of this customer outlives a sign-out
                signedIn -> Loader(::loadCustomer, keep = false) { CustomerContent(it, nav) }
                else -> SignedOut()
            }
        }
    }
}

private suspend fun loadCustomer() =
    parseCustomer(AppGraph.auth.customerQuery("Customer", JsonObject(emptyMap())).obj("customer") ?: error("Account not found"))

@Composable
private fun Centered(content: @Composable () -> Unit) = Column(
    Modifier.fillMaxSize().padding(32.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) { content() }

@Composable
private fun SignedOut() {
    val context = LocalContext.current
    val screen = rememberCoroutineScope()
    val callbackError by AppGraph.auth.signInError.collectAsState()
    var starting by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }

    // Discovery runs first, so a store without the Customer Account API fails here (error + Retry), before any browser opens.
    fun signIn() {
        starting = true
        failure = null
        screen.launch {
            try {
                AppGraph.auth.signIn { url -> CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e.message ?: e.toString()
            } finally {
                starting = false
            }
        }
    }

    val error = failure
    when {
        starting -> Spinner()
        error != null -> ErrorView(error, ::signIn)
        else -> Centered {
            callbackError?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
            Button(onClick = ::signIn) { Text("Sign in") }
        }
    }
}

@Composable
private fun CustomerContent(customer: Customer, nav: NavController) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 16.dp)) {
        item {
            Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp)) {
                if (customer.name.isNotBlank()) Text(customer.name, style = MaterialTheme.typography.headlineSmall)
                customer.email?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Text("Orders", Modifier.padding(16.dp, 8.dp), style = MaterialTheme.typography.titleMedium)
            if (customer.orders.isEmpty()) Text("No orders yet", Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        items(customer.orders, key = { it.id }) { order ->
            Row(
                Modifier.fillMaxWidth().clickable { nav.navigate("order/${Uri.encode(order.id)}") }.padding(16.dp, 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(order.name, style = MaterialTheme.typography.bodyLarge)
                    Text(
                        listOfNotNull(displayDate(order.processedAt), order.financialStatus?.let(::displayStatus)).joinToString(" · "),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(order.total.display(), style = MaterialTheme.typography.bodyLarge)
            }
            HorizontalDivider()
        }
        item {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = {
                        // on the app's scope: signing out finishes even if the shopper leaves the tab
                        AppGraph.scope.launch {
                            try {
                                // the cart too: one the customer was attached to would still check out as them (shopify.dev
                                // Checkout Kit "Authenticate checkouts": clear the stored tokens and authenticated carts).
                                // Only here, on an explicit sign-out: a session that ends mid-checkout must not lose the cart.
                                // First, so a slow or failing logout call can't leave it behind.
                                AppGraph.cart.completed()
                                AppGraph.auth.signOut()
                            } catch (e: Exception) {
                                Log.w("Account", "sign-out failed", e)
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Sign out") }
                // no API deletes a customer account, so the store's contact page takes the request (Apple and Google require the entry)
                TextButton(
                    onClick = { nav.open(Route.Web("https://${AppGraph.shopDomain}/pages/contact")) },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Delete account", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}
