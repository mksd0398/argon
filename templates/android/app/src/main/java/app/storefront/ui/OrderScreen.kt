package app.storefront.ui

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.storefront.AppGraph
import app.storefront.data.Money
import app.storefront.data.Order
import app.storefront.data.OrderLine
import coil3.compose.AsyncImage

/** "Fulfilled", "Unfulfilled", or each fulfillment's status. */
private fun fulfillment(statuses: List<String>) =
    if (statuses.isEmpty()) "Unfulfilled" else statuses.distinct().joinToString(", ") { if (it == "SUCCESS") "Fulfilled" else displayStatus(it) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrderScreen(id: String, nav: NavController) {
    Scaffold(topBar = { TopAppBar(title = { Text("Order") }, navigationIcon = { BackButton(nav) }) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ AppGraph.customerAccount.order(id) ?: error("Order not found") }) { OrderContent(it) }
        }
    }
}

@Composable
private fun OrderContent(order: Order) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text(order.name, style = MaterialTheme.typography.headlineSmall)
            Text(
                listOfNotNull(
                    displayDate(order.processedAt),
                    order.financialStatus?.let(::displayStatus),
                    fulfillment(order.fulfillments.mapNotNull { it.status }),
                )
                    .joinToString(" · "),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        items(order.lines) { OrderLineRow(it) }
        item {
            HorizontalDivider()
            order.subtotal?.let { Total("Subtotal", it) }
            Total("Total", order.total)
        }
    }
}

@Composable
private fun Total(label: String, money: Money) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.titleMedium)
        Text(money.display(), style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun OrderLineRow(line: OrderLine) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AsyncImage(
            model = line.image?.url,
            contentDescription = line.image?.alt ?: line.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(64.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
        )
        Column(Modifier.weight(1f)) {
            Text(line.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
            // a product without options has Shopify's one "Default Title" variant; nothing worth showing
            line.variantTitle?.takeIf { it != "Default Title" }?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("Qty ${line.quantity}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        line.total?.let { Text(it.display(), style = MaterialTheme.typography.bodyLarge) }
    }
}
