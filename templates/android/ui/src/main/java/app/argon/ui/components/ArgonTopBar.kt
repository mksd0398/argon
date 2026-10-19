package app.argon.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonColors
import app.argon.ui.ArgonTheme
import app.argon.ui.argonColors
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap

/** Standard: title (or the logo, when one is given) at the start. LargeTitle: a big title below the actions. CenteredLogo: the shop's logo (or title)
 *  centred. Search: a search field in place of the title. Overlay: the centred logo bar with no background, drawn over a
 *  picture that runs to the top edge of the screen (see `solid`). */
enum class ArgonTopBarVariant { Standard, LargeTitle, CenteredLogo, Search, Overlay }

/** An icon button in the top bar. [contentDescription] is what screen readers say (iOS `accessibilityLabel`);
 *  [badge] a count on the icon, none when null. */
data class ArgonTopBarAction(val icon: ArgonIconName, val contentDescription: String, val badge: Int? = null, val action: () -> Unit)

/** The solid bar's own colours, an app's (a merchant's settings): its [container] and its title and icons ([content]). Unspecified: the theme's. */
data class ArgonBarColors(val container: Color = Color.Unspecified, val content: Color = Color.Unspecified)

/** The [ArgonBarColors] every [ArgonTopBar] under it is drawn with (the Search field aside). */
val LocalArgonBarColors = staticCompositionLocalOf { ArgonBarColors() }

/**
 * The screen's top bar: native [TopAppBar], [LargeTopAppBar], [CenterAlignedTopAppBar] or [SearchBar] by [variant].
 * For Search, [title] is the placeholder, [searchText] the query and [onSearch] runs on the keyboard's search key.
 * For Overlay, put the bar on top of the content (not in a scaffold's top bar slot) and let the content start at the
 * top edge of the screen, under the status bar: at [solid] 0 the bar has no background and its logo, title and actions
 * are light over a short dark shade ([lightContent] false: dark over a light one, for a light picture); towards 1 (as
 * the picture under it scrolls away) the normal bar fades in. Only Overlay reads [solid] and [lightContent].
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
    solid: Float = 0f,
    lightContent: Boolean = true,
) {
    val bar = LocalArgonBarColors.current
    val barColors = TopAppBarDefaults.topAppBarColors(
        containerColor = bar.container,
        scrolledContainerColor = bar.container,
        navigationIconContentColor = bar.content,
        titleContentColor = bar.content,
        actionIconContentColor = bar.content,
    )
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
            colors = barColors,
        )
        ArgonTopBarVariant.LargeTitle -> LargeTopAppBar(
            title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            modifier = modifier,
            navigationIcon = navigation,
            actions = actions,
            colors = barColors,
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
            colors = barColors,
        )
        ArgonTopBarVariant.Overlay -> {
            val colors = overlayBarColors(solid, ArgonTheme.colors, bar, lightContent)
            // The shade is behind the whole bar, status bar included, and thins out into the picture half a bar further
            // down: at the height of the icons it is still dark enough for them to read on a bright picture.
            val shade = Modifier.drawBehind {
                val height = size.height * 1.5f
                drawRect(Brush.verticalGradient(listOf(colors.shade, Color.Transparent), endY = height), size = Size(size.width, height))
            }
            Box(modifier.then(shade)) {
                CenterAlignedTopAppBar(
                    title = {
                        if (logoUrl != null) {
                            OverlayLogo(logoUrl, title, colors.content.takeIf { solid < 0.5f })
                        } else {
                            Text(title, style = ArgonTheme.type.headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    },
                    navigationIcon = navigation,
                    actions = actions,
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = colors.container,
                        scrolledContainerColor = colors.container,
                        navigationIconContentColor = colors.content,
                        titleContentColor = colors.content,
                        actionIconContentColor = colors.content,
                    ),
                )
            }
        }
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

/** How dark the Overlay bar's shade is at the top edge of the screen. */
internal const val SHADE = 0.65f

/** What the Overlay bar is drawn with: its background, its title and icons, and the top of the shade behind it. */
internal data class OverlayBarColors(val container: Color, val content: Color, val shade: Color)

/**
 * The Overlay bar at [solid] (0 over the picture ... 1 the normal bar, in [bar]'s colours where set; clamped) in a theme
 * of [colors]. Over the picture it uses the dark palette whatever the theme, as everything that sits on a photo does:
 * light content, a dark shade; the light palette instead when not [lightContent] (dark content over a light picture).
 */
internal fun overlayBarColors(solid: Float, colors: ArgonColors, bar: ArgonBarColors = ArgonBarColors(), lightContent: Boolean = true): OverlayBarColors {
    val t = solid.coerceIn(0f, 1f)
    val onPhoto = argonColors(null, dark = lightContent)
    return OverlayBarColors(
        container = bar.container.takeOrElse { colors.paper }.copy(alpha = t),
        content = lerp(onPhoto.ink, bar.content.takeOrElse { colors.ink }, t),
        shade = onPhoto.paper.copy(alpha = SHADE * (1 - t)),
    )
}

/**
 * The logo in the Overlay bar. A mark on a clear background (its top-left pixel is transparent) is drawn in [tint]
 * while the bar is over the picture, where its own colour may not show; a logo with a background of its own keeps its
 * colours (tinted, it would be a plain box). Null [tint]: the logo as it is.
 */
@Composable
private fun OverlayLogo(url: String, title: String, tint: Color?) {
    val context = LocalContext.current
    var clear by remember(url) { mutableStateOf(false) }
    // a software bitmap: a pixel of a hardware one can't be read
    val request = remember(url, context) { ImageRequest.Builder(context).data(url).allowHardware(false).build() }
    AsyncImage(
        request,
        title,
        Modifier.height(28.dp).widthIn(max = 160.dp),
        onSuccess = { clear = runCatching { it.result.image.toBitmap().hasClearCorner() }.getOrDefault(false) },
        contentScale = ContentScale.Fit,
        colorFilter = tint?.takeIf { clear }?.let { ColorFilter.tint(it) },
    )
}

private fun Bitmap.hasClearCorner(): Boolean = width > 0 && height > 0 && (getPixel(0, 0) ushr 24) < 0xFF

@Composable
private fun ActionButton(action: ArgonTopBarAction) = IconButton(onClick = action.action) {
    if (action.badge != null) {
        ArgonBadgedBox(action.badge) { ArgonIcon(action.icon, contentDescription = action.contentDescription) }
    } else {
        ArgonIcon(action.icon, contentDescription = action.contentDescription)
    }
}
