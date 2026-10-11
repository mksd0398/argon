package app.storefront.ui.product

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.storefront.data.ComponentVariant
import app.storefront.data.Route
import app.storefront.data.Variant
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage

/**
 * Block 8 of the product page, from the selected variant in full. "This bundle includes": each part's image, product,
 * variant and "× n". "Also sold in": the bundles this variant is a part of, each opening its product ([onOpen]).
 */
@Composable
internal fun ProductBundle(variant: Variant?, modifier: Modifier = Modifier, onOpen: (Route) -> Unit) {
    val parts = variant?.components.orEmpty()
    val bundles = variant?.groupedBy.orEmpty()
    if (parts.isEmpty() && bundles.isEmpty()) return
    val spacing = ArgonTheme.spacing
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.m),
    ) {
        if (parts.isNotEmpty()) {
            SectionHeader("This bundle includes")
            for (part in parts) {
                BundleRow(part.variant) { Text("× ${part.quantity}", style = ArgonTheme.type.label, color = ArgonTheme.colors.ink) }
            }
        }
        if (bundles.isNotEmpty()) {
            SectionHeader("Also sold in")
            for (bundle in bundles) {
                BundleRow(bundle, Modifier.clickable(role = Role.Button) { onOpen(Route.Product(bundle.product.handle)) }) {
                    ArgonIcon(ArgonIconName.ChevronRight, tint = ArgonTheme.colors.muted)
                }
            }
        }
    }
}

/** A part or a bundle: image, product title, variant title (not Shopify's "Default Title"), and [trailing] at the end. */
@Composable
private fun BundleRow(item: ComponentVariant, modifier: Modifier = Modifier, trailing: @Composable () -> Unit) = Row(
    modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m),
    verticalAlignment = Alignment.CenterVertically,
) {
    StoreImage(item.image, item.product.title, Modifier.size(56.dp).clip(ArgonTheme.radius.s))
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xxs)) {
        Text(item.product.title.orEmpty(), style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (item.title != "Default Title") {
            Text(item.title, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    trailing()
}
