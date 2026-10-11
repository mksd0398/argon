package app.storefront.ui

import android.net.Uri
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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavController
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonProgressBar
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.ArgonApiError
import app.storefront.data.Fulfillment
import app.storefront.data.Order
import app.storefront.data.Return
import app.storefront.data.Route
import app.storefront.ui.account.ErrorText
import app.storefront.ui.account.InfoRow
import app.storefront.ui.account.Panel
import app.storefront.ui.account.addressLines
import app.storefront.ui.account.contactRoute
import app.storefront.ui.account.isPositive
import app.storefront.ui.orders.ItemRow
import app.storefront.ui.orders.ORDER_STEPS
import app.storefront.ui.orders.buyAgainMessage
import app.storefront.ui.orders.buyAgainPlan
import app.storefront.ui.orders.discountLabel
import app.storefront.ui.orders.itemDetails
import app.storefront.ui.orders.newestFirst
import app.storefront.ui.orders.orderProgressStep
import app.storefront.ui.orders.orderStatus
import app.storefront.ui.orders.paymentMethods
import app.storefront.ui.orders.quantityIn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** One order in full (`order/{id}`). */
@Composable
fun OrderScreen(id: String, nav: NavController) {
    Scaffold(topBar = { ArgonTopBar("Order", leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            // not kept: back from a return request, the order shows it
            Loader({ AppGraph.customerAccount.order(id) ?: error("Order not found") }, keep = false) { OrderContent(it, nav) }
        }
    }
}

@Composable
private fun OrderContent(order: Order, nav: NavController) {
    val spacing = ArgonTheme.spacing
    val openWeb: (String) -> Unit = { nav.open(Route.Web(it)) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.l)) {
        item { OrderHeader(order) }
        // a cancelled order goes nowhere, and one with nothing to ship (a gift card) has no shipment to follow
        if (order.cancelledAt == null && order.requiresShipping) item { OrderProgress(orderProgressStep(order.fulfillments.firstOrNull())) }
        // a cancelled shipment's tracking is nobody's news
        items(order.fulfillments.filter { it.status != "CANCELLED" }) { ShipmentCard(it, openWeb) }
        if (order.lines.isNotEmpty()) item { SectionHeader("Items") }
        items(order.lines) { line ->
            ItemRow(line.image, line.title, itemDetails(line.variantTitle, line.sku, line.quantity), trailing = (line.total ?: line.price)?.display())
        }
        item { OrderTotals(order, openWeb) }
        // an order with nothing to say about its payment (no status, no transactions, no terms) has no payment block
        val methods = paymentMethods(order.transactions)
        if (order.financialStatus != null || methods.isNotEmpty() || order.paymentInformation?.paymentTerms != null) item { OrderPayment(order, methods) }
        // where it ships, and where it is billed when that is somewhere else; a digital order has only the second
        val shipping = order.shippingAddress?.let(::addressLines).orEmpty()
        val billing = order.billingAddress?.let(::addressLines).orEmpty()
        if (shipping.isNotEmpty()) item { AddressPanel("Shipping address", shipping) }
        if (billing.isNotEmpty() && billing != shipping) item { AddressPanel("Billing address", billing) }
        if (order.purchasingCompany != null || !order.poNumber.isNullOrBlank()) item { OrderBusiness(order) }
        order.note?.takeIf { it.isNotBlank() }?.let { note ->
            item { Panel(title = "Note") { Text(note, style = ArgonTheme.type.body, color = ArgonTheme.colors.ink) } }
        }
        if (order.returns.isNotEmpty()) item { SectionHeader("Returns") }
        items(order.returns) { ReturnCard(it) }
        item { OrderActions(order, nav) }
    }
}

/** Name, date, the status tag and "Edited"; a cancelled order says when. */
@Composable
private fun OrderHeader(order: Order) = Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs)) {
    Text(order.name, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    Text(displayDate(order.processedAt), style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        ArgonTag(orderStatus(order), style = ArgonTagStyle.Info)
        if (order.edited) ArgonTag("Edited", style = ArgonTagStyle.Info)
    }
    order.cancelledAt?.let { Text("Cancelled on ${displayDate(it)}", style = ArgonTheme.type.label, color = ArgonTheme.colors.muted) }
}

/** The bar and its four steps; the ones reached are in ink. [step]: an index into [ORDER_STEPS]. */
@Composable
private fun OrderProgress(step: Int) = Column(
    Modifier.clearAndSetSemantics { contentDescription = "Order progress: ${ORDER_STEPS[step]}" },
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s),
) {
    ArgonProgressBar(step / (ORDER_STEPS.size - 1f))
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs)) {
        ORDER_STEPS.forEachIndexed { i, name ->
            Text(
                name,
                Modifier.weight(1f),
                style = ArgonTheme.type.caption,
                color = if (i <= step) ArgonTheme.colors.ink else ArgonTheme.colors.muted,
                textAlign = when (i) {
                    0 -> TextAlign.Start
                    ORDER_STEPS.lastIndex -> TextAlign.End
                    else -> TextAlign.Center
                },
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** One shipment: its carrier, tracking numbers, when it should arrive, what the carrier reported (newest first), and "Track package". */
@Composable
private fun ShipmentCard(fulfillment: Fulfillment, openWeb: (String) -> Unit) {
    val tracking = fulfillment.trackingInformation
    Panel(title = tracking.firstNotNullOfOrNull { it.company?.takeIf { name -> name.isNotBlank() } } ?: "Shipment") {
        for (number in tracking.mapNotNull { it.number?.takeIf { n -> n.isNotBlank() } }) InfoRow("Tracking number", number)
        // an estimate is old news once the parcel is there
        if (orderProgressStep(fulfillment) < ORDER_STEPS.lastIndex) {
            fulfillment.estimatedDeliveryAt?.let { InfoRow("Estimated delivery", displayDate(it)) }
        }
        for (event in newestFirst(fulfillment)) InfoRow(displayStatus(event.status), event.happenedAt?.let(::displayDate).orEmpty())
        for (url in tracking.mapNotNull { it.url?.takeIf { u -> u.isNotBlank() } }) {
            ArgonButton("Track package", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, icon = ArgonIconName.Truck) { openWeb(url) }
        }
    }
}

/** Subtotal, discounts, shipping (with its method), tax, total, what was refunded, and what is still to pay with "Pay now". */
@Composable
private fun OrderTotals(order: Order, openWeb: (String) -> Unit) = Panel {
    order.subtotal?.let { InfoRow("Subtotal", it.display()) }
    for (discount in order.discountApplications.mapNotNull { discountLabel(it.value) }) InfoRow("Discount", discount)
    order.totalShipping?.let { InfoRow("Shipping", it.display(), note = order.shippingLine?.title) }
    order.totalTax?.let { InfoRow("Tax", it.display()) }
    InfoRow("Total", order.total.display(), strong = true)
    order.totalRefunded?.takeIf { it.isPositive() }?.let { InfoRow("Refunded", it.display()) }
    order.paymentInformation?.totalOutstandingAmount?.takeIf { it.isPositive() }?.let { outstanding ->
        InfoRow("Outstanding", outstanding.display())
        order.paymentInformation.paymentCollectionUrl?.let { url -> ArgonButton("Pay now", fullWidth = true) { openWeb(url) } }
    }
}

/** Whether it is paid, how it was paid ([methods]), and a company's payment terms with their due date. */
@Composable
private fun OrderPayment(order: Order, methods: List<String>) = Panel(title = "Payment") {
    val terms = order.paymentInformation?.paymentTerms
    order.financialStatus?.let { InfoRow("Status", displayStatus(it)) }
    for (method in methods) Text(method, style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
    terms?.paymentTermsName?.let { InfoRow("Payment terms", it) }
    terms?.nextDueAt?.let { InfoRow("Due", displayDate(it)) }
    if (terms?.overdue == true) ErrorText("Overdue")
}

@Composable
private fun AddressPanel(title: String, lines: List<String>) = Panel(title = title) {
    Text(lines.joinToString("\n"), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
}

/** A company order's PO number, company and location. */
@Composable
private fun OrderBusiness(order: Order) = Panel(title = "Business details") {
    order.poNumber?.takeIf { it.isNotBlank() }?.let { InfoRow("PO number", it) }
    order.purchasingCompany?.let {
        InfoRow("Company", it.company.name)
        InfoRow("Location", it.location.name)
    }
}

/** A return: its name, status and date, what went back and why, what comes instead, and why the store declined it. */
@Composable
private fun ReturnCard(item: Return) = Panel {
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(item.name ?: "Return", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            item.createdAt?.let { Text(displayDate(it), style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted) }
        }
        ArgonTag(displayStatus(item.status), style = ArgonTagStyle.Info)
    }
    for (line in item.lines) {
        ItemRow(line.image, line.title ?: "Item", itemDetails(line.variantTitle, null, line.quantity) + listOfNotNull(line.reason))
    }
    if (item.exchangeLines.isNotEmpty()) Text("Exchanged for", style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
    for (line in item.exchangeLines) ItemRow(line.image, line.title, itemDetails(line.variantTitle, null, line.quantity))
    item.decline?.let { decline ->
        val why = listOfNotNull(decline.reason?.let(::displayStatus), decline.note?.takeIf { it.isNotBlank() }).joinToString(": ")
        ErrorText(if (why.isEmpty()) "Declined" else "Declined: $why")
    }
}

/** "Return or exchange items" (when something can go back), "Buy again", "View order status page" and "Need help?". */
@Composable
private fun OrderActions(order: Order, nav: NavController) = Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
    var buying by remember { mutableStateOf(false) }
    if (order.hasReturnableItems) {
        ArgonButton("Return or exchange items", fullWidth = true) { nav.navigate("return/${Uri.encode(order.id)}") }
    }
    if (order.lines.isNotEmpty()) {
        ArgonButton("Buy again", style = ArgonButtonStyle.Secondary, isLoading = buying, fullWidth = true) {
            buying = true
            // on the app's scope: leaving the order doesn't drop the cart writes
            AppGraph.scope.launch {
                try {
                    AppGraph.toast.show(buyAgain(order))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    AppGraph.toast.show(e.message ?: "Couldn't update the cart")
                } finally {
                    buying = false
                }
            }
        }
    }
    // the store's own order page: whatever its apps add to customer accounts shows there
    order.statusPageUrl?.let { url ->
        ArgonButton("View order status page", style = ArgonButtonStyle.Secondary, icon = ArgonIconName.External, fullWidth = true) { nav.open(Route.Web(url)) }
    }
    ArgonButton("Need help?", style = ArgonButtonStyle.Tertiary, fullWidth = true) { nav.open(contactRoute()) }
}

/**
 * Puts the order's items in the cart again, one variant at a time, and returns what to tell the shopper. An item Shopify
 * refuses, or takes without the cart gaining any of it (sold out), is named as no longer available; anything else that
 * goes wrong (no connection) is thrown.
 * ponytail: one cart call per variant (`CartStore.add` takes one). Give the cart store an add of several lines when
 * orders with many lines make this slow.
 */
private suspend fun buyAgain(order: Order): String {
    val plan = buyAgainPlan(order.lines)
    val unavailable = plan.unavailable.toMutableList()
    var added = 0
    for (line in plan.lines) {
        val before = quantityIn(AppGraph.cart.cart.value, line.variantId)
        try {
            AppGraph.cart.add(line.variantId, line.quantity)
        } catch (e: ArgonApiError.UserErrors) {
            // Shopify's answer for this one item (it no longer exists, or its quantity rule says no): the rest still go in
        }
        if (quantityIn(AppGraph.cart.cart.value, line.variantId) > before) added++ else unavailable += line.title
    }
    return buyAgainMessage(added, unavailable.distinct())
}
