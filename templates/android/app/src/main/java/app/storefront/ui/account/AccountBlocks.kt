package app.storefront.ui.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonCard
import app.argon.ui.components.ArgonCardStyle
import app.storefront.AppGraph
import app.storefront.data.Route

// The small blocks the account, orders and returns pages share.

/** The store's contact page, in the in-app browser: where "Help" and "Need help?" lead. */
fun contactRoute(): Route = Route.Web("https://${AppGraph.shopDomain}/pages/contact")

/** What went wrong with a change (Shopify's own words), shown where it happened; nothing without a [message]. */
@Composable
fun ErrorText(message: String?, modifier: Modifier = Modifier) {
    if (message.isNullOrBlank()) return
    Text(message, modifier, style = ArgonTheme.type.label, color = ArgonTheme.colors.sale)
}

/**
 * A label with its value at the end of the line ("Subtotal", "$230.00"); [note] is a quieter line under the label (the
 * shipping method). [strong] is for the line that matters most (the total).
 */
@Composable
fun InfoRow(label: String, value: String, modifier: Modifier = Modifier, note: String? = null, strong: Boolean = false) {
    val style = if (strong) ArgonTheme.type.headline else ArgonTheme.type.body
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(label, style = style, color = if (strong) ArgonTheme.colors.ink else ArgonTheme.colors.muted)
            if (!note.isNullOrBlank()) Text(note, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        }
        // a long value (a company's name) wraps instead of pushing its label off the line
        Text(value, Modifier.widthIn(max = 200.dp), style = style, color = ArgonTheme.colors.ink, textAlign = TextAlign.End)
    }
}

/** A bordered block of a page, with an optional heading; it fills the width it is given. */
@Composable
fun Panel(modifier: Modifier = Modifier, title: String? = null, content: @Composable ColumnScope.() -> Unit) =
    ArgonCard(modifier.fillMaxWidth(), style = ArgonCardStyle.Outlined) {
        Column(Modifier.fillMaxWidth().padding(ArgonTheme.spacing.l), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
            if (title != null) Text(title, Modifier.semantics { heading() }, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
            content()
        }
    }
