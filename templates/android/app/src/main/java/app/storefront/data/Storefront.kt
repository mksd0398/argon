package app.storefront.data

import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Every way a Storefront or Customer Account API call fails. [message] can be shown to the shopper. */
sealed class ArgonApiError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** No answer: offline, timed out, or the connection dropped. */
    class Network(cause: IOException) : ArgonApiError(cause.message ?: cause.toString(), cause)

    /** The server answered with a non-2xx HTTP [status]. */
    class Http(val status: Int) : ArgonApiError("HTTP $status")

    /** A 200 carrying `errors`: the API refused the operation (an unknown field, a missing permission, throttling). */
    class GraphQL(val messages: List<String>) : ArgonApiError(messages.joinToString("\n"))

    /**
     * A mutation's `userErrors`: understood, but refused (bad input, not enough stock). [cart]: the cart a cart mutation
     * returned beside them, if any (unchanged or partly changed).
     */
    class UserErrors(val errors: List<UserError>, val cart: Cart? = null) : ArgonApiError(errors.joinToString("\n") { it.message })

    /** The response isn't the shape [operation]'s document asks for; [detail] says where. */
    class Decoding(val operation: String, val detail: String) : ArgonApiError("Invalid response") {
        override fun toString() = "ArgonApiError.Decoding($operation): $detail"
    }
}

/**
 * The low-level Storefront API client: runs operation `queries/<name>.graphql` ([loadDocument] returns it) and returns its
 * `data`. [StorefrontApi] sits on it with typed calls.
 */
class Storefront(
    domain: String,
    private val token: String,
    apiVersion: String,
    private val loadDocument: (String) -> String,
    private val http: OkHttpClient,
) {
    private val url = "https://$domain/api/$apiVersion/graphql.json"
    private val documents = ConcurrentHashMap<String, String>()

    /** Runs operation [name] and returns its `data`. */
    suspend fun query(name: String, variables: JsonObject = JsonObject(emptyMap())): JsonObject {
        val document = withContext(Dispatchers.IO) { documents.getOrPut(name) { loadDocument(name) } }
        val request = Request.Builder()
            .url(url)
            .post(graphQLBody(document, variables))
            .apply { if (token.isNotEmpty()) header("X-Shopify-Storefront-Access-Token", token) }
            .build()
        return http.graphQL(name, request)
    }
}

internal fun graphQLBody(document: String, variables: JsonObject) =
    JsonObject(mapOf("query" to JsonPrimitive(document), "variables" to variables)).toString().toRequestBody("application/json".toMediaType())

/** Sends [operation]'s GraphQL [request] and returns the response's `data`. Shared by the Storefront and Customer Account clients. */
internal suspend fun OkHttpClient.graphQL(operation: String, request: Request): JsonObject = withContext(Dispatchers.IO) {
    try {
        newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw ArgonApiError.Http(response.code)
            val text = response.body.string()
            val json = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject
                ?: throw ArgonApiError.Decoding(operation, "the body isn't a JSON object")
            (json["errors"] as? JsonArray)?.let { errors ->
                throw ArgonApiError.GraphQL(errors.map { ((it as? JsonObject)?.get("message") as? JsonPrimitive)?.contentOrNull ?: it.toString() })
            }
            json["data"] as? JsonObject ?: throw ArgonApiError.Decoding(operation, "no data")
        }
    } catch (e: IOException) {
        throw ArgonApiError.Network(e)
    }
}
