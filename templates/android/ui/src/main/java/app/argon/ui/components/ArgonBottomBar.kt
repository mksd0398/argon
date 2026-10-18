package app.argon.ui.components

import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** One tab: [badge] is a count on its icon (none when null or 0). */
data class ArgonBottomBarItem(val id: String, val title: String, val icon: ArgonIconName, val badge: Int? = null)

/** The app's tab bar: native [NavigationBar]. Without [showLabels] the icons stand alone (their titles are what screen readers say). */
@Composable
fun ArgonBottomBar(
    items: List<ArgonBottomBarItem>,
    selectedId: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    showLabels: Boolean = true,
) =
    NavigationBar(modifier) {
        for (item in items) {
            NavigationBarItem(
                selected = item.id == selectedId,
                onClick = { onSelect(item.id) },
                icon = {
                    val description = if (showLabels) null else item.title
                    if (item.badge != null && item.badge > 0) ArgonBadgedBox(item.badge) { ArgonIcon(item.icon, contentDescription = description) } else ArgonIcon(item.icon, contentDescription = description)
                },
                label = if (showLabels) ({ Text(item.title) }) else null,
                alwaysShowLabel = showLabels,
            )
        }
    }
