package app.argon.ui.components

import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow

/** Underlined tabs: native [PrimaryTabRow], or [PrimaryScrollableTabRow] when [isScrollable] (many or long titles). */
@Composable
fun ArgonTabs(
    titles: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    isScrollable: Boolean = false,
) {
    val tabs = @Composable {
        titles.forEachIndexed { i, title ->
            Tab(
                selected = i == selectedIndex,
                onClick = { onSelect(i) },
                text = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
    if (isScrollable) PrimaryScrollableTabRow(selectedIndex, modifier, tabs = tabs) else PrimaryTabRow(selectedIndex, modifier, tabs = tabs)
}
