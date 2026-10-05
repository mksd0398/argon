package app.storefront.data

import kotlinx.coroutines.runBlocking
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class StorefrontTest {
    // An interceptor answers every request, so nothing touches the network.
    private fun query(body: String, code: Int = 200) = runBlocking {
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(code).message("test")
                .body(body.toResponseBody("application/json".toMediaType())).build()
        }.build()
        Storefront("shop.test", "", "2026-10", { "query Q { shop { name } }" }, http).query("Q")
    }

    @Test
    fun returnsData() {
        assertEquals("""{"a":1}""", query("""{"data":{"a":1}}""").toString())
    }

    @Test
    fun unparseableBodyIsAStorefrontException() {
        val e = assertThrows(StorefrontException::class.java) { query("<html>") }
        assertEquals(listOf("Invalid response"), e.messages)
        assertEquals(200, e.status)
        assertFalse(e.isGraphQL)
    }

    @Test
    fun nonObjectBodyIsAStorefrontException() {
        val e = assertThrows(StorefrontException::class.java) { query("[1,2]") }
        assertEquals(listOf("Invalid response"), e.messages)
    }

    @Test
    fun graphqlErrorsAreAStorefrontException() {
        val e = assertThrows(StorefrontException::class.java) { query("""{"errors":[{"message":"boom"}]}""") }
        assertEquals(listOf("boom"), e.messages)
        assertTrue("a 200 carrying errors is a GraphQL failure", e.isGraphQL)
    }

    @Test
    fun httpFailureIsNotGraphql() {
        val e = assertThrows(StorefrontException::class.java) { query("service unavailable", code = 503) }
        assertEquals(listOf("HTTP 503"), e.messages)
        assertEquals(503, e.status)
        assertFalse(e.isGraphQL)
    }
}
