package app.argon.ui.components

import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.argon.ui.ArgonTheme

/** What a badge shows for [count]: null (a dot) for null, the count (0 at least) up to 99, then "99+". As iOS. */
fun badgeText(count: Int?): String? = when {
    count == null -> null
    count > 99 -> "99+"
    else -> count.coerceAtLeast(0).toString()
}

/** A count bubble in the sale colour, or a dot when [count] is null: native [Badge]. */
@Composable
fun ArgonBadge(count: Int? = null, modifier: Modifier = Modifier) {
    val text = badgeText(count)
    if (text == null) {
        Badge(modifier)
    } else {
        Badge(modifier) { Text(text, style = ArgonTheme.type.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Bold)) }
    }
}

/** [content] (an icon, usually) with an [ArgonBadge] on its top end corner: native [BadgedBox]. */
@Composable
fun ArgonBadgedBox(count: Int?, modifier: Modifier = Modifier, content: @Composable () -> Unit) =
    BadgedBox(badge = { ArgonBadge(count) }, modifier = modifier) { content() }
