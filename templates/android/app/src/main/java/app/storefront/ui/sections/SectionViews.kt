package app.storefront.ui.sections

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAvatar
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCarousel
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListLeading
import app.argon.ui.components.ArgonListTrailing
import app.storefront.data.CollectionCard
import app.storefront.data.ProductCard
import app.storefront.data.Route
import app.storefront.data.ScreenSection
import app.storefront.data.Section
import app.storefront.data.SectionBlock
import app.storefront.data.SectionContent
import app.storefront.data.Slide
import app.storefront.data.content
import app.storefront.ui.HtmlText
import app.storefront.ui.ProductCardRow
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage
import app.storefront.ui.home.BannerView
import app.storefront.ui.home.ProductPairs
import app.storefront.ui.home.picture
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

// The section types, each drawn from the component library and the shared blocks. A section takes the full width and
// brings its own side margin (spacing.l), like the home templates' blocks.

/**
 * One section, by its type; a type this app doesn't know, or one with nothing to show, draws nothing. Its `background`
 * is behind the whole of it, edge to edge, its `padding` room above and below inside that.
 */
@Composable
fun SectionView(section: ScreenSection, env: SectionEnv, modifier: Modifier = Modifier) {
    LaunchedEffect(section.id) { env.viewed(section) }
    val background = section.background?.let(::color)
    Box(modifier.fillMaxWidth().then(if (background != null) Modifier.background(background) else Modifier).padding(vertical = section.padding.dp)) {
        when (val content = section.content) {
            is SectionContent.Banner -> BannerSection(section, content, env)
            is SectionContent.Slideshow -> SlideshowSection(section, content, env)
            is SectionContent.Products -> ProductsSection(section, content, env)
            is SectionContent.Collections -> CollectionsSection(section, content, env)
            is SectionContent.RichText -> RichTextSection(section, content, env)
            is SectionContent.ImageWithText -> ImageWithTextSection(section, content, env)
            is SectionContent.Video -> VideoSection(content)
            is SectionContent.Countdown -> CountdownSection(section, content, env)
            is SectionContent.Spacer -> SpacerSection(content)
            is SectionContent.Custom -> CustomSection(section, content, env)
            is SectionContent.Marquee -> MarqueeSection(section, content, env)
            is SectionContent.Faq -> FaqSection(section, content, env)
            is SectionContent.Features -> FeaturesSection(section, content, env)
            is SectionContent.ImageGrid -> ImageGridSection(section, content, env)
            null -> Unit
        }
    }
}

internal val gutter @Composable get() = Modifier.padding(horizontal = ArgonTheme.spacing.l)

/** Width over height of a banner or slide by its `height` choice. */
internal fun bannerRatio(height: String): Float = when (height) {
    "small" -> 21f / 9f
    "medium" -> 16f / 10f
    else -> 4f / 5f
}

/** "#RRGGBB" as a colour; null when it isn't one. */
internal fun color(hex: String): Color? = hex.removePrefix("#").toLongOrNull(16)?.takeIf { hex.length == 7 }?.let { Color(0xFF000000 or it) }

/** A banner or slide as the home templates' [BannerView] takes it, its words through Liquid. */
private fun SectionEnv.banner(slide: Slide, section: ScreenSection, block: SectionBlock?) = Section.Banner(
    style = "hero",
    image = slide.image,
    heading = text(slide.heading, section, block),
    text = text(slide.text, section, block),
    buttonLabel = text(slide.buttonLabel, section, block),
    link = route(text(slide.link, section, block)),
)

@Composable
private fun BannerSection(section: ScreenSection, content: SectionContent.Banner, env: SectionEnv) {
    val banner = env.banner(content.slide, section, null)
    val card = content.style == "card"
    BannerView(
        banner,
        onOpen = { env.open(it, section) },
        ratio = bannerRatio(content.height),
        modifier = if (card) gutter else Modifier,
        shape = if (card) ArgonTheme.radius.l else RectangleShape,
        textColor = color(content.textColor),
    )
}

@Composable
private fun SlideshowSection(section: ScreenSection, content: SectionContent.Slideshow, env: SectionEnv) {
    val slides = section.blocks.filter { it.type == "slide" }.take(content.slides.size).zip(content.slides)
    if (slides.isEmpty()) return
    ArgonCarousel(slides.size, autoplaySeconds = if (content.autoplay) content.interval.toDouble() else null) { page ->
        slides.getOrNull(page)?.let { (block, slide) ->
            BannerView(env.banner(slide, section, block), onOpen = { env.open(it, section, block) }, ratio = bannerRatio(content.height))
        }
    }
}

/** A products section's cards: its own products when it lists some, else its collection's first `limit`. */
internal fun productsOf(content: SectionContent.Products, env: SectionEnv): List<ProductCard> {
    val listed = content.products.mapNotNull { env.nodes.products[it] }
    if (content.products.isNotEmpty()) return listed
    return content.collection?.let { env.nodes.collections[it] }?.products.orEmpty().take(content.limit)
}

@Composable
private fun ProductsSection(section: ScreenSection, content: SectionContent.Products, env: SectionEnv) {
    val cards = productsOf(content, env)
    if (cards.isEmpty()) return
    val spacing = ArgonTheme.spacing
    val collection = content.collection?.let { env.nodes.collections[it] }
    val seeAll = collection?.takeIf { content.showAll }?.let { Route.Collection(it.handle) }
    val open: (ProductCard) -> Unit = { env.open(Route.Product(it.handle), section) }
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        val heading = env.text(content.heading, section)
        if (heading != null || seeAll != null) {
            SectionHeader(heading ?: collection?.title.orEmpty(), gutter, actionLabel = seeAll?.let { "See all" }, onAction = seeAll?.let { { env.open(it, section) } })
        }
        if (content.style == "grid") ProductPairs(cards, { route -> env.open(route, section) }, gutter) else ProductCardRow(cards, open)
    }
}

@Composable
private fun CollectionsSection(section: ScreenSection, content: SectionContent.Collections, env: SectionEnv) {
    val collections = content.collections.mapNotNull { env.nodes.collections[it] }
    if (collections.isEmpty()) return
    val spacing = ArgonTheme.spacing
    val open: (CollectionCard) -> Unit = { env.open(Route.Collection(it.handle), section) }
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        env.text(content.heading, section)?.let { SectionHeader(it, gutter) }
        when (content.style) {
            "grid" -> Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.m)) {
                for (pair in collections.chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                        for (collection in pair) CollectionTile(collection, Modifier.weight(1f)) { open(collection) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            "list" -> Column {
                for (collection in collections) {
                    ArgonListItem(
                        collection.title,
                        leading = collection.picture?.let { ArgonListLeading.Image(it.url) },
                        trailing = ArgonListTrailing.Chevron,
                        onClick = { open(collection) },
                    )
                }
            }
            // circles: a round picture with the title under it, in a row that scrolls sideways
            else -> LazyRow(contentPadding = PaddingValues(horizontal = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                items(collections, key = { it.id }) { collection ->
                    Column(
                        Modifier.width(72.dp).clickable(role = Role.Button) { open(collection) },
                        verticalArrangement = Arrangement.spacedBy(spacing.xs),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        ArgonAvatar(imageUrl = collection.picture?.url, initials = collection.title, size = ArgonSize.L)
                        Text(collection.title, style = ArgonTheme.type.caption, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** A collection in a grid: its picture, square, and its title under it. */
@Composable
private fun CollectionTile(collection: CollectionCard, modifier: Modifier, onOpen: () -> Unit) = Column(
    modifier.clickable(role = Role.Button, onClick = onOpen),
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs),
) {
    StoreImage(collection.picture, collection.title, Modifier.fillMaxWidth().aspectRatio(1f).clip(ArgonTheme.radius.m))
    Text(collection.title, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
}

@Composable
private fun RichTextSection(section: ScreenSection, content: SectionContent.RichText, env: SectionEnv) {
    val heading = env.text(content.heading, section)
    val text = env.text(content.text, section)
    if (heading == null && text == null) return
    val centered = content.alignment == "center"
    Column(gutter.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        if (heading != null) {
            Text(
                heading,
                Modifier.fillMaxWidth().semantics { heading() },
                style = ArgonTheme.type.headline,
                color = ArgonTheme.colors.ink,
                textAlign = if (centered) TextAlign.Center else TextAlign.Start,
            )
        }
        if (text != null) HtmlText(text, centered = centered)
    }
}

@Composable
private fun ImageWithTextSection(section: ScreenSection, content: SectionContent.ImageWithText, env: SectionEnv) {
    val spacing = ArgonTheme.spacing
    val route = env.route(env.text(content.link, section))
    val button = env.text(content.buttonLabel, section)?.takeIf { route != null }
    val image: @Composable (Modifier) -> Unit = { StoreImage(content.image, null, it.aspectRatio(1f).clip(ArgonTheme.radius.m)) }
    Row(gutter, horizontalArrangement = Arrangement.spacedBy(spacing.l), verticalAlignment = Alignment.CenterVertically) {
        if (content.imagePosition == "start") image(Modifier.weight(1f))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            env.text(content.heading, section)?.let { Text(it, Modifier.semantics { heading() }, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink) }
            env.text(content.text, section)?.let { HtmlText(it) }
            if (button != null && route != null) ArgonButton(button, style = ArgonButtonStyle.Secondary, size = ArgonSize.S) { env.open(route, section) }
        }
        if (content.imagePosition == "end") image(Modifier.weight(1f))
    }
}

/** What is left until [end] from [now], as days, hours, minutes and seconds; all zero once it is over. */
internal fun remaining(end: Instant, now: Instant): List<Long> {
    // Duration's toHoursPart() and the like need API 31
    val seconds = Duration.between(now, end).seconds.coerceAtLeast(0)
    return listOf(seconds / 86_400, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60)
}

@Composable
private fun CountdownSection(section: ScreenSection, content: SectionContent.Countdown, env: SectionEnv) {
    val end = content.endsAt ?: return
    var now by remember { mutableStateOf(Instant.now()) }
    // ticks every second while it runs
    LaunchedEffect(end) {
        while (now < end) {
            delay(1000 - (System.currentTimeMillis() % 1000))
            now = Instant.now()
        }
    }
    if (now >= end && content.hideWhenOver) return
    val spacing = ArgonTheme.spacing
    val route = env.route(env.text(content.link, section))
    Column(
        gutter.fillMaxWidth().then(if (route != null) Modifier.clickable(role = Role.Button) { env.open(route, section) } else Modifier),
        verticalArrangement = Arrangement.spacedBy(spacing.s),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        env.text(content.heading, section)?.let { Text(it, Modifier.semantics { heading() }, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center) }
        Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
            for ((value, unit) in remaining(end, now).zip(listOf("days", "hours", "min", "sec"))) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(value.toString().padStart(2, '0'), style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
                    Text(unit, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
                }
            }
        }
        env.text(content.text, section)?.let { Text(it, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center) }
    }
}

@Composable
private fun SpacerSection(content: SectionContent.Spacer) =
    Box(Modifier.fillMaxWidth().height(content.height.dp), Alignment.Center) {
        if (content.divider) ArgonDivider(gutter)
    }
