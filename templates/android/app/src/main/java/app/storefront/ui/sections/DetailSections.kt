package app.storefront.ui.sections

import androidx.compose.foundation.MarqueeSpacing
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAccordion
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.storefront.data.ScreenSection
import app.storefront.data.SectionContent
import app.storefront.ui.HtmlText
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage
import app.storefront.ui.toColor

// The scrolling text, FAQ, features and image grid sections (screens v2, "Detailing"). A tap on a question or a tile
// reports its block, as slides do; features link nowhere.

/** [text] repeated, with a gap after each, to at least [length] characters: basicMarquee only moves what overflows the strip. */
internal fun marqueeLine(text: String, length: Int = 120): String {
    val unit = "$text      "
    return unit.repeat(length / unit.length + 1)
}

/** The Argon icon of a feature's `icon` ([app.storefront.data.FEATURE_ICONS], snake_case); a check for one it doesn't have. */
internal fun featureIcon(name: String): ArgonIconName =
    ArgonIconName.entries.firstOrNull { it.name.equals(name.replace("_", ""), ignoreCase = true) } ?: ArgonIconName.Check

@Composable
internal fun MarqueeSection(section: ScreenSection, content: SectionContent.Marquee, env: SectionEnv) {
    val text = env.text(content.text, section) ?: return
    val route = env.route(env.text(content.link, section))
    // the strip is the section's background, else near black
    val strip = (section.background ?: "text").toColor()
    Text(
        marqueeLine(text),
        Modifier.fillMaxWidth().background(strip)
            .then(if (route != null) Modifier.clickable(role = Role.Button) { env.open(route, section) } else Modifier)
            .clearAndSetSemantics { contentDescription = text }
            .padding(vertical = ArgonTheme.spacing.m)
            .basicMarquee(iterations = Int.MAX_VALUE, repeatDelayMillis = 0, initialDelayMillis = 0, spacing = MarqueeSpacing(0.dp), velocity = content.speed.dp),
        style = ArgonTheme.type.label,
        color = content.textColor.toColor().takeOrElse { ArgonTheme.colors.paper },
        maxLines = 1,
        softWrap = false,
    )
}

@Composable
internal fun FaqSection(section: ScreenSection, content: SectionContent.Faq, env: SectionEnv) {
    val questions = content.questions.mapNotNull { q -> env.text(q.question, section, q.block)?.let { q to it } }
    if (questions.isEmpty()) return
    // all closed at first
    var open by remember { mutableStateOf(emptySet<String>()) }
    Column(verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        env.text(content.heading, section)?.let { SectionHeader(it, gutter) }
        Column {
            questions.forEachIndexed { index, (q, question) ->
                if (index > 0) ArgonDivider(gutter)
                val id = q.block.id
                ArgonAccordion(question, id in open, {
                    env.tapped(section, q.block)
                    open = if (id in open) open - id else open + id
                }) { env.text(q.answer, section, q.block)?.let { HtmlText(it) } }
            }
        }
    }
}

@Composable
internal fun FeaturesSection(section: ScreenSection, content: SectionContent.Features, env: SectionEnv) {
    val features = content.features.map { Triple(it.icon, env.text(it.heading, section, it.block), env.text(it.text, section, it.block)) }
        .filter { (_, heading, text) -> heading != null || text != null }
    if (features.isEmpty()) return
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        env.text(content.heading, section)?.let { SectionHeader(it, gutter) }
        if (content.layout == "grid") {
            Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.l)) {
                for (pair in features.chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                        for ((icon, heading, text) in pair) FeatureItem(icon, heading, text, Modifier.weight(1f))
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        } else {
            // a row sharing the width while they fit, scrolling sideways once each would be narrower than 112dp
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val width = ((maxWidth - spacing.l * 2 - spacing.m * (features.size - 1)) / features.size).coerceAtLeast(112.dp)
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = spacing.l), horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                    for ((icon, heading, text) in features) FeatureItem(icon, heading, text, Modifier.width(width))
                }
            }
        }
    }
}

/** A feature: its icon above its heading and text, centred. */
@Composable
private fun FeatureItem(icon: String, heading: String?, text: String?, modifier: Modifier) = Column(
    modifier,
    verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    ArgonIcon(featureIcon(icon), size = 28.dp, tint = ArgonTheme.colors.ink)
    heading?.let { Text(it, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, textAlign = TextAlign.Center) }
    text?.let { Text(it, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, textAlign = TextAlign.Center) }
}

@Composable
internal fun ImageGridSection(section: ScreenSection, content: SectionContent.ImageGrid, env: SectionEnv) {
    if (content.tiles.isEmpty()) return
    val spacing = ArgonTheme.spacing
    Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        env.text(content.heading, section)?.let { SectionHeader(it, gutter) }
        Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.m)) {
            for (row in content.tiles.chunked(content.columns)) {
                Row(horizontalArrangement = Arrangement.spacedBy(spacing.m)) {
                    for (tile in row) {
                        val heading = env.text(tile.heading, section, tile.block)
                        val route = env.route(env.text(tile.link, section, tile.block))
                        Column(
                            Modifier.weight(1f).then(if (route != null) Modifier.clickable(role = Role.Button) { env.open(route, section, tile.block) } else Modifier),
                            verticalArrangement = Arrangement.spacedBy(spacing.xs),
                        ) {
                            StoreImage(tile.image, heading, Modifier.fillMaxWidth().aspectRatio(content.ratio).clip(ArgonTheme.radius.m))
                            heading?.let { Text(it, style = ArgonTheme.type.label, color = ArgonTheme.colors.ink, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                        }
                    }
                    repeat(content.columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}
