package app.storefront.ui

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.OrderSummary
import app.storefront.data.Page
import app.storefront.ui.account.ErrorText
import app.storefront.ui.orders.OrderCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * The customer's orders, newest first, a page at a time. Kept with the screen (it is what the screen's [Loader] loads),
 * so coming back from an order finds the list as it was.
 */
private class OrderList(first: Page<OrderSummary>) {
    // each order once: the list is keyed by order id
    var items by mutableStateOf(first.items.distinctBy { it.id })
        private set
    var hasNext by mutableStateOf(first.hasNextPage && first.endCursor != null)
        private set
    var loading by mutableStateOf(false)
        private set

    /** Why the last "Load more" failed. */
    var error by mutableStateOf<String?>(null)
        private set
    private var cursor = first.endCursor

    suspend fun loadMore() {
        if (loading || !hasNext) return
        loading = true
        error = null
        try {
            val page = AppGraph.customerAccount.orders(cursor)
            items = (items + page.items).distinctBy { it.id }
            cursor = page.endCursor
            // without a cursor "more" could only repeat this page
            hasNext = page.hasNextPage && page.endCursor != null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: e.toString()
        } finally {
            loading = false
        }
    }
}

/** The customer's orders, newest first (`orders`). */
@Composable
fun OrdersScreen(nav: NavController) {
    Scaffold(topBar = { ArgonTopBar("Orders", leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ OrderList(AppGraph.customerAccount.orders()) }) { list ->
                if (list.items.isEmpty()) {
                    NoOrders(
                        onShop = {
                            // back to the account first, so its tab doesn't reopen on this empty list
                            nav.popBackStack()
                            AppGraph.tabs.select(AppTab.Shop)
                        },
                    )
                } else {
                    Orders(list, onOpen = { nav.navigate("order/${Uri.encode(it.id)}") })
                }
            }
        }
    }
}

@Composable
private fun Orders(list: OrderList, onOpen: (OrderSummary) -> Unit) {
    val spacing = ArgonTheme.spacing
    val screen = rememberCoroutineScope()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        items(list.items, key = { it.id }) { order -> OrderCard(order, onOpen = { onOpen(order) }) }
        if (list.hasNext) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(spacing.s)) {
                    ErrorText(list.error)
                    ArgonButton("Load more", style = ArgonButtonStyle.Secondary, isLoading = list.loading, fullWidth = true) {
                        screen.launch { list.loadMore() }
                    }
                }
            }
        }
    }
}

@Composable
private fun NoOrders(onShop: () -> Unit) = Column(
    Modifier.fillMaxSize().padding(ArgonTheme.spacing.xxl),
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    ArgonIcon(ArgonIconName.Bag, tint = ArgonTheme.colors.muted)
    Text("No orders yet", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center)
    Text("Your orders will show here.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center)
    ArgonButton("Start shopping", action = onShop)
}
