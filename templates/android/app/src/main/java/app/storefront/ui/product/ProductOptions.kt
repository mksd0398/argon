package app.storefront.ui.product

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonSwatch
import app.argon.ui.components.ArgonTag
import app.storefront.data.Product
import app.storefront.data.ProductOption
import app.storefront.data.Variant
import app.storefront.data.Variants
import app.storefront.data.isColorName
import app.storefront.ui.swatch

// Block 4 of the product page: the options to choose from.

/** How many variants a product arrives with at most (`variants(first: 250)`, the Storefront API's page ceiling). */
private const val LOADED_VARIANTS = 250

/** The options a shopper chooses from: all of them, but for Shopify's lone "Title: Default Title" of a product without options. */
internal fun visibleOptions(product: Product): List<ProductOption> =
    product.options.filterNot { it.name == "Title" && it.values == listOf("Default Title") }

/**
 * The values of [option] that give a variant that can be bought, keeping the rest of [selection]. The others are shown
 * struck or dimmed, and can still be chosen (to reach "Sold out").
 * ponytail: [variants] holds the product's first 250. Past that, a combination that isn't listed may still exist, so it
 * counts as available and the selected variant's own answer (`variantBySelectedOptions`) tells. Upgrade: decode
 * `encodedVariantAvailability`.
 */
internal fun availableValues(variants: List<Variant>, selection: Map<String, String>, option: ProductOption): Set<String> =
    option.values.filterTo(mutableSetOf()) { value ->
        Variants.match(variants, selection + (option.name to value))?.available ?: (variants.size >= LOADED_VARIANTS)
    }

/**
 * One group per option: its name with the chosen value ("Colour: Olive"), then its values to pick from, colours
 * (`isColorName`) as swatches and the rest as tags. A value that can't be bought with the rest of the [selection] is
 * struck (a swatch) or dimmed (a tag). [onSelect] gets the option's name and the value tapped.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ProductOptions(
    options: List<ProductOption>,
    selection: Map<String, String>,
    variants: List<Variant>,
    modifier: Modifier = Modifier,
    onSelect: (option: String, value: String) -> Unit,
) {
    if (options.isEmpty()) return
    val spacing = ArgonTheme.spacing
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.l),
    ) {
        for (option in options) {
            val chosen = selection[option.name]
            val available = remember(variants, selection, option) { availableValues(variants, selection, option) }
            val isColor = isColorName(option.name)
            Column(verticalArrangement = Arrangement.spacedBy(spacing.s)) {
                Text(
                    if (chosen != null) "${option.name}: $chosen" else option.name,
                    style = ArgonTheme.type.label,
                    color = ArgonTheme.colors.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(spacing.s),
                    // a tag brings its own touch height; swatches need the gap between rows
                    verticalArrangement = Arrangement.spacedBy(if (isColor) spacing.s else spacing.xxs),
                ) {
                    for (value in option.optionValues) {
                        val isAvailable = value.name in available
                        if (isColor) {
                            val fill = swatch(value)
                            ArgonSwatch(
                                fill.colorHex,
                                fill.imageUrl,
                                value.name,
                                isSelected = value.name == chosen,
                                isAvailable = isAvailable,
                                onClick = { onSelect(option.name, value.name) },
                            )
                        } else {
                            ArgonTag(
                                value.name,
                                Modifier.alpha(if (isAvailable) 1f else 0.45f).semantics { if (!isAvailable) stateDescription = "Unavailable" },
                                isSelected = value.name == chosen,
                                onClick = { onSelect(option.name, value.name) },
                            )
                        }
                    }
                }
            }
        }
    }
}
