package app.storefront.ui.product

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAccordion
import app.argon.ui.components.ArgonDivider
import app.storefront.data.Metafield
import app.storefront.data.ShopPolicies
import app.storefront.ui.HtmlText

/** The accordion that starts open. */
internal const val DESCRIPTION = "Description"

/** "care_guide" -> "Care guide": a metafield's key as its label. */
internal fun metafieldLabel(key: String): String = key.replace('_', ' ').replaceFirstChar { it.uppercase() }

/**
 * Block 9 of the product page, one accordion each: "Description", "Details" (the `PDP_METAFIELDS` the product has a
 * value for), "Shipping policy" and "Returns policy" (the shop's own). One with nothing to say is left out. [open] holds
 * the titles of the expanded ones; [onToggle] gets the title tapped.
 */
@Composable
internal fun ProductDetails(
    descriptionHtml: String,
    metafields: List<Metafield>,
    policies: ShopPolicies?,
    open: Set<String>,
    modifier: Modifier = Modifier,
    onToggle: (title: String) -> Unit,
) {
    val shipping = policies?.shippingPolicy?.body?.takeIf { it.isNotBlank() }
    val returns = policies?.refundPolicy?.body?.takeIf { it.isNotBlank() }
    if (descriptionHtml.isBlank() && metafields.isEmpty() && shipping == null && returns == null) return
    // the accordions bring the page's gutter themselves
    Column(modifier.fillMaxWidth().padding(top = ArgonTheme.spacing.xl)) {
        ArgonDivider()
        if (descriptionHtml.isNotBlank()) Section(DESCRIPTION, open, onToggle) { HtmlText(descriptionHtml) }
        if (metafields.isNotEmpty()) {
            Section("Details", open, onToggle) {
                // ponytail: values are shown as the store sends them (a rich-text or JSON metafield shows its raw text)
                Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
                    for (metafield in metafields) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.l)) {
                            Text(metafieldLabel(metafield.key), Modifier.weight(1f), style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
                            Text(metafield.value, Modifier.weight(2f), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
                        }
                    }
                }
            }
        }
        if (shipping != null) Section("Shipping policy", open, onToggle) { HtmlText(shipping) }
        if (returns != null) Section("Returns policy", open, onToggle) { HtmlText(returns) }
    }
}

/** One accordion, expanded while its [title] is in [open], with the hairline under it. */
@Composable
private fun Section(title: String, open: Set<String>, onToggle: (String) -> Unit, content: @Composable () -> Unit) {
    ArgonAccordion(title, title in open, { onToggle(title) }, content = content)
    ArgonDivider()
}
