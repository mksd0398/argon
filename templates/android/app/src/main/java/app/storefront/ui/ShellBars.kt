package app.storefront.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonSideMenu
import app.argon.ui.components.ArgonSideMenuItem
import app.storefront.AppGraph
import app.storefront.data.Announcement
import app.storefront.data.Links
import app.storefront.data.MenuItem
import app.storefront.data.Route
import app.storefront.data.menuTree
import app.storefront.ui.sections.color
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

// The parts of the app shell the merchant's settings add (screens v2, "App shell"): the announcement strip and the
// home's drawer. The tab bar is in Nav.kt, the home's top bar in HomeScreen.kt.

/**
 * The announcement strip over a tab root's top bar (under the status bar): one message at a time, the next every
 * `interval` seconds; a message with a link opens it ([Links.resolve]). [onClose] (shown when it is dismissible) hides it
 * for the session.
 */
@Composable
fun AnnouncementBar(announcement: Announcement, onOpen: (Route) -> Unit, onClose: () -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    LaunchedEffect(announcement) {
        while (announcement.messages.size > 1) {
            delay(announcement.interval * 1000L)
            index = (index + 1) % announcement.messages.size
        }
    }
    val message = announcement.messages[index % announcement.messages.size]
    val route = Links.resolve(message.link, AppGraph.brand.value?.hosts ?: setOf(AppGraph.shopDomain))
    val ink = color(announcement.color) ?: ArgonTheme.colors.paper
    Row(
        Modifier.fillMaxWidth().background(color(announcement.background) ?: ArgonTheme.colors.ink).statusBarsPadding().heightIn(min = 36.dp)
            .then(if (route != null) Modifier.clickable(role = Role.Button) { onOpen(route) } else Modifier),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            message.text,
            Modifier.weight(1f).padding(horizontal = ArgonTheme.spacing.l, vertical = ArgonTheme.spacing.xs),
            style = ArgonTheme.type.label,
            color = ink,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (announcement.dismissible) IconButton(onClick = onClose) { ArgonIcon(ArgonIconName.Close, size = 16.dp, tint = ink, contentDescription = "Close") }
    }
}

/**
 * [screen] with the drawer of the Shopify menu [menu] (`navigation.drawer`), which [screen]'s menu button opens (its
 * `openMenu`). The menu's items open their routes; a parent lists its children under it. A menu that can't be loaded
 * leaves the drawer empty.
 */
@Composable
fun HomeDrawer(menu: String, onOpen: (Route) -> Unit, screen: @Composable (openMenu: () -> Unit) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val items by produceState(emptyList<MenuItem>(), menu) {
        value = try {
            val hosts = AppGraph.loadBrand().hosts
            AppGraph.storefront.menu(menu)?.let { menuTree(it.items, hosts) }.orEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
    }
    val select: (MenuItem) -> Unit = { item ->
        open = false
        // a header item (url "#") is a Web placeholder without an http(s) URL and has nothing to open
        if (item.route !is Route.Web || item.route.url.startsWith("http")) onOpen(item.route)
    }
    ArgonSideMenu(
        isOpen = open,
        onDismiss = { open = false },
        header = {
            Text(
                AppGraph.brand.value?.name.orEmpty(),
                Modifier.padding(ArgonTheme.spacing.l),
                style = ArgonTheme.type.headline,
                color = ArgonTheme.colors.ink,
            )
        },
        content = {
            for (item in items) {
                ArgonSideMenuItem(item.title, { select(item) })
                for (child in item.children) ArgonSideMenuItem(child.title, { select(child) }, Modifier.padding(start = ArgonTheme.spacing.l))
            }
        },
        screen = { screen { open = true } },
    )
}
