package app.argon.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import coil3.compose.AsyncImage

/** A lazy, scrolling list of rows: native [LazyColumn] with an optional [header]. Give it a bounded height. */
@Composable
fun ArgonList(
    modifier: Modifier = Modifier,
    header: String? = null,
    contentPadding: PaddingValues = PaddingValues(),
    content: LazyListScope.() -> Unit,
) = LazyColumn(modifier, contentPadding = contentPadding) {
    if (header != null) {
        item(contentType = "header") {
            Text(
                header,
                Modifier.padding(horizontal = ArgonTheme.spacing.l, vertical = ArgonTheme.spacing.s),
                style = ArgonTheme.type.caption,
                color = ArgonTheme.colors.muted,
            )
        }
    }
    content()
}

/** What a list row shows before its text. */
sealed interface ArgonListLeading {
    data class Icon(val name: ArgonIconName) : ArgonListLeading
    data class Avatar(val imageUrl: String? = null, val initials: String? = null) : ArgonListLeading
    data class Image(val url: String) : ArgonListLeading
}

/** What a list row shows after its text. */
sealed interface ArgonListTrailing {
    data object Chevron : ArgonListTrailing
    data class Text(val text: String) : ArgonListTrailing
    data class Badge(val count: Int?) : ArgonListTrailing
    data class Switch(val isOn: Boolean, val onChange: (Boolean) -> Unit) : ArgonListTrailing
    data class Checkbox(val isChecked: Boolean, val onChange: (Boolean) -> Unit) : ArgonListTrailing
}

/** A native M3 [ListItem]: one or two lines with optional leading and trailing parts; tappable when [onClick] is set. */
@Composable
fun ArgonListItem(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: ArgonListLeading? = null,
    trailing: ArgonListTrailing? = null,
    onClick: (() -> Unit)? = null,
) = ListItem(
    headlineContent = { Text(title) },
    modifier = if (onClick != null) modifier.clickable(onClick = onClick) else modifier,
    supportingContent = subtitle?.let { { Text(it) } },
    leadingContent = leading?.let { { Leading(it) } },
    trailingContent = trailing?.let { { Trailing(it) } },
)

@Composable
private fun Leading(leading: ArgonListLeading) = when (leading) {
    is ArgonListLeading.Icon -> ArgonIcon(leading.name)
    is ArgonListLeading.Avatar -> ArgonAvatar(imageUrl = leading.imageUrl, initials = leading.initials)
    is ArgonListLeading.Image ->
        AsyncImage(leading.url, null, Modifier.size(56.dp).clip(ArgonTheme.radius.m), contentScale = ContentScale.Crop)
}

@Composable
private fun Trailing(trailing: ArgonListTrailing) = when (trailing) {
    ArgonListTrailing.Chevron -> ArgonIcon(ArgonIconName.ChevronRight)
    is ArgonListTrailing.Text -> Text(trailing.text, style = ArgonTheme.type.body)
    is ArgonListTrailing.Badge -> ArgonBadge(trailing.count)
    is ArgonListTrailing.Switch -> Switch(trailing.isOn, trailing.onChange)
    is ArgonListTrailing.Checkbox -> Checkbox(trailing.isChecked, trailing.onChange)
}

/** A hairline in the border colour, [inset] from the start edge. */
@Composable
fun ArgonDivider(modifier: Modifier = Modifier, inset: Dp = 0.dp) =
    HorizontalDivider(modifier.padding(start = inset), color = ArgonTheme.colors.border)
