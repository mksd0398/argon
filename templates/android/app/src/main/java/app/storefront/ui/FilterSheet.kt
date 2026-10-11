package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonBottomSheet
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCheckbox
import app.argon.ui.components.ArgonRadioGroup
import app.argon.ui.components.ArgonRangeSlider
import app.argon.ui.components.ArgonSheetDetent
import app.argon.ui.components.ArgonSwatch
import app.argon.ui.components.ArgonSwitch
import app.storefront.data.Filter
import app.storefront.data.FilterValue
import app.storefront.data.Money
import app.storefront.data.isColorName
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/** How the filter sheet shows a filter. */
internal enum class FilterControl { Slider, Switch, Swatches, Checkboxes }

/**
 * The control for [filter]: a slider for a price range, a switch for a boolean, and for a list checkboxes, or swatches
 * when it is a colour filter (the store presents it as swatches, a value has a swatch, or it is named colour, color or
 * shade). Null when it has nothing to choose: no values, or a price range without bounds.
 */
internal fun filterControl(filter: Filter): FilterControl? = when {
    filter.type == "PRICE_RANGE" -> FilterControl.Slider.takeIf { priceSlider(filter) != null }
    filter.values.isEmpty() -> null
    filter.type == "BOOLEAN" -> FilterControl.Switch
    filter.presentation == "SWATCH" || filter.values.any { it.swatch != null } || isColorName(filter.label) -> FilterControl.Swatches
    else -> FilterControl.Checkboxes
}

/** The value a BOOLEAN [filter]'s switch turns on: the one whose input says true, else its first. */
internal fun booleanValue(filter: Filter): FilterValue? =
    filter.values.firstOrNull { "true" in it.input.lowercase() } ?: filter.values.firstOrNull()

// Price. A price filter is one entry of the selection, Shopify's `ProductFilter` `{"price":{"min":10.0,"max":50.0}}`.

/** The `min` and `max` of a `{"price":{...}}` filter input (either may be missing); null for any other input. */
internal fun priceRange(input: String): Pair<Float?, Float?>? {
    val price = runCatching { Json.parseToJsonElement(input).jsonObject["price"]?.jsonObject }.getOrNull() ?: return null
    fun bound(key: String) = (price[key] as? JsonPrimitive)?.floatOrNull?.takeIf { it.isFinite() }
    return bound("min") to bound("max")
}

/** The price range selected in [applied]; null when there is none. */
internal fun priceSelection(applied: List<String>): Pair<Float?, Float?>? = applied.firstNotNullOfOrNull(::priceRange)

/** `{"price":{"min":10.0,"max":50.0}}`: the filter input for the prices from [lower] to [upper]. */
internal fun priceInput(lower: Float, upper: Float): String = buildJsonObject {
    put("price", buildJsonObject {
        put("min", lower)
        put("max", upper)
    })
}.toString()

/**
 * [applied] with [lower]...[upper] as its one price entry; with no price entry when that is the whole of [bounds] (all
 * prices: nothing to filter).
 */
internal fun withPrice(applied: List<String>, lower: Float, upper: Float, bounds: ClosedFloatingPointRange<Float>): List<String> {
    val others = applied.filter { priceRange(it) == null }
    return if (lower <= bounds.start && upper >= bounds.endInclusive) others else others + priceInput(lower, upper)
}

/** A price filter's slider: the [bounds] its two thumbs move in, and the [step] they move by. */
internal data class PriceSlider(val bounds: ClosedFloatingPointRange<Float>, val step: Float)

/**
 * The slider of a PRICE_RANGE [filter]. Its bounds are the `min` and `max` of the filter value's own `input`
 * (`{"price":{"min":0,"max":120}}`: the list's lowest and highest price), widened to whole steps so the highest price
 * stays inside. Null when there is no range to choose in.
 */
internal fun priceSlider(filter: Filter): PriceSlider? {
    val (min, max) = filter.values.firstNotNullOfOrNull { priceRange(it.input) } ?: return null
    val low = min ?: 0f
    if (max == null || max <= low) return null
    val step = priceStep(max - low)
    return PriceSlider(floor(low / step) * step..ceil(max / step) * step, step)
}

/** The smallest of 1, 2, 5, 10, 20, 50, ... that crosses [span] in 100 steps or fewer. */
internal fun priceStep(span: Float): Float =
    generateSequence(1f) { it * 10 }.flatMap { magnitude -> sequenceOf(1f, 2f, 5f).map { it * magnitude } }.first { span / it <= 100 }

/** A price at a slider's end or on a tag: in [currencyCode] when the list has shown one, else the bare number. */
internal fun priceText(value: Float, currencyCode: String?): String =
    if (currencyCode != null) Money(value.toString(), currencyCode).display() else value.roundToInt().toString()

/** The sorts of a product list to choose from; choosing one applies it ([onSelect] closes the sheet). */
@Composable
fun SortSheet(isPresented: Boolean, sorts: List<Sort>, selected: Sort, onSelect: (Sort) -> Unit, onDismiss: () -> Unit) =
    ArgonBottomSheet(isPresented, onDismiss, detents = setOf(ArgonSheetDetent.Medium)) {
        val spacing = ArgonTheme.spacing
        SheetTitle("Sort", Modifier.padding(horizontal = spacing.l))
        ArgonRadioGroup(
            sorts.map { it.label },
            sorts.indexOf(selected).takeIf { it >= 0 },
            { onSelect(sorts[it]) },
            Modifier.padding(start = spacing.l, end = spacing.l, bottom = spacing.xl),
        )
    }

/**
 * The filters of a product list, one section each ([filterControl] says which control a filter gets). A change applies
 * at once: [onChange] gets the new selection (the selected values' `input` JSON, a price range as one
 * `{"price":{...}}`), the list reloads behind the sheet, and the button that closes it says what is left ([results],
 * "14 products"; null while that loads). "Clear" takes every filter off. [scrollTo] is the id of the filter to open at.
 */
@Composable
fun FilterSheet(
    isPresented: Boolean,
    filters: List<Filter>,
    applied: List<String>,
    onChange: (List<String>) -> Unit,
    onDismiss: () -> Unit,
    results: String? = null,
    currencyCode: String? = null,
    scrollTo: String? = null,
) = ArgonBottomSheet(isPresented, onDismiss, detents = setOf(ArgonSheetDetent.Large)) {
    val spacing = ArgonTheme.spacing
    SheetTitle("Filters", Modifier.padding(horizontal = spacing.l))
    LazyColumn(
        Modifier.weight(1f, fill = false),
        state = rememberLazyListState(filters.indexOfFirst { it.id == scrollTo }.coerceAtLeast(0)),
        contentPadding = PaddingValues(horizontal = spacing.l, vertical = spacing.m),
        verticalArrangement = Arrangement.spacedBy(spacing.l),
    ) {
        items(filters) { filter -> FilterSection(filter, applied, onChange, currencyCode) }
    }
    Row(Modifier.fillMaxWidth().padding(spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
        ArgonButton("Clear", style = ArgonButtonStyle.Tertiary, isEnabled = applied.isNotEmpty()) { onChange(emptyList()) }
        ArgonButton(if (results != null) "Show $results" else "Show products", Modifier.weight(1f), action = onDismiss)
    }
}

/** A sheet's title; with [section], the smaller heading of one of its sections. */
@Composable
private fun SheetTitle(text: String, modifier: Modifier = Modifier, section: Boolean = false) = Text(
    text,
    modifier.semantics { heading() },
    style = if (section) ArgonTheme.type.headline else ArgonTheme.type.title,
    color = ArgonTheme.colors.ink,
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSection(filter: Filter, applied: List<String>, onChange: (List<String>) -> Unit, currencyCode: String?) {
    val spacing = ArgonTheme.spacing
    val control = filterControl(filter)
    // a switch carries the filter's name itself
    if (control == FilterControl.Switch) {
        val value = booleanValue(filter) ?: return
        ArgonSwitch(value.input in applied, { onChange(toggled(applied, value.input)) }, label = filter.label)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
        SheetTitle(filter.label, section = true)
        when (control) {
            FilterControl.Slider -> priceSlider(filter)?.let { PriceRange(it, applied, onChange, currencyCode) }
            FilterControl.Swatches -> FlowRow(
                Modifier.padding(top = spacing.s),
                horizontalArrangement = Arrangement.spacedBy(spacing.s),
                verticalArrangement = Arrangement.spacedBy(spacing.m),
            ) {
                for (value in filter.values) {
                    val on = value.input in applied
                    val fill = swatch(value)
                    // a colour no product in the list has is struck through (it can still be tapped)
                    ArgonSwatch(fill.colorHex, fill.imageUrl, value.label, isSelected = on, isAvailable = value.count > 0 || on, size = ArgonSize.L) {
                        onChange(toggled(applied, value.input))
                    }
                }
            }
            else -> {
                for (value in filter.values) {
                    val on = value.input in applied
                    // a value no product in the list has can't be ticked (but one that is ticked can be unticked)
                    ArgonCheckbox(on, { onChange(toggled(applied, value.input)) }, label = "${value.label} (${value.count})", isEnabled = value.count > 0 || on)
                }
            }
        }
    }
}

/**
 * The price slider with its two prices under it. The thumbs follow the finger; the selection changes once they have
 * rested for a moment, so a drag is one reload of the list, not one per step.
 * ponytail: a drag in the last moments before the sheet closes is dropped; apply on release if ArgonRangeSlider gets one.
 */
@Composable
private fun PriceRange(slider: PriceSlider, applied: List<String>, onChange: (List<String>) -> Unit, currencyCode: String?) {
    val bounds = slider.bounds
    val selected = priceSelection(applied)
    var range by remember(selected, bounds) { mutableStateOf((selected?.first ?: bounds.start) to (selected?.second ?: bounds.endInclusive)) }
    val current by rememberUpdatedState(applied)
    val apply by rememberUpdatedState(onChange)
    LaunchedEffect(range) {
        delay(400)
        val next = withPrice(current, range.first, range.second, bounds)
        if (next != current) apply(next)
    }
    Column {
        ArgonRangeSlider(range.first, range.second, bounds, { lower, upper -> range = lower to upper }, step = slider.step)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(priceText(range.first, currencyCode), style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
            Text(priceText(range.second, currencyCode), style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
        }
    }
}
