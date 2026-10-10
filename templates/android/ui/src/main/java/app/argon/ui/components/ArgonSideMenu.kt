package app.argon.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.argon.ui.ArgonTheme
import kotlinx.coroutines.flow.drop

/**
 * A menu that slides over [screen] from the start edge: native [ModalNavigationDrawer]. [content] holds the
 * [ArgonSideMenuItem]s between an optional [header] and [footer]. Tapping the scrim, swiping it shut or Back calls
 * [onDismiss]; it only opens from [isOpen] (no edge swipe, which would bypass the caller's state).
 */
@Composable
fun ArgonSideMenu(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    header: (@Composable () -> Unit)? = null,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
    screen: @Composable () -> Unit,
) {
    val state = rememberDrawerState(if (isOpen) DrawerValue.Open else DrawerValue.Closed)
    val open by rememberUpdatedState(isOpen)
    val dismiss by rememberUpdatedState(onDismiss)
    LaunchedEffect(isOpen) { if (isOpen) state.open() else state.close() }
    // closed by the user (not by isOpen turning false): tell the caller
    LaunchedEffect(state) { snapshotFlow { state.currentValue }.drop(1).collect { if (it == DrawerValue.Closed && open) dismiss() } }
    ModalNavigationDrawer(
        drawerContent = {
            ModalDrawerSheet(state) {
                header?.invoke()
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = ArgonTheme.spacing.m), content = content)
                footer?.invoke()
            }
        },
        modifier = modifier,
        drawerState = state,
        gesturesEnabled = isOpen,
        content = screen,
    )
}

/** One menu row: native [NavigationDrawerItem]; [hasChildren] adds a chevron for a submenu. */
@Composable
fun ArgonSideMenuItem(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ArgonIconName? = null,
    badge: Int? = null,
    isSelected: Boolean = false,
    hasChildren: Boolean = false,
) = NavigationDrawerItem(
    label = { Text(title) },
    selected = isSelected,
    onClick = onClick,
    modifier = modifier,
    icon = icon?.let { { ArgonIcon(it) } },
    badge = if (badge == null && !hasChildren) null else {
        {
            Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
                if (badge != null) ArgonBadge(badge)
                if (hasChildren) ArgonIcon(ArgonIconName.ChevronRight)
            }
        }
    },
)
