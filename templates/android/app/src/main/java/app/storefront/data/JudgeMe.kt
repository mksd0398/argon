package app.storefront.data

import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** [average]: stars out of 5; [count]: all the product's reviews; [histogram]: stars (1...5) to how many reviews gave them. */
data class ReviewSummary(val average: Double, val count: Int, val histogram: Map<Int, Int>)

/** [date]: ISO-8601; [pictures]: the shopper's photos (URLs); [reply]: the store's answer. */
data class Review(
    val id: String,
    val rating: Int,
    val title: String?,
    val body: String,
    val author: String,
    val verified: Boolean,
    val date: String?,
    val pictures: List<String>,
    val reply: String?,
)

/** One page of a product's reviews. [summary] is null when the widget carries none. */
data class ReviewPage(val summary: ReviewSummary?, val reviews: List<Review>, val page: Int, val hasNextPage: Boolean)

/**
 * Product reviews from Judge.me, through its Widget API with the shop's public token ([token]; the private token must
 * never ship in an app). Failures are [ArgonApiError]s.
 */
class JudgeMe(private val shopDomain: String, private val token: String, private val http: OkHttpClient) {
    /** The reviews of product [productId] (its GID), [perPage] at a time from [page] 1. */
    suspend fun reviews(productId: String, page: Int = 1, perPage: Int = 5): ReviewPage {
        val url = "https://api.judge.me/api/v1/widgets/product_review".toHttpUrl().newBuilder()
            .addQueryParameter("shop_domain", shopDomain)
            .addQueryParameter("external_id", numericId(productId))
            .addQueryParameter("page", page.toString())
            .addQueryParameter("per_page", perPage.toString())
            .build()
        val json = send("reviews", Request.Builder().url(url).header("X-Api-Token", token).build())
        // the answer is JSON whose `widget` is the review widget's HTML
        val widget = (json?.get("widget") as? JsonPrimitive)?.contentOrNull ?: throw ArgonApiError.Decoding("JudgeMe.reviews", "no widget")
        return JudgeMeHtml.parse(widget, page, perPage)
    }

    /** Sends a review; the store approves it before it shows. Judge.me needs no token for this call. */
    suspend fun submit(productId: String, name: String, email: String, rating: Int, title: String, body: String) {
        val id = numericId(productId)
        val review = buildJsonObject {
            put("shop_domain", shopDomain)
            put("platform", "shopify")
            put("id", id.toLongOrNull()?.let { JsonPrimitive(it) } ?: JsonPrimitive(id))
            put("name", name)
            put("email", email)
            put("rating", rating)
            put("title", title)
            put("body", body)
        }
        send("submit", Request.Builder().url("https://api.judge.me/api/v1/reviews").post(review.toString().toRequestBody("application/json".toMediaType())).build())
    }

    /** The answer's JSON object (null when it isn't one); a non-2xx status is an [ArgonApiError.Http]. */
    private suspend fun send(call: String, request: Request): JsonObject? = withContext(Dispatchers.IO) {
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw ArgonApiError.Http(response.code)
                runCatching { Json.parseToJsonElement(response.body.string()) }.getOrNull() as? JsonObject
            }
        } catch (e: IOException) {
            throw ArgonApiError.Network(e)
        }
    }

    /** `gid://shopify/Product/123` -> `123`: Judge.me knows products by Shopify's numeric id. */
    private fun numericId(gid: String) = gid.substringBefore('?').substringAfterLast('/')
}

/**
 * Reads Judge.me's review widget HTML.
 * ponytail: it scans for Judge.me's class names and data attributes (regex, no HTML parser). A markup change on their
 * side shows fewer fields, never a crash: every field is optional but a review's id and rating. Upgrade: Judge.me's JSON
 * reviews endpoint, which needs the private token and so a server of the store's own.
 */
object JudgeMeHtml {
    fun parse(html: String, page: Int = 1, perPage: Int = 5): ReviewPage {
        val average = attribute(html, "data-average-rating")?.toDoubleOrNull()
        val count = attribute(html, "data-number-of-reviews")?.toIntOrNull()
        val summary = if (average == null || count == null) null else ReviewSummary(
            average,
            count,
            openTags(html, "jdgm-histogram__row").mapNotNull { row ->
                val stars = attribute(row, "data-rating")?.toIntOrNull()?.takeIf { it in 1..5 }
                val frequency = attribute(row, "data-frequency")?.toIntOrNull()
                if (stars == null || frequency == null) null else stars to frequency
            }.toMap(),
        )
        // a review is the chunk from its `<div class='jdgm-rev ...'>` to the next one
        val starts = REVIEW.findAll(html).map { html.lastIndexOf('<', it.range.first).coerceAtLeast(0) }.toList()
        val reviews = starts.mapIndexedNotNull { i, start -> review(html.substring(start, starts.getOrElse(i + 1) { html.length })) }
        return ReviewPage(summary, reviews, page, hasNextPage = summary != null && summary.count > page * perPage)
    }

    private fun review(chunk: String): Review? {
        val id = attribute(chunk, "data-review-id")?.takeIf { it.isNotEmpty() } ?: return null
        val rating = openTags(chunk, "jdgm-rev__rating").firstNotNullOfOrNull { attribute(it, "data-score")?.toIntOrNull() } ?: return null
        val time = openTags(chunk, "jdgm-rev__timestamp").firstOrNull().orEmpty()
        return Review(
            id = id,
            rating = rating,
            title = element(chunk, "jdgm-rev__title")?.let(::text)?.takeIf { it.isNotEmpty() },
            body = element(chunk, "jdgm-rev__body")?.let(::text).orEmpty(),
            author = element(chunk, "jdgm-rev__author")?.let(::text).orEmpty(),
            verified = attribute(chunk, "data-verified-buyer") == "true",
            date = attribute(time, "datetime")?.takeIf { it.isNotEmpty() } ?: attribute(time, "data-content")?.let(::isoDate),
            pictures = openTags(chunk, "jdgm-rev__pic-link").mapNotNull { attribute(it, "href")?.let(::decodeEntities) }.filter { it.isNotEmpty() },
            reply = element(chunk, "jdgm-rev__reply-content")?.let(::text)?.takeIf { it.isNotEmpty() },
        )
    }

    /** HTML as plain text: paragraph ends and line breaks become newlines, other tags go, entities are decoded. */
    internal fun text(html: String): String =
        decodeEntities(html.replace(BREAK, "\n").replace(TAG, "")).trim()

    private val REVIEW = Regex("""class\s*=\s*['"]jdgm-rev[\s'"]""")
    private val BREAK = Regex("""</p\s*>|<br\s*/?>""", RegexOption.IGNORE_CASE)
    private val TAG = Regex("<[^>]+>")
    private val ENTITY = Regex("""&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);""")
    private val UTC = Regex("""(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) UTC""")
    private val NAMED = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ", "mdash" to "—")

    /** Decoded once, left to right, so `&amp;lt;` stays `&lt;`. An entity this doesn't know is left as it is. */
    private fun decodeEntities(text: String): String = ENTITY.replace(text) { match ->
        val name = match.groupValues[1]
        val code = when {
            name.startsWith("#x") || name.startsWith("#X") -> name.drop(2).toIntOrNull(16)
            name.startsWith("#") -> name.drop(1).toIntOrNull()
            else -> return@replace NAMED[name] ?: match.value
        }
        code?.takeIf { Character.isValidCodePoint(it) }?.let { String(Character.toChars(it)) } ?: match.value
    }

    /** "2026-10-09 14:22:31 UTC" -> "2026-10-09T14:22:31Z"; null for anything else. */
    private fun isoDate(text: String): String? = UTC.matchEntire(text.trim())?.let { "${it.groupValues[1]}T${it.groupValues[2]}Z" }

    /** The value of attribute [name] at its first occurrence in [html]: quoted either way, or bare. */
    private fun attribute(html: String, name: String): String? =
        Regex("""(?<![\w-])${Regex.escape(name)}\s*=\s*(?:'([^']*)'|"([^"]*)"|([^\s>'"]+))""").find(html)?.let { m -> m.groupValues.drop(1).firstOrNull { it.isNotEmpty() }.orEmpty() }

    /** The opening tags whose class list has [cssClass]. */
    private fun openTags(html: String, cssClass: String): List<String> = classed(cssClass).findAll(html).map { it.value }.toList()

    /** The inner HTML of the first element whose class list has [cssClass], up to its matching closing tag. */
    private fun element(html: String, cssClass: String): String? {
        val open = classed(cssClass).find(html) ?: return null
        val tag = open.groupValues[1]
        var depth = 1
        // same-named tags inside (a <div> in a review's <div> body) are counted, so the right closing tag ends it
        for (next in Regex("""<(/?)$tag\b[^>]*>""", RegexOption.IGNORE_CASE).findAll(html, open.range.last + 1)) {
            depth += if (next.groupValues[1].isEmpty()) 1 else -1
            if (depth == 0) return html.substring(open.range.last + 1, next.range.first)
        }
        return html.substring(open.range.last + 1) // unclosed: everything after it
    }

    private fun classed(cssClass: String) =
        Regex("""<(\w+)\b[^>]*\bclass\s*=\s*['"][^'"]*(?<![\w-])${Regex.escape(cssClass)}(?![\w-])[^'"]*['"][^>]*>""")
}
