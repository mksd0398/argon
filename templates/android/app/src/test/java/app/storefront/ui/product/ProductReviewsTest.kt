package app.storefront.ui.product

import app.storefront.data.Review
import app.storefront.data.ReviewPage
import app.storefront.data.ReviewSummary
import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProductReviewsTest {
    // The write-a-review form

    private val valid = ReviewForm(rating = 5, title = "", body = "Soft and warm.", name = "Ada", email = "ada@example.com")

    @Test
    fun aReviewWithARatingABodyANameAndAnEmailCanBeSent() {
        assertTrue(validate(valid).isEmpty)
        assertTrue("the title is optional", validate(valid.copy(title = "Love it")).isEmpty)
        assertTrue("spaces around the email are not the shopper's mistake", validate(valid.copy(email = " ada@example.com ")).isEmpty)
    }

    @Test
    fun anEmptyFormSaysWhatIsMissingFieldByField() {
        assertEquals(
            ReviewFormErrors(rating = "Choose a rating", body = "Write your review", name = "Enter your name", email = "Enter a valid email address"),
            validate(ReviewForm()),
        )
        assertFalse(validate(ReviewForm()).isEmpty)
    }

    @Test
    fun theRatingMustBeChosen() {
        assertEquals(ReviewFormErrors(rating = "Choose a rating"), validate(valid.copy(rating = 0)))
        assertEquals(ReviewFormErrors(rating = "Choose a rating"), validate(valid.copy(rating = 6)))
        for (stars in 1..5) assertNull(validate(valid.copy(rating = stars)).rating)
    }

    @Test
    fun theBodyAndTheNameMustNotBeBlank() {
        assertEquals(ReviewFormErrors(body = "Write your review"), validate(valid.copy(body = "  \n ")))
        assertEquals(ReviewFormErrors(name = "Enter your name"), validate(valid.copy(name = " ")))
    }

    @Test
    fun theEmailMustBePlausible() {
        for (email in listOf("ada@example.com", "a@b.co", "first.last+tag@mail.example.org")) {
            assertNull(email, validate(valid.copy(email = email)).email)
        }
        for (email in listOf("", "ada", "ada@", "ada@example", "@example.com", "ada@.com", "ada@example.", "a da@example.com", "ada@@example.com")) {
            assertEquals(email, "Enter a valid email address", validate(valid.copy(email = email)).email)
        }
    }

    // The summary

    private fun summary(count: Int, histogram: Map<Int, Int> = emptyMap()) = ReviewSummary(4.6, count, histogram)

    @Test
    fun theTitlesStarsComeFromTheReviewsElseFromTheRatingMetafields() {
        assertEquals(4.6 to 128, shownRating(summary(128), rating = 4.0, ratingCount = 10))
        assertEquals("no reviews loaded: the metafields", 4.0 to 10, shownRating(summary(0), rating = 4.0, ratingCount = 10))
        assertEquals(4.0 to null, shownRating(null, rating = 4.0, ratingCount = null))
        assertNull("rated by nobody", shownRating(null, rating = 4.0, ratingCount = 0))
        assertNull(shownRating(null, rating = null, ratingCount = 5))
        assertNull(shownRating(summary(0), rating = null, ratingCount = null))
        // reviews read without a token, their average not known yet
        assertNull("a count is no stars", shownRating(ReviewSummary(null, 12, emptyMap()), rating = null, ratingCount = null))
        assertEquals(4.0 to 10, shownRating(ReviewSummary(null, 12, emptyMap()), rating = 4.0, ratingCount = 10))
    }

    @Test
    fun reviewsWithoutAnAverageTakeTheRatingMetafieldElseTheirOwnMeanOnceAllAreLoaded() {
        val two = listOf(review(1, stars = 5), review(2, stars = 4))
        assertEquals("the store's metafield, whatever is loaded", 4.2, reviewAverage(rating = 4.2, count = 12, loaded = two))
        assertEquals(4.2, reviewAverage(rating = 4.2, count = 2, loaded = two))
        assertEquals("both reviews are here: their mean", 4.5, reviewAverage(rating = null, count = 2, loaded = two))
        assertNull("ten more are not loaded", reviewAverage(rating = null, count = 12, loaded = two))
        assertNull(reviewAverage(rating = null, count = 0, loaded = emptyList()))
        assertEquals("a rating of 0 is none", 4.5, reviewAverage(rating = 0.0, count = 2, loaded = two))
    }

    @Test
    fun aHistogramBarIsItsShareOfAllReviews() {
        val reviews = summary(128, mapOf(5 to 96, 4 to 32))
        assertEquals(0.75f, histogramShare(reviews, 5))
        assertEquals(0.25f, histogramShare(reviews, 4))
        assertEquals(0f, histogramShare(reviews, 1))
        assertEquals("no reviews, no division", 0f, histogramShare(summary(0), 5))
    }

    @Test
    fun countsAndAveragesReadAsWords() {
        assertEquals("1 star", starsLabel(1))
        assertEquals("5 stars", starsLabel(5))
        assertEquals("1 review", reviewCountLabel(1))
        assertEquals("128 reviews", reviewCountLabel(128))
        assertEquals("0 reviews", reviewCountLabel(0))
        assertEquals("4.6", averageLabel(4.56))
        assertEquals("5.0", averageLabel(5.0))
    }

    // Loading

    private fun review(id: Int, stars: Int = 5) = Review("$id", stars, null, "Body $id", "Ada", verified = true, date = null, pictures = emptyList(), reply = null)

    /** Seven reviews, five a page; review 5 shows again on page 2 (a new review came in between the two calls). */
    private class Pages {
        val asked = mutableListOf<Int>()
        var failing = false

        fun load(page: Int, review: (Int) -> Review): ReviewPage {
            asked += page
            if (failing) throw IOException("offline")
            val ids = if (page == 1) 1..5 else 5..7
            return ReviewPage(ReviewSummary(4.6, 7, mapOf(5 to 7)), ids.map(review), page, hasNextPage = page == 1)
        }
    }

    @Test
    fun loadMoreAddsTheNextPageUnderTheFirst() = runBlocking {
        val pages = Pages()
        val reviews = ReviewsState({ pages.load(it, ::review) }, {})
        assertFalse(reviews.isLoaded)
        reviews.loadFirst()
        assertTrue(reviews.isLoaded)
        assertEquals(7, reviews.summary?.count)
        assertEquals(listOf("1", "2", "3", "4", "5"), reviews.items.map { it.id })
        assertTrue(reviews.hasMore)
        reviews.loadFirst()
        assertEquals("the first page is loaded once", listOf(1), pages.asked)
        reviews.loadMore()
        assertEquals("a review seen on both pages shows once", listOf("1", "2", "3", "4", "5", "6", "7"), reviews.items.map { it.id })
        assertFalse(reviews.hasMore)
        assertFalse(reviews.isLoading)
    }

    @Test
    fun aFailedLoadIsQuietAndRetryAsksForTheSamePage() = runBlocking {
        val pages = Pages()
        val reviews = ReviewsState({ pages.load(it, ::review) }, {})
        pages.failing = true
        reviews.loadFirst()
        assertTrue(reviews.failed)
        assertFalse(reviews.isLoaded)
        assertFalse(reviews.isLoading)
        assertEquals(emptyList<Review>(), reviews.items)
        pages.failing = false
        reviews.loadMore()
        assertFalse(reviews.failed)
        assertEquals(listOf(1, 1), pages.asked)
        assertEquals(5, reviews.items.size)

        pages.failing = true
        reviews.loadMore()
        assertTrue(reviews.failed)
        assertEquals("what was loaded stays", 5, reviews.items.size)
        assertTrue(reviews.hasMore)
        pages.failing = false
        reviews.loadMore()
        assertEquals(listOf(1, 1, 2, 2), pages.asked)
        assertEquals(7, reviews.items.size)
    }

    // Without a token: three reviews, two a page, with their count and nothing else

    private fun tokenless(page: Int) =
        ReviewPage(ReviewSummary(null, 3, emptyMap()), if (page == 1) listOf(review(1, stars = 5), review(2, stars = 4)) else listOf(review(3, stars = 3)), page, hasNextPage = page == 1)

    @Test
    fun withoutATokenTheBlockWaitsForAReviewAndTheAverageForAllOfThem() = runBlocking {
        val reviews = ReviewsState({ tokenless(it) }, {}, hidesEmpty = true)
        assertFalse("nothing is known of the store's reviews yet", reviews.isShown)
        assertTrue("with a token the block is there from the start", ReviewsState({ tokenless(it) }, {}).isShown)
        reviews.loadFirst()
        assertTrue(reviews.isShown)
        assertEquals("one review is not loaded: the count alone", ReviewSummary(null, 3, emptyMap()), reviews.summary)
        reviews.loadMore()
        assertEquals("all three: (5 + 4 + 3) / 3", ReviewSummary(4.0, 3, emptyMap()), reviews.summary)

        val rated = ReviewsState({ tokenless(it) }, {}, rating = 4.6, hidesEmpty = true)
        rated.loadFirst()
        assertEquals("the product's rating metafield, from the first page on", 4.6, rated.summary?.average)
    }

    @Test
    fun withoutATokenAProductWithoutReviewsAndAFailedLoadShowNoBlock() = runBlocking {
        val none = ReviewsState({ ReviewPage(ReviewSummary(null, 0, emptyMap()), emptyList(), it, hasNextPage = false) }, {}, hidesEmpty = true)
        none.loadFirst()
        assertTrue(none.isLoaded)
        assertFalse(none.isShown)

        val offline = ReviewsState({ throw IOException("offline") }, {}, hidesEmpty = true)
        offline.loadFirst()
        assertTrue(offline.failed)
        assertFalse("no retry line for reviews that may not exist", offline.isShown)
    }

    @Test
    fun submitSendsTheForm() = runBlocking {
        val sent = mutableListOf<ReviewForm>()
        val reviews = ReviewsState({ ReviewPage(null, emptyList(), it, false) }, { sent += it })
        reviews.submit(valid)
        assertEquals(listOf(valid), sent)
    }
}
