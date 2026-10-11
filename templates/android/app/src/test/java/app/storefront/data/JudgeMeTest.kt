package app.storefront.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class JudgeMeTest {
    /** Judge.me's product review widget as its Widget API sends it (contract/fixtures/JudgeMeWidget.html). */
    private val widget = JudgeMeTest::class.java.getResource("/fixtures/JudgeMeWidget.html")!!.readText()

    // The widget HTML

    @Test
    fun theSummaryComesFromTheWidgetsDataAttributes() {
        val summary = JudgeMeHtml.parse(widget).summary!!
        assertEquals(4.33, summary.average, 0.0)
        assertEquals(12, summary.count)
        assertEquals("the clear-filter row is no rating", mapOf(5 to 8, 4 to 2, 3 to 1, 2 to 0, 1 to 1), summary.histogram)
    }

    @Test
    fun everyReviewIsRead() {
        val reviews = JudgeMeHtml.parse(widget).reviews
        assertEquals(
            listOf("11111111-aaaa-4bbb-8ccc-000000000001", "11111111-aaaa-4bbb-8ccc-000000000002", "11111111-aaaa-4bbb-8ccc-000000000003"),
            reviews.map { it.id },
        )
        assertEquals(listOf(5, 4, 1), reviews.map { it.rating })
        assertEquals(listOf("Ada L.", "Grace H.", "Anonymous"), reviews.map { it.author })
        assertEquals(listOf(true, true, false), reviews.map { it.verified })
        assertEquals(listOf("2026-10-09T14:22:31Z", "2026-09-28T08:05:00Z", "2026-09-02T19:40:12Z"), reviews.map { it.date })

        val (ada, grace, anonymous) = reviews
        assertEquals("entities are decoded", "Soft, warm & true to size", ada.title)
        assertEquals(
            "paragraphs become lines",
            "Bought the olive one in medium. It's heavier than I expected — in a good way.\nWashed it twice, no shrinking.",
            ada.body,
        )
        assertEquals(
            "the full-size picture, its URL decoded",
            listOf("https://review-images.judgeme.com/example-store/1791654122__crewneck-olive__original.jpeg?quality=80&width=1024"),
            ada.pictures,
        )
        assertNull(ada.reply)

        assertEquals("Great, sleeves a little long", grace.title)
        assertEquals("Thanks Grace! The small has a shorter sleeve — happy to exchange it.", grace.reply)
        assertTrue(grace.pictures.isEmpty())

        assertNull("an empty title is no title", anonymous.title)
        assertEquals("Arrived late.", anonymous.body)
        assertNull(anonymous.reply)
    }

    @Test
    fun thereIsANextPageWhileTheCountIsNotReached() {
        assertTrue("12 reviews, 5 shown", JudgeMeHtml.parse(widget, page = 1, perPage = 5).hasNextPage)
        assertTrue(JudgeMeHtml.parse(widget, page = 2, perPage = 5).hasNextPage)
        assertFalse(JudgeMeHtml.parse(widget, page = 3, perPage = 5).hasNextPage)
        assertFalse(JudgeMeHtml.parse(widget, page = 1, perPage = 12).hasNextPage)
        assertEquals(2, JudgeMeHtml.parse(widget, page = 2).page)
    }

    @Test
    fun otherMarkupShowsFewerFieldsNeverACrash() {
        val empty = JudgeMeHtml.parse("")
        assertNull(empty.summary)
        assertTrue(empty.reviews.isEmpty())
        assertFalse(empty.hasNextPage)

        // double quotes, the date only as text, a nested <div> in the body, a <br>, numeric entities, an unknown one
        val page = JudgeMeHtml.parse(
            """<div class="jdgm-rev-widg" data-number-of-reviews="1">
            <div data-review-id="r1" class="jdgm-rev" data-verified-buyer="false">
              <span class="jdgm-rev__rating" data-score="3"></span>
              <span class="jdgm-rev__timestamp" data-content="2026-01-02 03:04:05 UTC"></span>
              <div class="jdgm-rev__body">Line one<br/>Line&nbsp;two <div>inner &#169; &#xA9; &bogus; &amp;lt;</div> end</div>
            </div>
            <div class="jdgm-rev" data-review-id="r2"><span class="jdgm-rev__author">No rating</span></div>
            <div class="jdgm-rev"><span class="jdgm-rev__rating" data-score="5"></span></div>""",
        )
        assertNull("no average: no summary", page.summary)
        val review = page.reviews.single()
        assertEquals("a review needs its id and its rating; the two without are left out", "r1", review.id)
        assertEquals(3, review.rating)
        assertEquals("2026-01-02T03:04:05Z", review.date)
        assertEquals("Line one\nLine two inner © © &bogus; &lt; end", review.body)
        assertEquals("", review.author)
        assertNull(review.title)
        assertFalse(review.verified)
    }

    // The client

    private val requests = mutableListOf<Request>()

    // An interceptor answers every request, so nothing touches the network.
    private fun client(code: Int = 200, body: String) = JudgeMe(
        "shop.test",
        "public-token",
        OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(code).message("test")
                .body(body.toResponseBody("application/json".toMediaType())).build()
        }.build(),
    )

    private val widgetJson = buildJsonObject { put("widget", widget) }.toString()

    @Test
    fun reviewsAsksTheWidgetApiWithThePublicToken() = runBlocking {
        val page = client(body = widgetJson).reviews("gid://shopify/Product/7982905098262", page = 2, perPage = 5)
        assertEquals(3, page.reviews.size)
        assertEquals(2, page.page)
        assertTrue(page.hasNextPage)

        val request = requests.single()
        assertEquals("GET", request.method)
        assertEquals("https://api.judge.me/api/v1/widgets/product_review", request.url.newBuilder().query(null).build().toString())
        assertEquals("shop.test", request.url.queryParameter("shop_domain"))
        assertEquals("the product's numeric id", "7982905098262", request.url.queryParameter("external_id"))
        assertEquals("2", request.url.queryParameter("page"))
        assertEquals("5", request.url.queryParameter("per_page"))
        assertEquals("public-token", request.header("X-Api-Token"))
    }

    @Test
    fun submitPostsTheReviewWithoutAToken() = runBlocking {
        client(body = """{"message":"ok"}""").submit("gid://shopify/Product/7982905098262", "Ada", "ada@example.com", 5, "Lovely", "Soft \"and\" warm")
        val request = requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://api.judge.me/api/v1/reviews", request.url.toString())
        assertNull(request.header("X-Api-Token"))
        val sent = json(Buffer().also { request.body!!.writeTo(it) }.readUtf8())
        assertEquals(
            buildJsonObject {
                put("shop_domain", "shop.test")
                put("platform", "shopify")
                put("id", 7982905098262)
                put("name", "Ada")
                put("email", "ada@example.com")
                put("rating", 5)
                put("title", "Lovely")
                put("body", "Soft \"and\" warm")
            },
            sent,
        )
        assertEquals("the id is a number", JsonPrimitive(7982905098262), sent["id"])
    }

    @Test
    fun failuresAreApiErrors() {
        val refused = assertThrows(ArgonApiError.Http::class.java) { runBlocking { client(code = 401, body = "{}").reviews("gid://shopify/Product/1") } }
        assertEquals(401, refused.status)
        assertThrows(ArgonApiError.Http::class.java) { runBlocking { client(code = 422, body = "{}").submit("gid://shopify/Product/1", "A", "a@b.test", 5, "", "") } }
        val shape = assertThrows(ArgonApiError.Decoding::class.java) { runBlocking { client(body = """{"error":"no widget"}""").reviews("gid://shopify/Product/1") } }
        assertEquals("no widget", shape.detail)
    }

    @Test
    fun theDemoStoresSampleIsOnePageAndSendsNothing() = runBlocking {
        val http = OkHttpClient.Builder().addInterceptor { chain -> requests += chain.request(); error("the sample must not use the network") }.build()
        val sample = JudgeMe("mock.shop", "", http, sample = { widget })
        assertTrue(sample.isSample)
        assertFalse(client(body = widgetJson).isSample)

        val first = sample.reviews("gid://shopify/Product/1")
        assertEquals(3, first.reviews.size)
        assertEquals(12, first.summary?.count)
        assertFalse("the sample has no second page to load", first.hasNextPage)
        assertTrue(sample.reviews("gid://shopify/Product/1", page = 2).reviews.isEmpty())

        sample.submit("gid://shopify/Product/1", "Ada", "ada@example.com", 5, "Lovely", "Soft")
        assertTrue(requests.isEmpty())
    }
}
