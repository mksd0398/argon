package app.argon.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class RangeSliderTest {
    private val prices = 0f..500f

    @Test
    fun thumbsStayInsideTheBounds() {
        assertEquals(0f to 500f, clampRange(-10f, 600f, prices))
        assertEquals(500f to 500f, clampRange(700f, 800f, prices))
    }

    @Test
    fun lowerNeverPassesUpper() {
        assertEquals(50f to 50f, clampRange(80f, 50f, 0f..100f))
        assertEquals(250f to 250f, clampRange(250f, 250f, prices))
    }

    @Test
    fun valuesSnapToTheStep() {
        assertEquals(40f to 260f, clampRange(42f, 258f, prices, step = 10f))
        assertEquals(50f, clampRange(0f, 47f, 0f..100f, step = 10f).second)
        assertEquals(10f, clampRange(12f, 100f, 0f..100f, step = 5f).first)
        assertEquals("steps count from the lower bound", 14f, snapToStep(13f, 10f..20f, 4f))
        assertEquals("a step past the upper bound falls back inside", 8f, snapToStep(20f, 0f..10f, 4f))
    }

    @Test
    fun noStepMeansContinuous() {
        assertEquals(42.5f to 258.25f, clampRange(42.5f, 258.25f, prices))
        assertEquals(42.5f to 258.25f, clampRange(42.5f, 258.25f, prices, step = 0f))
    }

    @Test
    fun materialStepsCountTheStopsBetweenTheEnds() {
        assertEquals(49, sliderSteps(prices, 10f))
        assertEquals(0, sliderSteps(prices, null))
        assertEquals(0, sliderSteps(prices, 1000f))
        assertEquals("a step that doesn't divide the range: continuous, snapped by clampRange", 0, sliderSteps(0f..10f, 4f))
    }
}
