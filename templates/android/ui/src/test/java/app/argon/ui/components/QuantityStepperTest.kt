package app.argon.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

// the same cases as iOS's ArgonUITests
class QuantityStepperTest {
    @Test
    fun plusAndMinusMoveOneStepInsideMinAndMax() {
        assertEquals(2, steppedQuantity(1, 1))
        assertEquals(4, steppedQuantity(5, -1))
        assertEquals("never under the minimum", 1, steppedQuantity(1, -1))
        assertEquals(10, steppedQuantity(9, 1, max = 10))
        assertEquals("never over the maximum", 10, steppedQuantity(10, 1, max = 10))
        assertEquals("no max: no upper end", 1001, steppedQuantity(1000, 1))
    }

    @Test
    fun theValueStaysOnTheGridThatStartsAtMin() {
        assertEquals(4, steppedQuantity(2, 1, min = 2, max = 40, step = 2))
        assertEquals(2, steppedQuantity(4, -1, min = 2, max = 40, step = 2))
        assertEquals(2, steppedQuantity(2, -1, min = 2, max = 40, step = 2))
        assertEquals(40, steppedQuantity(40, 1, min = 2, max = 40, step = 2))
        assertEquals("a value off the grid lands back on it", 4, steppedQuantity(3, 1, min = 2, max = 40, step = 2))
        assertEquals(2, steppedQuantity(3, -1, min = 2, max = 40, step = 2))
        assertEquals("1, 4, 7: 10 is over the maximum", 7, steppedQuantity(7, 1, min = 1, max = 9, step = 3))
        assertEquals(7, steppedQuantity(4, 1, min = 1, max = 9, step = 3))
    }

    @Test
    fun aMinOfZeroLetsMinusReachZero() {
        // a cart line's stepper: 0 removes the line
        assertEquals(0, steppedQuantity(6, -1, min = 0, step = 6))
        assertEquals(6, steppedQuantity(0, 1, min = 0, step = 6))
        assertEquals(0, steppedQuantity(0, -1, min = 0, step = 6))
    }

    @Test
    fun oddRulesStillGiveAQuantity() {
        // stores without quantity rules send an increment of 0
        assertEquals("a step of 0 is a step of 1", 2, steppedQuantity(1, 1, step = 0))
        assertEquals("a maximum under the minimum: the minimum", 5, steppedQuantity(5, 1, min = 5, max = 3))
        assertEquals("no move: the grid point at or below", 4, steppedQuantity(5, 0, min = 2, step = 2))
    }
}
