package app.argon.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BadgeTest {
    @Test
    fun nullIsADot() = assertNull(badgeText(null))

    @Test
    fun countsShowUpToNinetyNine() {
        assertEquals("0", badgeText(0))
        assertEquals("0", badgeText(-3))
        assertEquals("1", badgeText(1))
        assertEquals("99", badgeText(99))
    }

    @Test
    fun countsAboveNinetyNineAreCapped() {
        assertEquals("99+", badgeText(100))
        assertEquals("99+", badgeText(12_000))
    }
}
