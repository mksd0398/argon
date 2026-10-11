package app.storefront.data

import java.io.IOException
import java.util.logging.Handler
import java.util.logging.LogRecord
import java.util.logging.Logger
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

    // Access denied: a Headless token without a permission answers 200 with the data and an error per denied field

    private fun denied(path: String, message: String = "Access denied for $path field.") =
        """{"message":"$message","path":[${path.split('.').joinToString(",") { "\"$it\"" }}],"extensions":{"code":"ACCESS_DENIED"}}"""

    @Test
    fun deniedFieldsComeBackNullWithTheRestOfTheData() {
        val data = """{"product":{"id":"p","variantBySelectedOptions":{"id":"v","quantityAvailable":null}},"shop":{"name":"S"}}"""
        val errors = """[${denied("product.variantBySelectedOptions.quantityAvailable")},${denied("product.rating", "Access denied for metafield field.")}]"""
        assertEquals(data, query("""{"data":$data,"errors":$errors}""").toString())
    }

    @Test
    fun aDeniedRootFieldIsStillAnError() {
        // the home screen's metaobject query on a token without metaobject access: nothing came back, so the caller must know
        val e = assertThrows(ArgonApiError.GraphQL::class.java) {
            query("""{"data":{"metaobject":null},"errors":[${denied("metaobject", "Access denied for metaobject field.")}]}""")
        }
        assertEquals(listOf("Access denied for metaobject field."), e.messages)
        // a non-null field refused deeper down nulls its parents up to the root: the same
        assertThrows(ArgonApiError.GraphQL::class.java) { query("""{"data":{"product":null},"errors":[${denied("product.metafields")}]}""") }
        assertThrows(ArgonApiError.GraphQL::class.java) { query("""{"data":null,"errors":[${denied("product.metafields")}]}""") }
    }

    @Test
    fun anyOtherErrorBesideADeniedFieldIsStillAnError() {
        val data = """{"product":{"id":"p","quantityAvailable":null}}"""
        val e = assertThrows(ArgonApiError.GraphQL::class.java) {
            query("""{"data":$data,"errors":[${denied("product.quantityAvailable")},{"message":"Throttled","extensions":{"code":"THROTTLED"}}]}""")
        }
        assertEquals(listOf("Access denied for product.quantityAvailable field.", "Throttled"), e.messages)
        assertThrows("a denied error that names no field", ArgonApiError.GraphQL::class.java) {
            query("""{"data":$data,"errors":[{"message":"Access denied","extensions":{"code":"ACCESS_DENIED"}}]}""")
        }
        assertThrows("the code is what counts, not the message", ArgonApiError.GraphQL::class.java) {
            query("""{"data":$data,"errors":[{"message":"Access denied for quantityAvailable field.","path":["product","quantityAvailable"]}]}""")
        }
        assertThrows("an empty errors list isn't a denial", ArgonApiError.GraphQL::class.java) { query("""{"data":$data,"errors":[]}""") }
    }

    @Test
    fun aDeniedMessageIsLoggedOnce() {
        val records = mutableListOf<String>()
        val handler = object : Handler() {
            override fun publish(record: LogRecord) { records += record.message }
            override fun flush() {}
            override fun close() {}
        }
        val log = Logger.getLogger("GraphQL").apply { addHandler(handler) }
        try {
            val body = """{"data":{"product":{"id":"p"}},"errors":[${denied("product.loggedOnce")},${denied("product.loggedOnce")}]}"""
            query(body)
            query(body)
            assertEquals(listOf("Q: Access denied for product.loggedOnce field."), records)
        } finally {
            log.removeHandler(handler)
        }
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
