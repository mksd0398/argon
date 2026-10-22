package app.storefront.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.time.LocalDate
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DeliveryTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test
    fun decodesKryptonsAnswer() {
        val e = DeliveryEstimate.decode("""{"pincode":"560001","serviceable":true,"cod":false,"date":"2026-10-24","city":"Bengaluru"}""")!!
        assertEquals(DeliveryEstimate("560001", true, false, LocalDate.of(2026, 10, 24), "Bengaluru"), e)
        val off = DeliveryEstimate.decode("""{"pincode":"744101","serviceable":false,"cod":false,"date":null}""")!!
        assertFalse(off.serviceable)
        assertNull(off.date)
        assertNull("cod unknown", DeliveryEstimate.decode("""{"pincode":"1","serviceable":true,"cod":null,"date":"bad"}""")!!.cod)
        assertNull(DeliveryEstimate.decode("""{"serviceable":true}"""))
        assertNull(DeliveryEstimate.decode("not json"))
    }

    @Test
    fun linesSayTheDateCodOrNoDelivery() {
        val date = LocalDate.of(2026, 10, 22)
        assertEquals(
            listOf(DeliveryLine("Delivery by Thu, 22 Oct", DeliveryTone.Good), DeliveryLine("Cash on delivery available", DeliveryTone.Muted)),
            deliveryLines(DeliveryEstimate("560001", true, true, date, null), Locale.ENGLISH),
        )
        assertEquals(listOf(DeliveryLine("Delivery by Thu, 22 Oct", DeliveryTone.Good)), deliveryLines(DeliveryEstimate("560001", true, null, date, null), Locale.ENGLISH))
        assertEquals(listOf(DeliveryLine("Not delivering to 744101 yet", DeliveryTone.Bad)), deliveryLines(DeliveryEstimate("744101", false, false, null, null)))
    }

    @Test
    fun locationFromAnIndianAddressOnly() {
        assertEquals(DeliveryLocation("560001", "Bengaluru"), DeliveryLocation.of(CustomerAddress("a", city = " Bengaluru ", zip = "560 001", countryCode = "IN")))
        assertEquals(DeliveryLocation("560001"), DeliveryLocation.of(CustomerAddress("a", zip = "560001")))
        assertNull(DeliveryLocation.of(CustomerAddress("a", zip = "10001", countryCode = "US")))
        assertNull(DeliveryLocation.of(CustomerAddress("a", zip = "060001", countryCode = "IN")))
        assertEquals("560001 · Bengaluru", DeliveryLocation("560001", "Bengaluru").label)
        assertEquals("560001", DeliveryLocation("560001", " ").label)
    }

    @Test
    fun endpointIsNextToTheSettings() {
        assertEquals("https://k.web.app/v1/delivery/shop.myshopify.com", deliveryEndpoint("https://k.web.app/v1/settings/shop.myshopify.com"))
        assertEquals("", deliveryEndpoint(""))
        assertEquals("", deliveryEndpoint("https://elsewhere.test/settings.json"))
    }

    @Test
    fun storeKeepsTheLocationAndAsksOncePerPincode() = runBlocking {
        val asked = mutableListOf<String>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val pin = chain.request().url.queryParameter("pincode")!!
            asked += pin
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("ok")
                .body("""{"pincode":"$pin","serviceable":true,"cod":true,"date":"2026-10-24"}""".toResponseBody("application/json".toMediaType())).build()
        }.build()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val store = DeliveryStore(PreferenceDataStoreFactory.create(scope = scope) { File(tmp.root, "delivery.preferences_pb") }, scope, "https://k.test/v1/delivery/s", http)
        store.prefill(CustomerAddress("a", zip = "110001", city = "Delhi"))
        assertEquals(DeliveryLocation("110001", "Delhi"), store.location.value)
        store.prefill(CustomerAddress("b", zip = "560001"))
        assertEquals("prefill never replaces a chosen location", "110001", store.location.value?.pincode)
        store.set(DeliveryLocation("560001"))
        store.fill(DeliveryLocation("400001", "Mumbai"))
        assertEquals("the device's location never replaces a chosen one", "560001", store.location.value?.pincode)
        assertFalse(store.unset())
        assertEquals(LocalDate.of(2026, 10, 24), store.estimate("560001")?.date)
        store.estimate("560001")
        assertEquals(listOf("560001"), asked)
        assertTrue(DeliveryStore(PreferenceDataStoreFactory.create(scope = scope) { File(tmp.root, "other.preferences_pb") }, scope, "", http).estimate("560001") == null)
        assertEquals(1, asked.size)
        store.location.first()
        Unit
    }
}
