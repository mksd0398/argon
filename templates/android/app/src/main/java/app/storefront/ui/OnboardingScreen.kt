package app.storefront.ui

import android.net.Uri
import android.widget.VideoView
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.storefront.AppGraph
import app.storefront.BuildConfig
import app.storefront.data.Brand
import app.storefront.data.Onboarding
import app.storefront.data.Welcome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** How much of a page's bottom the controls over it take: the page dots and [buttons] buttons, with their margins. */
private fun controlsHeight(buttons: Int): Dp {
    val spacing = ArgonTheme.spacing
    return spacing.l + (48.dp + spacing.m) * buttons + 8.dp + spacing.l
}

/**
 * The first-launch welcome, shown once before the tabs (`AppGraph.onboarding`): full-screen pages to swipe through, each
 * a picture (or a muted, looping video) with a heading and a line of text over a bottom shade. The pages are the
 * `onboarding` screen's, read live (up to 3 s, on the welcome's dark background meanwhile: there are no cached settings on
 * a first launch), else [Onboarding.pages] in the settings' words where they have some; a screen that turns the welcome
 * off ends it. "Skip" and the last page's button end it; so does "Sign in" on the last page, offered when the store has
 * sign-in set up, which also asks for the Account tab ([onDone]'s `signIn`).
 */
@Composable
fun OnboardingScreen(onDone: (signIn: Boolean) -> Unit) {
    val loaded by AppGraph.brand.collectAsState()
    // The shop's own name and words once it answers; the app's name until then, and when it can't be reached.
    LaunchedEffect(Unit) {
        try {
            AppGraph.loadBrand()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // the pages keep the app's name
        }
    }
    // the onboarding screen's welcome, once it has answered (or not, in time)
    var asked by remember { mutableStateOf(false) }
    var screen by remember { mutableStateOf<Welcome?>(null) }
    LaunchedEffect(Unit) {
        val json = try {
            withTimeoutOrNull(3_000) { AppGraph.storefront.appScreen("onboarding") }?.template
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null // the app's own welcome
        }
        screen = Onboarding.fromScreen(json, AppGraph.homeTemplate)
        asked = true
        if (screen == Welcome.Off) onDone(false)
    }
    if (!asked || screen == Welcome.Off) {
        // the welcome's own dark background, which its pages then cover
        ArgonTheme(darkTheme = true) { Box(Modifier.fillMaxSize().background(ArgonTheme.colors.paper)) }
        return
    }
    val brand = loaded ?: Brand(BuildConfig.APP_NAME, logo = null, cover = null, accent = null, hosts = emptySet())
    val own = (screen as? Welcome.Pages)?.pages
    val pages = remember(brand, own) { own ?: Onboarding.pages(brand, AppGraph.homeTemplate).let { AppGraph.settings?.pages(it) ?: it } }
    val canSignIn = AppGraph.kwikPass != null || AppGraph.customerClientId.isNotBlank()
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()
    val last = pager.currentPage == pages.lastIndex

    StatusBarIcons(light = true)
    // What sits on a photo uses the dark palette in light and dark mode alike: a dark shade, light text, a light button.
    ArgonTheme(darkTheme = true, headingFont = AppGraph.headingFont, bodyFont = AppGraph.bodyFont, corners = AppGraph.look.corners, buttons = AppGraph.look.buttons) {
        val colors = ArgonTheme.colors
        val spacing = ArgonTheme.spacing
        // dark behind the status bar and "Skip", clear over the picture, then dark again where the words are
        val shade = Brush.verticalGradient(
            0f to colors.paper.copy(alpha = 0.65f),
            0.25f to Color.Transparent,
            0.45f to Color.Transparent,
            1f to colors.paper.copy(alpha = 0.92f),
        )
        Box(Modifier.fillMaxSize().background(colors.paper)) {
            HorizontalPager(pager, Modifier.fillMaxSize()) { index ->
                val page = pages[index]
                Box(Modifier.fillMaxSize()) {
                    StoreImage(page.image, null, Modifier.matchParentSize(), placeholder = false)
                    page.video?.let { WelcomeVideo(it, Modifier.matchParentSize()) }
                    Column(
                        Modifier.matchParentSize().background(shade).navigationBarsPadding()
                            .padding(horizontal = spacing.xl)
                            // the words end where this page's controls begin
                            .padding(bottom = controlsHeight(if (index == pages.lastIndex && canSignIn) 2 else 1)),
                        verticalArrangement = Arrangement.spacedBy(spacing.s, Alignment.Bottom),
                    ) {
                        if (page.heading.isNotBlank()) Text(page.heading, Modifier.semantics { heading() }, style = ArgonTheme.type.display, color = colors.ink)
                        if (page.text.isNotBlank()) Text(page.text, style = ArgonTheme.type.body, color = colors.ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (!last) {
                ArgonButton(
                    "Skip",
                    Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(horizontal = spacing.s),
                    style = ArgonButtonStyle.Tertiary,
                    size = ArgonSize.S,
                ) { onDone(false) }
            }
            Column(
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding()
                    .padding(start = spacing.xl, end = spacing.xl, bottom = spacing.l)
                    // "Sign in" joining on the last page moves the dots and the button up instead of jumping them
                    .animateContentSize(),
                verticalArrangement = Arrangement.spacedBy(spacing.m),
            ) {
                Row(
                    Modifier.fillMaxWidth().semantics { stateDescription = "Page ${pager.currentPage + 1} of ${pages.size}" },
                    horizontalArrangement = Arrangement.spacedBy(spacing.xs, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    repeat(pages.size) { i ->
                        val current = i == pager.currentPage
                        Box(Modifier.size(if (current) 8.dp else 6.dp).background(colors.ink.copy(alpha = if (current) 1f else 0.4f), CircleShape))
                    }
                }
                ArgonButton(pages[pager.currentPage].button ?: if (last) "Get started" else "Next", fullWidth = true) {
                    if (last) onDone(false) else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                }
                if (last && canSignIn) ArgonButton("Sign in", style = ArgonButtonStyle.Secondary, fullWidth = true) { onDone(true) }
            }
        }
    }
}

/** A welcome page's video, filling the page over its picture: muted, looping, playing from the start. */
@Composable
private fun WelcomeVideo(url: String, modifier: Modifier) = AndroidView(
    factory = { context ->
        VideoView(context).apply {
            setOnPreparedListener { player ->
                player.isLooping = true
                player.setVolume(0f, 0f)
                start()
            }
            // a video that can't be played leaves the picture; true keeps the system's error dialog away
            setOnErrorListener { _, _, _ -> true }
            setVideoURI(Uri.parse(url))
        }
    },
    modifier = modifier,
    onRelease = { it.stopPlayback() },
)
