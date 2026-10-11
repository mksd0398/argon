package app.storefront.ui.product

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonFullScreenModal
import app.storefront.data.Img
import app.storefront.data.Variant
import app.storefront.ui.LabelTag
import app.storefront.ui.StoreImage

// Block 1 of the product page: the image pager with its tags, and the full-screen viewer a tap opens.
// ponytail: images only (`Product.images`): a product's videos and 3D models are decoded but not shown. Upgrade: a page
// with a player for `Media.Video`.

/**
 * Where [image] (a variant's own) sits among the product's [images]; null when it isn't one of them. The CDN's size
 * parameters (after `?`) don't count.
 */
internal fun imageIndex(images: List<Img>, image: Img?): Int? {
    val url = image?.url?.substringBefore('?') ?: return null
    return images.indexOfFirst { it.url.substringBefore('?') == url }.takeIf { it >= 0 }
}

/** A tag over the gallery; [isSale] puts it on the sale colour. */
internal data class GalleryTag(val text: String, val isSale: Boolean = false)

/** What the gallery says about [variant] at a glance: "Sale −20%", "Sold out", "Bundle", each only when it is true. */
internal fun galleryTags(variant: Variant?): List<GalleryTag> = listOfNotNull(
    variant?.let { saleTag(it.price, it.compareAt) }?.let { GalleryTag(it, isSale = true) },
    GalleryTag("Sold out").takeIf { variant?.available == false },
    GalleryTag("Bundle").takeIf { variant?.requiresComponents == true },
)

/**
 * The product's [images], edge to edge and 4:5, one per page of [pager] with page dots under them, and [tags] over the
 * top corner. A tap calls [onOpen] with the page (the full-screen viewer). A product without images shows the quiet
 * placeholder. The pager is the caller's, so choosing an option can bring its variant's image into view.
 */
@Composable
internal fun ProductGallery(images: List<Img>, title: String, pager: PagerState, tags: List<GalleryTag>, onOpen: (page: Int) -> Unit) {
    val spacing = ArgonTheme.spacing
    Column {
        Box(Modifier.fillMaxWidth().aspectRatio(4f / 5f)) {
            if (images.isEmpty()) {
                StoreImage(images.firstOrNull(), title, Modifier.matchParentSize())
            } else {
                HorizontalPager(pager, Modifier.matchParentSize()) { page ->
                    StoreImage(images[page], title, Modifier.fillMaxSize().clickable(onClickLabel = "View full screen") { onOpen(page) })
                }
            }
            Column(Modifier.align(Alignment.TopStart).padding(spacing.m), verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
                for (tag in tags) LabelTag(tag.text, isSale = tag.isSale)
            }
        }
        if (images.size > 1) PageDots(images.size, pager.currentPage, Modifier.padding(top = spacing.s))
    }
}

/** One dot per image, the current one larger and in ink: the dots of `ArgonCarousel`, for a pager the page drives itself. */
@Composable
private fun PageDots(count: Int, current: Int, modifier: Modifier = Modifier) {
    val colors = ArgonTheme.colors
    Row(
        modifier.fillMaxWidth().semantics { stateDescription = "Image ${current + 1} of $count" },
        horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { i -> Box(Modifier.size(if (i == current) 8.dp else 6.dp).background(if (i == current) colors.ink else colors.border, CircleShape)) }
    }
}

/**
 * The product's [images] over the whole screen, opened at [page] (null: closed): swipe between them, pinch or double-tap
 * to zoom, drag a zoomed image around. Close or Back calls [onDismiss].
 */
@Composable
internal fun GalleryViewer(images: List<Img>, title: String, page: Int?, onDismiss: () -> Unit) {
    ArgonFullScreenModal(page != null && images.isNotEmpty(), onDismiss, title) {
        val pager = rememberPagerState(initialPage = (page ?: 0).coerceIn(0, images.lastIndex)) { images.size }
        HorizontalPager(pager, Modifier.fillMaxSize()) { index -> ZoomableImage(images[index], title) }
    }
}

private const val MAX_ZOOM = 4f
private const val DOUBLE_TAP_ZOOM = 2.5f

/** [offset] kept so a zoomed image still covers its frame: it moves only as far as its magnified edges. */
private fun clampedOffset(offset: Offset, scale: Float, frame: IntSize): Offset {
    val x = frame.width * (scale - 1f) / 2f
    val y = frame.height * (scale - 1f) / 2f
    return Offset(offset.x.coerceIn(-x, x), offset.y.coerceIn(-y, y))
}

/** [image] whole in its frame; pinch to zoom up to 4x, double-tap to zoom in and back out, drag while zoomed. */
@Composable
private fun ZoomableImage(image: Img, contentDescription: String) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    StoreImage(
        image,
        contentDescription,
        Modifier.fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(onDoubleTap = {
                    scale = if (scale > 1f) 1f else DOUBLE_TAP_ZOOM
                    offset = Offset.Zero
                })
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        // one finger on an image at rest is the pager's swipe; two fingers, or a zoomed image, are ours
                        if (event.changes.size > 1 || scale > 1f) {
                            scale = (scale * event.calculateZoom()).coerceIn(1f, MAX_ZOOM)
                            offset = clampedOffset(offset + event.calculatePan(), scale, size)
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            }
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                translationX = offset.x
                translationY = offset.y
            },
        contentScale = ContentScale.Fit,
    )
}
