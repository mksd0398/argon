package app.argon.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class OtpInputTest {
    @Test
    fun typingAddsDigits() {
        assertEquals("1" to false, otpInput("", "1"))
        assertEquals("12" to false, otpInput("1", "12"))
    }

    @Test
    fun deletingRemovesTheLastDigit() {
        assertEquals("12" to false, otpInput("123", "12"))
        assertEquals("" to false, otpInput("1", ""))
    }

    @Test
    fun pastingAWholeCodeCompletesIt() {
        assertEquals("123456" to true, otpInput("", "123456"))
        assertEquals("482913" to true, otpInput("", "Your code is 482 913"))
        assertEquals("123456" to true, otpInput("", "123-456"))
        // pasted after digits already typed: the paste wins
        assertEquals("123456" to true, otpInput("98", "98123456"))
        // SMS autofill replacing the text
        assertEquals("654321" to true, otpInput("12", "654321"))
    }

    @Test
    fun nonDigitsAreIgnored() {
        assertEquals("1" to false, otpInput("1", "1a"))
        assertEquals("1" to false, otpInput("1", "1 "))
        assertEquals("" to false, otpInput("", "١٢٣")) // non-ASCII digits
    }

    @Test
    fun extraDigitsBeyondTheLengthAreDropped() {
        assertEquals("123456" to false, otpInput("123456", "1234567"))
        assertEquals("1234" to true, otpInput("123", "12345", length = 4))
    }

    @Test
    fun onCompleteFiresOnce() {
        var code = ""
        var completions = 0
        fun field(text: String) {
            val (next, complete) = otpInput(code, text)
            code = next
            if (complete) completions++
        }
        for (i in 1..6) field(code + i)
        field(code + "7") // a seventh digit
        field(code) // the same text again
        field("123456") // a paste of the same code
        assertEquals("123456", code)
        assertEquals(1, completions)
        field("12345")
        field("123459") // a corrected last digit completes a new code
        assertEquals(2, completions)
    }

    @Test
    fun aCleanupPassDoesNotCompleteTwice() = assertEquals("123456" to false, otpInput("123456x", "123456"))
}
