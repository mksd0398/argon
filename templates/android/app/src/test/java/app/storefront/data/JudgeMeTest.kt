package app.storefront.data

import java.io.IOException
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
        assertEquals(4.33, summary.average!!, 0.0)
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
    private var offline = false

    // An interceptor answers every request, so nothing touches the network.
    private fun client(code: Int = 200, body: String, token: String = "public-token") = JudgeMe(
        "shop.test",
        token,
        OkHttpClient.Builder().addInterceptor { chain ->
            requests += chain.request()
            if (offline) throw IOException("offline")
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
        assertFalse("a sample is not a store without a token", sample.isTokenless)
    }

    // Without a token

    /** What Judge.me's own storefront widget is answered with (contract/fixtures/JudgeMeReviews.json): two reviews and their count. */
    private val tokenless = JudgeMeTest::class.java.getResource("/fixtures/JudgeMeReviews.json")!!.readText()
    private val tokenlessHtml = (json(tokenless)["html"] as JsonPrimitive).content

    /** The same answer for a product nobody has reviewed. */
    private val noReviews = buildJsonObject {
        put(
            "html",
            """<div class='jdgm-rev-widg__reviews'></div> <div class='jdgm-paginate' data-per-page='5' data-url='https://api.judge.me/reviews/reviews_for_widget' style="display: none;"></div>""",
        )
        put("total_count", 0)
        put("page", "1")
    }.toString()

    @Test
    fun theTokenlessHtmlIsTheReviewBlocksWithoutASummary() {
        val page = JudgeMeHtml.parse(tokenlessHtml)
        assertNull("no average, no count, no histogram", page.summary)
        assertEquals(
            listOf(
                Review(
                    id = "22222222-aaaa-4bbb-8ccc-000000000001",
                    rating = 5,
                    title = "Holds its shape & its colour",
                    body = "Third month of wearing the navy one most days. The cuffs haven't stretched.\nWould buy it again.",
                    author = "Mira K.",
                    verified = true,
                    date = "2026-10-06T09:15:42Z",
                    pictures = listOf("https://review-images.judgeme.com/example-store/1791700031__crewneck-navy__original.jpeg?quality=80&width=1024"),
                    reply = null,
                ),
                Review(
                    id = "22222222-aaaa-4bbb-8ccc-000000000002",
                    rating = 4,
                    title = "Good, runs warm",
                    body = "Nice weight. Too warm for me indoors.",
                    author = "Tomas R.",
                    verified = false,
                    date = "2026-09-19T17:48:03Z", // its timestamp has `data-content` only
                    pictures = emptyList(),
                    reply = "Thanks Tomas! The lighter knit is back in spring.",
                ),
            ),
            page.reviews,
        )
        assertTrue(JudgeMeHtml.parse((json(noReviews)["html"] as JsonPrimitive).content).reviews.isEmpty())
    }

    @Test
    fun withoutATokenTheReviewsComeFromTheWidgetsOwnEndpoint() = runBlocking {
        val judgeMe = client(body = tokenless, token = "")
        assertTrue(judgeMe.isTokenless)
        assertFalse(client(body = widgetJson).isTokenless)

        val page = judgeMe.reviews("gid://shopify/Product/7982905098262")
        assertEquals("the count alone: no average, no breakdown", ReviewSummary(null, 2, emptyMap()), page.summary)
        assertEquals(JudgeMeHtml.parse(tokenlessHtml).reviews, page.reviews)
        assertEquals(1, page.page)
        assertFalse(page.hasNextPage)

        val request = requests.single()
        assertEquals("GET", request.method)
        assertEquals("https://api.judge.me/reviews/reviews_for_widget", request.url.newBuilder().query(null).build().toString())
        assertEquals(
            mapOf("url" to "shop.test", "shop_domain" to "shop.test", "platform" to "shopify", "page" to "1", "per_page" to "5", "product_id" to "7982905098262"),
            request.url.queryParameterNames.associateWith { request.url.queryParameter(it) },
        )
        assertNull(request.header("X-Api-Token"))

        assertTrue("2 reviews, 1 a page", judgeMe.reviews("gid://shopify/Product/7982905098262", page = 1, perPage = 1).hasNextPage)
        assertFalse(judgeMe.reviews("gid://shopify/Product/7982905098262", page = 2, perPage = 1).hasNextPage)

        // writing a review never needed the token
        judgeMe.submit("gid://shopify/Product/7982905098262", "Ada", "ada@example.com", 5, "Lovely", "Soft")
        assertEquals("POST https://api.judge.me/api/v1/reviews", requests.last().let { "${it.method} ${it.url}" })
    }

    @Test
    fun aProductWithoutReviewsIsAnEmptyPageAndTheNextProductIsStillAskedFor() = runBlocking {
        val judgeMe = client(body = noReviews, token = "")
        assertEquals(ReviewPage(ReviewSummary(null, 0, emptyMap()), emptyList(), 1, hasNextPage = false), judgeMe.reviews("gid://shopify/Product/1"))
        judgeMe.reviews("gid://shopify/Product/2")
        assertEquals(2, requests.size)
    }

    @Test
    fun anyOtherAnswerTurnsTheTokenlessEndpointOffForTheRunWithoutAnError() = runBlocking {
        val answers = listOf(
            404 to """{"error":"Not found"}""",
            500 to "",
            200 to "<html>Not here</html>",
            200 to "[]",
            200 to """{"widget":"<div></div>"}""",
            200 to """{"html":"<div class='jdgm-rev-widg__reviews'></div>"}""",
            200 to """{"html":null,"total_count":0}""",
            200 to """{"html":"<div class='jdgm-rev-widg__reviews'></div>","total_count":"many"}""",
        )
        for ((code, body) in answers) {
            requests.clear()
            val judgeMe = client(code, body, token = "")
            assertEquals("$code $body", ReviewPage(null, emptyList(), 1, hasNextPage = false), judgeMe.reviews("gid://shopify/Product/1"))
            assertEquals(ReviewPage(null, emptyList(), 2, hasNextPage = false), judgeMe.reviews("gid://shopify/Product/2", page = 2))
            assertEquals("$code $body: asked once, then left alone", 1, requests.size)
        }
    }

    @Test
    fun beingOfflineIsNoAnswerTheNextCallAsksAgain() {
        val judgeMe = client(body = tokenless, token = "")
        offline = true
        assertThrows(ArgonApiError.Network::class.java) { runBlocking { judgeMe.reviews("gid://shopify/Product/1") } }
        offline = false
        assertEquals(2, runBlocking { judgeMe.reviews("gid://shopify/Product/1") }.reviews.size)
    }
}
