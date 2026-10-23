package app.storefront.data

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

class CrashReportsTest {
    private class Recorded : CrashBackend {
        val logs = mutableListOf<String>()
        val errors = mutableListOf<Throwable>()

        override fun setKey(key: String, value: String) {}

        override fun log(message: String) {
            logs += message
        }

        override fun record(error: Throwable) {
            errors += error
        }
    }

    @After fun reset() {
        CrashReports.backend = null
    }

    @Test fun `broken Liquid is a non-fatal report, and still renders without its Liquid`() {
        val recorded = Recorded().also { CrashReports.backend = it }
        assertEquals("a b", Liquid.render("a {% if x %}b", emptyMap()))
        assertEquals(1, recorded.errors.size)
        assertEquals("non-fatal: liquid: a {% if x %}b", recorded.logs.single())
    }

    @Test fun `a breadcrumb is the event and its flat parameters`() {
        assertEquals("screen_view {screen_name=product}", breadcrumb(AnalyticsEvent.ScreenView("product")))
        val recorded = Recorded().also { CrashReports.backend = it }
        CrashSink().track(AnalyticsEvent.Search("shoes"))
        assertEquals(listOf(breadcrumb(AnalyticsEvent.Search("shoes"))), recorded.logs)
    }

    @Test fun `a backend that throws never reaches the caller, and none at all is a no-op`() {
        CrashReports.record(IllegalStateException("x"), "nothing set up")
        CrashReports.backend = object : CrashBackend {
            override fun setKey(key: String, value: String) = error("broken")
            override fun log(message: String) = error("broken")
            override fun record(error: Throwable) = error("broken")
        }
        CrashReports.setKey("screen", "home")
        CrashReports.record(IllegalStateException("x"), "broken backend")
    }
}
