package app.storefront.data

import java.io.IOException
import kotlinx.coroutines.runBlocking
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class StorefrontTest {
    // An interceptor answers every request, so nothing touches the network.
    private fun query(body: String, code: Int = 200, failure: IOException? = null) = runBlocking {
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            failure?.let { throw it }
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
    fun anUnparseableBodyIsADecodingError() {
        val e = assertThrows(ArgonApiError.Decoding::class.java) { query("<html>") }
        assertEquals("Q", e.operation)
        assertEquals("Invalid response", e.message)
    }

    @Test
    fun aNonObjectBodyIsADecodingError() {
        assertThrows(ArgonApiError.Decoding::class.java) { query("[1,2]") }
    }

    @Test
    fun aResponseWithoutDataIsADecodingError() {
        assertEquals("no data", assertThrows(ArgonApiError.Decoding::class.java) { query("{}") }.detail)
    }

    @Test
    fun graphqlErrorsAreAGraphQLError() {
        val e = assertThrows(ArgonApiError.GraphQL::class.java) { query("""{"errors":[{"message":"boom"},{"message":"bang"}]}""") }
        assertEquals(listOf("boom", "bang"), e.messages)
        assertEquals("boom\nbang", e.message)
    }

    @Test
    fun anHttpFailureIsAnHttpError() {
        val e = assertThrows(ArgonApiError.Http::class.java) { query("service unavailable", code = 503) }
        assertEquals(503, e.status)
        assertEquals("HTTP 503", e.message)
    }

    @Test
    fun noAnswerIsANetworkError() {
        val offline = IOException("Unable to resolve host")
        val e = assertThrows(ArgonApiError.Network::class.java) { query("", failure = offline) }
        assertSame(offline, e.cause)
        assertEquals("Can't reach the store. Check your internet connection.", e.message)
    }
}
