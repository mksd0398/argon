package app.storefront.ui

import app.storefront.data.Money
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class MoneyTest {
    @Test
    fun displaysTheAmountInItsCurrency() {
        Locale.setDefault(Locale.US)
        assertEquals("$25.00", Money("25.0", "USD").display())
        assertEquals("$1,234.50", Money("1234.5", "USD").display())
    }

    @Test
    fun unknownCurrencyFallsBackToAmountAndCode() {
        assertEquals("5.0 ???", Money("5.0", "???").display())
    }
}
