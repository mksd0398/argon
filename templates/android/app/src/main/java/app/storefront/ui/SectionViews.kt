package app.storefront.ui

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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.storefront.data.Route
import app.storefront.data.Section
import coil3.compose.AsyncImage

/** One view per home section type. */
@Composable
fun SectionView(section: Section, onOpen: (Route) -> Unit) = when (section) {
    is Section.Banner -> BannerView(section, onOpen)
    is Section.Products -> ProductsView(section, onOpen)
    is Section.Collections -> CollectionsView(section, onOpen)
}

@Composable
private fun Heading(text: String?) {
    if (!text.isNullOrBlank()) {
        Text(text, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 12.dp))
    }
}

/** `hero`: full width, edge to edge. `card`: rounded and inset. Without an image the box is the accent colour. */
@Composable
private fun BannerView(b: Section.Banner, onOpen: (Route) -> Unit) {
    val colors = MaterialTheme.colorScheme
    val link = b.link
    val image = b.image
    val card = b.style == "card"
    Box(
        Modifier.fillMaxWidth().padding(if (card) 16.dp else 0.dp)
            .clip(if (card) RoundedCornerShape(16.dp) else RectangleShape)
            .background(colors.primary)
            .let { if (link != null) it.clickable { onOpen(link) } else it }
            .heightIn(min = 180.dp),
        contentAlignment = Alignment.BottomStart,
    ) {
        if (image != null) {
            val ratio = if (image.width != null && image.height != null && image.height > 0) image.width.toFloat() / image.height else 1.5f
            AsyncImage(
                model = image.url,
                contentDescription = image.alt ?: b.heading,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().aspectRatio(ratio.coerceIn(1f, 2f)),
            )
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f)))))
        }
        val text = if (image != null) Color.White else colors.onPrimary
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            b.heading?.let { Text(it, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = text) }
            b.text?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = text) }
            if (b.buttonLabel != null && link != null) {
                Button(
                    onClick = { onOpen(link) },
                    colors = if (image != null) ButtonDefaults.buttonColors() else ButtonDefaults.buttonColors(containerColor = colors.onPrimary, contentColor = colors.primary),
                ) { Text(b.buttonLabel) }
            }
        }
    }
}

/** `carousel` scrolls sideways; `grid` is two columns (a LazyRow of cards here, because a lazy grid can't nest in the home list). */
@Composable
private fun ProductsView(s: Section.Products, onOpen: (Route) -> Unit) = Column {
    Heading(s.heading)
    if (s.style == "grid") {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            for (pair in s.items.chunked(2)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    for (card in pair) ProductCardView(card, { onOpen(Route.Product(card.handle)) }, Modifier.weight(1f))
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    } else {
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(s.items) { card -> ProductCardView(card, { onOpen(Route.Product(card.handle)) }, Modifier.width(160.dp)) }
        }
    }
}

@Composable
private fun CollectionsView(s: Section.Collections, onOpen: (Route) -> Unit) = Column {
    Heading(s.heading)
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(s.items) { c ->
            Box(
                Modifier.width(140.dp).aspectRatio(1f).clip(RoundedCornerShape(12.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable { onOpen(Route.Collection(c.handle)) },
                contentAlignment = Alignment.BottomStart,
            ) {
                c.image?.let { AsyncImage(it.url, it.alt ?: c.title, Modifier.matchParentSize(), contentScale = ContentScale.Crop) }
                Text(
                    c.title,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (c.image != null) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().background(if (c.image != null) Color.Black.copy(alpha = 0.45f) else Color.Transparent).padding(8.dp),
                )
            }
        }
    }
}
