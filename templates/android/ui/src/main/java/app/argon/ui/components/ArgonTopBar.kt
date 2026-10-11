package app.argon.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import coil3.compose.AsyncImage

/** Standard: title (or the logo, when one is given) at the start. LargeTitle: a big title below the actions. CenteredLogo: the shop's logo (or title)
 *  centred. Search: a search field in place of the title. */
enum class ArgonTopBarVariant { Standard, LargeTitle, CenteredLogo, Search }

/** An icon button in the top bar. [contentDescription] is what screen readers say (iOS `accessibilityLabel`);
 *  [badge] a count on the icon, none when null. */
data class ArgonTopBarAction(val icon: ArgonIconName, val contentDescription: String, val badge: Int? = null, val action: () -> Unit)

/**
 * The screen's top bar: native [TopAppBar], [LargeTopAppBar], [CenterAlignedTopAppBar] or [SearchBar] by [variant].
 * For Search, [title] is the placeholder, [searchText] the query and [onSearch] runs on the keyboard's search key.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArgonTopBar(
    title: String,
    modifier: Modifier = Modifier,
    variant: ArgonTopBarVariant = ArgonTopBarVariant.Standard,
    logoUrl: String? = null,
    leading: List<ArgonTopBarAction> = emptyList(),
    trailing: List<ArgonTopBarAction> = emptyList(),
    searchText: String? = null,
    onSearchTextChange: (String) -> Unit = {},
    onSearch: (String) -> Unit = {},
) {
    val navigation = @Composable { Row { leading.forEach { ActionButton(it) } } }
    val actions: @Composable RowScope.() -> Unit = { trailing.forEach { ActionButton(it) } }
    when (variant) {
        ArgonTopBarVariant.Standard -> TopAppBar(
            title = {
                // with a logo, the logo sits where the title would (a home screen with its logo at the start)
                if (logoUrl != null) {
                    AsyncImage(logoUrl, title, Modifier.height(28.dp).widthIn(max = 160.dp), contentScale = ContentScale.Fit)
                } else {
                    Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            },
            modifier = modifier,
            navigationIcon = navigation,
            actions = actions,
        )
        ArgonTopBarVariant.LargeTitle -> LargeTopAppBar(
            title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            modifier = modifier,
            navigationIcon = navigation,
            actions = actions,
        )
        ArgonTopBarVariant.CenteredLogo -> CenterAlignedTopAppBar(
            title = {
                if (logoUrl != null) {
                    AsyncImage(logoUrl, title, Modifier.height(28.dp).widthIn(max = 160.dp), contentScale = ContentScale.Fit)
                } else {
                    Text(title, style = ArgonTheme.type.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            },
            modifier = modifier,
            navigationIcon = navigation,
            actions = actions,
        )
        ArgonTopBarVariant.Search -> SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = searchText.orEmpty(),
                    onQueryChange = onSearchTextChange,
                    onSearch = onSearch,
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text(title) },
                    leadingIcon = { if (leading.isEmpty()) ArgonIcon(ArgonIconName.Search) else navigation() },
                    trailingIcon = if (trailing.isEmpty()) null else ({ Row(content = actions) }),
                )
            },
            expanded = false,
            onExpandedChange = {},
            modifier = modifier.fillMaxWidth().padding(horizontal = ArgonTheme.spacing.l),
        ) {}
    }
}

@Composable
private fun ActionButton(action: ArgonTopBarAction) = IconButton(onClick = action.action) {
    if (action.badge != null) {
        ArgonBadgedBox(action.badge) { ArgonIcon(action.icon, contentDescription = action.contentDescription) }
    } else {
        ArgonIcon(action.icon, contentDescription = action.contentDescription)
    }
}
