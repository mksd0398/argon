package app.argon.ui.components

import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import androidx.compose.ui.graphics.takeOrElse

/**
 * One tab: [badge] is a count on its icon (none when null or 0). With [iconUrl] the tab shows that image instead of
 * [icon] (which stays while it loads, and if it can't), tinted like the icons: draw it in one colour on transparency.
 */
data class ArgonBottomBarItem(val id: String, val title: String, val icon: ArgonIconName, val badge: Int? = null, val iconUrl: String? = null)

/**
 * The app's tab bar: native [NavigationBar]. Without [showLabels] the icons stand alone (their titles are what screen
 * readers say). [containerColor], [activeColor] (the selected tab's icon and label) and [inactiveColor] (the others'):
 * the theme's when unspecified.
 */
@Composable
fun ArgonBottomBar(
    items: List<ArgonBottomBarItem>,
    selectedId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    showLabels: Boolean = true,
    containerColor: Color = Color.Unspecified,
    activeColor: Color = Color.Unspecified,
    inactiveColor: Color = Color.Unspecified,
) =
    NavigationBar(modifier, containerColor = containerColor.takeOrElse { NavigationBarDefaults.containerColor }) {
        val colors = NavigationBarItemDefaults.colors(
            selectedIconColor = activeColor,
            selectedTextColor = activeColor,
            unselectedIconColor = inactiveColor,
            unselectedTextColor = inactiveColor,
        )
        for (item in items) {
            NavigationBarItem(
                colors = colors,
                selected = item.id == selectedId,
                onClick = { onSelect(item.id) },
                icon = {
                    val description = if (showLabels) null else item.title
                    if (item.badge != null && item.badge > 0) ArgonBadgedBox(item.badge) { TabIcon(item, description) } else TabIcon(item, description)
                },
                label = if (showLabels) ({ Text(item.title) }) else null,
                alwaysShowLabel = showLabels,
            )
        }
    }

@Composable
private fun TabIcon(item: ArgonBottomBarItem, description: String?) {
    if (item.iconUrl == null) return ArgonIcon(item.icon, contentDescription = description)
    val fallback = painterResource(if (LocalArgonIconStyle.current == ArgonIconStyle.Filled) item.icon.filled else item.icon.drawable)
    AsyncImage(
        item.iconUrl,
        contentDescription = description,
        modifier = Modifier.size(24.dp),
        placeholder = fallback,
        error = fallback,
        colorFilter = ColorFilter.tint(LocalContentColor.current),
    )
}
