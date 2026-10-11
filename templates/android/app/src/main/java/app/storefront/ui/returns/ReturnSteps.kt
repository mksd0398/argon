package app.storefront.ui.returns

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonGroup
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCheckbox
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonDropdown
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonProgressBar
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonSpinner
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTextArea
import app.storefront.AppGraph
import app.storefront.data.Product
import app.storefront.data.Return
import app.storefront.data.ReturnableLineItem
import app.storefront.data.Variants
import app.storefront.ui.account.ErrorText
import app.storefront.ui.account.InfoRow
import app.storefront.ui.account.Panel
import app.storefront.ui.display
import app.storefront.ui.displayStatus
import app.storefront.ui.orders.ItemRow
import app.storefront.ui.orders.itemDetails
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private const val EXCHANGE_HINT = "The store confirms exchanges by email."

/**
 * The returns flow of the order with id [orderId]: its three steps, then the request's outcome. [onBackToOrder] leaves
 * the flow.
 */
@Composable
fun ReturnFlowView(flow: ReturnFlow, orderId: String, onBackToOrder: () -> Unit) {
    val done = flow.submitted
    when {
        done != null -> ReturnRequested(done, exchange = flow.chosen.any { flow.choice(it).exchange }, onBackToOrder)
        flow.items.isEmpty() -> NothingToReturn(flow.options.nonReturnableSummary, onBackToOrder)
        else -> ReturnSteps(flow, orderId)
    }
}

/** The step's progress and title, its content, and "Back" / "Continue" (the last step: "Submit request") under it. */
@Composable
private fun ReturnSteps(flow: ReturnFlow, orderId: String) {
    val spacing = ArgonTheme.spacing
    val last = flow.step == RETURN_STEPS.lastIndex
    // what stops "Continue"; said once it was tapped on this step, and gone as soon as it is put right
    val problem = stepProblem(flow.step, flow.chosen.map { it to flow.choice(it) })
    var tapped by remember(flow.step) { mutableStateOf(false) }
    BackHandler(enabled = flow.step > 0 && !flow.submitting) { flow.step-- }

    fun next() {
        tapped = true
        if (problem != null) return
        if (last) submit(flow, orderId) else flow.step++
    }

    Column(Modifier.fillMaxSize()) {
        // keyed by the step: each one starts at its top
        key(flow.step) {
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.l)) {
                // in the list, so it scrolls away and leaves the room to a note being typed
                item { StepHeader(flow.step) }
                when (flow.step) {
                    0 -> chooseItems(flow)
                    1 -> items(flow.chosen, key = { it.lineItem.id }) { item -> Resolution(flow, item, showProblem = tapped) }
                    else -> review(flow)
                }
            }
        }
        ArgonDivider()
        Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            // why the step isn't done, or (the last step) why the request didn't go through
            ErrorText(if (tapped && problem != null) problem else flow.error.takeIf { last })
            Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                if (flow.step > 0) {
                    ArgonButton("Back", Modifier.weight(1f), style = ArgonButtonStyle.Secondary, isEnabled = !flow.submitting) { flow.step-- }
                }
                ArgonButton(if (last) "Submit request" else "Continue", Modifier.weight(1f), isLoading = flow.submitting, action = { next() })
            }
        }
    }
}

/** How far the flow is (the bar and "Step 2 of 3") and the step's title. */
@Composable
private fun StepHeader(step: Int) = Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
    ArgonProgressBar((step + 1) / RETURN_STEPS.size.toFloat())
    Text("Step ${step + 1} of ${RETURN_STEPS.size}", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    Text(RETURN_STEPS[step], Modifier.semantics { heading() }, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
}

/** Sends the request on the app's scope (leaving the screen doesn't drop it); the flow shows how it went. */
private fun submit(flow: ReturnFlow, orderId: String) {
    flow.submitting = true
    flow.error = null
    AppGraph.scope.launch {
        try {
            flow.submitted = AppGraph.customerAccount.requestReturn(orderId, returnLines(flow.items, flow.choices))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            flow.error = e.message ?: e.toString()
        } finally {
            flow.submitting = false
        }
    }
}

// Step 1

/** Each returnable item with its checkbox and, once chosen, how many of it go back; then why the rest can't. */
private fun LazyListScope.chooseItems(flow: ReturnFlow) {
    items(flow.items, key = { it.lineItem.id }) { item -> ChooseItem(item, flow.choice(item)) { change -> flow.update(item, change) } }
    flow.options.nonReturnableSummary?.takeIf { it.isNotBlank() }?.let { summary ->
        item { Text(summary, style = ArgonTheme.type.label, color = ArgonTheme.colors.muted) }
    }
}

@Composable
private fun ChooseItem(item: ReturnableLineItem, choice: ReturnChoice, onChange: ((ReturnChoice) -> ReturnChoice) -> Unit) {
    val line = item.lineItem
    val checked = choice.quantity > 0
    val toggle: (Boolean) -> Unit = { on -> onChange { it.copy(quantity = if (on) 1 else 0) } }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.Top) {
        ArgonCheckbox(checked, toggle)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
            ItemRow(
                line.image,
                line.title,
                itemDetails(line.variantTitle, line.sku, null),
                Modifier.clickable { toggle(!checked) },
                trailing = line.price?.display(),
            )
            if (checked && item.quantity > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.CenterVertically) {
                    ArgonQuantityStepper(choice.quantity, { quantity -> onChange { it.copy(quantity = quantity) } }, max = item.quantity, size = ArgonSize.S)
                    Text("of ${item.quantity}", style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
                }
            }
        }
    }
}

// Step 2

/** One chosen item: refund or exchange, the reason, the replacement (an exchange), and a note. */
@Composable
private fun Resolution(flow: ReturnFlow, item: ReturnableLineItem, showProblem: Boolean) {
    val line = item.lineItem
    val choice = flow.choice(item)
    val reasons = line.suggestedReturnReasonDefinitions
    Panel {
        ItemRow(line.image, line.title, itemDetails(line.variantTitle, null, choice.quantity))
        ArgonButtonGroup(listOf("Refund", "Exchange"), if (choice.exchange) 1 else 0, { index -> flow.update(item) { it.copy(exchange = index == 1) } })
        if (reasons.isNotEmpty()) {
            ArgonDropdown(
                "Reason",
                reasons.map { it.name },
                reasons.indexOfFirst { it.id == choice.reasonId }.takeIf { it >= 0 },
                { index -> flow.update(item) { it.copy(reasonId = reasons[index].id) } },
            )
        }
        if (choice.exchange) {
            Replacement(flow, item)
            Text(EXCHANGE_HINT, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        }
        ArgonTextArea("Note (optional)", choice.note, { text -> flow.update(item) { it.copy(note = text) } }, minLines = 2, maxLength = noteLimit(choice))
        if (showProblem) ErrorText(choiceProblem(item, choice))
    }
}

/**
 * The product of the item being exchanged, with its options and variants; null when it can't be had.
 * ponytail: the Product query loads the first 250 variants, so a product with more shows "Unavailable" for the ones that
 * didn't load (as the product page does). Ask `variantBySelectedOptions` for each selection when a store needs more.
 */
private suspend fun loadProduct(productId: String?): Product? = try {
    // an order line knows its product's id, the product query wants its handle
    val handle = productId?.let { AppGraph.storefront.productsByIds(listOf(it)).firstOrNull()?.handle }
    handle?.let { AppGraph.storefront.product(it) }
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    null
}

/**
 * What the shopper wants instead: the product's options to pick the replacement variant from. While the product loads, a
 * spinner; when it can't be loaded, a field to say it in words.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Replacement(flow: ReturnFlow, item: ReturnableLineItem) {
    val line = item.lineItem
    val choice = flow.choice(item)
    val loaded = flow.products[line.id]
    LaunchedEffect(line.id) {
        if (flow.products[line.id] != null) return@LaunchedEffect
        val product = loadProduct(line.productId)
        if (product != null) {
            val start = startSelection(product, line.variantId)
            flow.update(item) { it.copy(selection = start, wanted = wantedVariant(product, start)) }
        }
        flow.products[line.id] = ExchangeProduct(product)
    }
    val product = loaded?.product
    when {
        loaded == null -> Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
            ArgonSpinner(ArgonSize.S)
            Text("Loading options", style = ArgonTheme.type.label, color = ArgonTheme.colors.muted)
        }
        product == null -> ArgonInput("What would you like instead?", choice.wanted, { text -> flow.update(item) { it.copy(wanted = text) } })
        else -> {
            Text("Exchange for", style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
            for (option in choosableOptions(product)) {
                Text("${option.name}: ${choice.selection[option.name].orEmpty()}", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
                    for (value in option.values) {
                        ArgonTag(
                            value,
                            isSelected = choice.selection[option.name] == value,
                            onClick = {
                                val selection = choice.selection + (option.name to value)
                                flow.update(item) { it.copy(selection = selection, wanted = wantedVariant(product, selection)) }
                            },
                        )
                    }
                }
            }
            // what the selection comes to: the variant by name, or why it can't be had
            val variant = Variants.match(product.variants, choice.selection)
            when {
                variant == null -> ErrorText("Unavailable")
                !variant.available -> ErrorText("Sold out")
                else -> Text(choice.wanted, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
            }
        }
    }
}

// Step 3

/** The chosen items with what was asked for each, what the return costs, and how it ships back. */
private fun LazyListScope.review(flow: ReturnFlow) {
    item {
        Panel(title = "Items") {
            for (item in flow.chosen) ItemRow(item.lineItem.image, item.lineItem.title, reviewDetails(item, flow.choice(item)))
        }
    }
    val fees = feeRows(flow.options)
    if (fees.isNotEmpty()) {
        item { Panel(title = "Fees") { for ((label, amount) in fees) InfoRow(label, amount) } }
    }
    item {
        Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
            flow.options.returnShippingMethodNote?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
            }
            if (flow.chosen.any { flow.choice(it).exchange }) Text(EXCHANGE_HINT, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
        }
    }
}

// Outcomes

/** The request went through: the return's name and status, and the way back to the order. */
@Composable
private fun ReturnRequested(done: Return, exchange: Boolean, onBackToOrder: () -> Unit) = Outcome("Back to order", onBackToOrder) {
    ArgonIcon(ArgonIconName.Check, size = 40.dp, tint = ArgonTheme.colors.success)
    Text("Return requested", style = ArgonTheme.type.title, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center)
    Text(
        listOfNotNull(done.name, displayStatus(done.status)).joinToString(" · "),
        style = ArgonTheme.type.body,
        color = ArgonTheme.colors.ink,
        textAlign = TextAlign.Center,
    )
    if (exchange) Text(EXCHANGE_HINT, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center)
}

/** Nothing on the order can go back (any more): the store's reason, when it gives one. */
@Composable
private fun NothingToReturn(summary: String?, onBackToOrder: () -> Unit) = Outcome("Back to order", onBackToOrder) {
    Text("Nothing on this order can be returned", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center)
    if (!summary.isNullOrBlank()) Text(summary, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center)
}

/** A centred message with one button under it. */
@Composable
private fun Outcome(button: String, onClick: () -> Unit, content: @Composable () -> Unit) = Column(
    Modifier.fillMaxSize().padding(ArgonTheme.spacing.xxl),
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    content()
    ArgonButton(button, fullWidth = true, action = onClick)
}
