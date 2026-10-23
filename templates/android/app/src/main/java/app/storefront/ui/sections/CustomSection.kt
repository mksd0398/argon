package app.storefront.ui.sections

import android.annotation.SuppressLint
import android.content.Intent
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonDivider
import app.storefront.AppGraph
import app.storefront.data.CustomNode
import app.storefront.data.Route
import app.storefront.data.ScreenSection
import app.storefront.data.SectionContent
import app.storefront.data.TextRun
import app.storefront.ui.ProductCardRow
import app.storefront.ui.ProductCardStyle
import app.storefront.ui.ProductCardView
import app.storefront.ui.SectionHeader
import app.storefront.ui.StoreImage

/**
 * A custom section: its compiled [CustomNode]s drawn natively when it is `native` and has them, else its html (after
 * Liquid) in a web view.
 */
@Composable
internal fun CustomSection(section: ScreenSection, content: SectionContent.Custom, env: SectionEnv) {
    if (content.isNative) {
        NativeNodes(section, content.nodes, env)
    } else {
        val html = content.html?.let { env.liquid(it, section) }?.takeIf { it.isNotBlank() } ?: return
        WebSection(html, content.height, section, env)
    }
}

@Composable
private fun NativeNodes(section: ScreenSection, nodes: List<CustomNode>, env: SectionEnv) {
    val spacing = ArgonTheme.spacing
    val gutter = Modifier.padding(horizontal = spacing.l)
    val open: (Route) -> Unit = { env.open(it, section) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        for (node in nodes) when (node) {
            is CustomNode.Heading -> env.text(node.text, section)?.let {
                val style = when (node.level) {
                    1 -> ArgonTheme.type.title
                    2 -> ArgonTheme.type.headline
                    else -> ArgonTheme.type.label
                }
                Text(it, gutter.semantics { heading() }, style = style, color = ArgonTheme.colors.ink)
            }
            is CustomNode.Paragraph -> Text(runs(node.runs, section, env), gutter, style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
            is CustomNode.Bullets -> Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.xs)) {
                node.items.forEachIndexed { i, item ->
                    Row(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
                        Text(if (node.ordered) "${i + 1}." else "•", Modifier.widthIn(min = 16.dp), style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
                        Text(runs(item, section, env), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
                    }
                }
            }
            is CustomNode.Image -> {
                val route = env.route(node.link?.let { env.liquid(it, section) })
                StoreImage(
                    env.liquid(node.url, section),
                    node.alt?.let { env.liquid(it, section) },
                    gutter.fillMaxWidth().then(if (route != null) Modifier.clickable(role = Role.Button) { open(route) } else Modifier),
                    contentScale = ContentScale.FillWidth,
                    placeholder = false,
                )
            }
            is CustomNode.Button -> {
                val route = env.route(node.link?.let { env.liquid(it, section) })
                env.text(node.label, section)?.let { label -> ArgonButton(label, gutter, isEnabled = route != null) { route?.let(open) } }
            }
            CustomNode.Divider -> ArgonDivider(gutter)
            is CustomNode.Product -> env.nodes.products[node.id]?.let { card ->
                ProductCardView(card, { open(Route.Product(card.handle)) }, gutter, style = ProductCardStyle.Row)
            }
            is CustomNode.Collection -> env.nodes.collections[node.id]?.let { collection ->
                Column(verticalArrangement = Arrangement.spacedBy(spacing.m)) {
                    SectionHeader(collection.title, gutter, actionLabel = "See all") { open(Route.Collection(collection.handle)) }
                    ProductCardRow(collection.products.take(node.limit), { open(Route.Product(it.handle)) })
                }
            }
        }
    }
}

/** A paragraph's runs as one text: bold, italic, and links that open through the section. */
@Composable
private fun runs(runs: List<TextRun>, section: ScreenSection, env: SectionEnv): AnnotatedString {
    val link = TextLinkStyles(SpanStyle(color = ArgonTheme.colors.accent, textDecoration = TextDecoration.Underline))
    return buildAnnotatedString {
        for (run in runs) {
            val style = SpanStyle(fontWeight = if (run.bold) FontWeight.Bold else null, fontStyle = if (run.italic) FontStyle.Italic else null)
            val route = env.route(run.link?.let { env.liquid(it, section) })
            withStyle(style) {
                val text = env.liquid(run.text, section)
                if (route != null) withLink(LinkAnnotation.Clickable("link", link) { env.open(route, section) }) { append(text) } else append(text)
            }
        }
    }
}

private fun Color.css() = "#%06X".format(toArgb() and 0xFFFFFF)

// the theme's font, served to the page from the app's resources at this path (the page's origin is the shop's)
private const val FONT_PATH = "/__argon/font.ttf"

/**
 * [html] in a page with the app's font and colours (`--accent`, `--text`, `--background`), no margins and images no
 * wider than the page; JavaScript on. Its height is [height] when set, else the page's own, measured after it loads and
 * whenever it resizes. A link in it never navigates the view: it goes through [Links][app.storefront.data.Links] (a store
 * link opens in the app, anything else in the browser).
 */
@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
private fun WebSection(html: String, height: Int, section: ScreenSection, env: SectionEnv) {
    val colors = ArgonTheme.colors
    var measured by remember { mutableFloatStateOf(1f) }
    val document = remember(html, colors) {
        """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>@font-face{font-family:ArgonText;src:url('$FONT_PATH')}
:root{--accent:${colors.accent.css()};--text:${colors.ink.css()};--background:${colors.paper.css()}}
body{margin:0;padding:0 16px;font-family:ArgonText,sans-serif;color:var(--text);background:transparent}
img{max-width:100%;height:auto}a{color:var(--accent)}</style></head><body>$html
<script>(function(){function report(){ArgonBridge.height(document.documentElement.scrollHeight)}
window.addEventListener('load',report);window.addEventListener('resize',report);
if(window.ResizeObserver){new ResizeObserver(report).observe(document.documentElement)}report()})()</script></body></html>"""
    }
    val shown = if (height > 0) height.toFloat() else measured
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                isVerticalScrollBarEnabled = false
                addJavascriptInterface(
                    object {
                        @JavascriptInterface
                        fun height(value: Float) {
                            // only a real height, and not past what a section can be: a page can report anything
                            if (value.isFinite()) post { measured = value.coerceIn(1f, 5000f) }
                        }
                    },
                    "ArgonBridge",
                )
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        // a frame inside the page (an embedded video) loads what it loads
                        if (!request.isForMainFrame) return false
                        // the page itself never navigates; only a tap on a link leaves it, never a script's redirect
                        if (!request.hasGesture()) return true
                        val url = request.url
                        when (url.scheme?.lowercase()) {
                            // the app that handles them, when there is one
                            "mailto", "tel", "sms" -> runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url)) }
                            // http(s): a store link in the app, anything else in the browser; other schemes nowhere
                            else -> env.route(url.toString())?.let { env.open(it, section) }
                        }
                        return true
                    }

                    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                        if (request.url.path != FONT_PATH || request.url.host != AppGraph.shopDomain) return null
                        return runCatching { WebResourceResponse("font/ttf", null, context.resources.openRawResource(app.argon.ui.R.font.hanken_grotesk)) }.getOrNull()
                    }
                }
            }
        },
        // loaded once per document: the height it reports recomposes this, which must not load it again
        update = {
            if (it.tag != document) {
                it.tag = document
                it.loadDataWithBaseURL("https://${AppGraph.shopDomain}/", document, "text/html", "utf-8", null)
            }
        },
        modifier = Modifier.fillMaxWidth().height(shown.dp),
        onRelease = { it.destroy() },
    )
}
