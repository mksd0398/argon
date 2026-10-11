package app.argon.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class RatingTest {
    @Test
    fun starsFillUpToTheValue() {
        assertEquals(listOf(1f, 1f, 1f, 1f, 0.6f), (0..4).map { starFill(4.6, it) }.map { Math.round(it * 10) / 10f })
        assertEquals(listOf(1f, 1f, 1f, 0.5f, 0f), (0..4).map { starFill(3.5, it) })
        assertEquals(listOf(0f, 0f, 0f, 0f, 0f), (0..4).map { starFill(0.0, it) })
        assertEquals("above 5 is five full stars", 1f, starFill(7.0, 4))
        assertEquals(0f, starFill(-1.0, 0))
    }

    @Test
    fun theLabelSaysTheRatingAndTheReviewCount() {
        assertEquals("4.6 out of 5, 128 reviews", ratingLabel(4.6, 128))
        assertEquals("5.0 out of 5, 1 review", ratingLabel(5.0, 1))
        assertEquals("3.5 out of 5", ratingLabel(3.5))
        assertEquals("0.0 out of 5, 0 reviews", ratingLabel(0.0, 0))
        assertEquals("the value is kept to 0...5", "5.0 out of 5", ratingLabel(9.0))
    }
}
