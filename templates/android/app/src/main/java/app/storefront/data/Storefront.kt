package app.storefront.data

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class StorefrontException(val messages: List<String>, val status: Int?) : Exception(messages.joinToString("\n"))

/** Storefront API client. `loadDocument(name)` returns the GraphQL document `queries/<name>.graphql`. */
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
    suspend fun query(name: String, variables: JsonObject = JsonObject(emptyMap())): JsonObject =
        withContext(Dispatchers.IO) {
            val document = documents.getOrPut(name) { loadDocument(name) }
            val body = JsonObject(mapOf("query" to JsonPrimitive(document), "variables" to variables)).toString()
            val request = Request.Builder()
                .url(url)
                .post(body.toRequestBody(JSON))
                .apply { if (token.isNotEmpty()) header("X-Shopify-Storefront-Access-Token", token) }
                .build()
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw StorefrontException(listOf("HTTP ${response.code}"), response.code)
                val text = response.body.string()
                val json = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject
                    ?: throw StorefrontException(listOf("Invalid response"), response.code)
                (json["errors"] as? JsonArray)?.let { errors ->
                    throw StorefrontException(errors.map { (it as? JsonObject)?.str("message") ?: it.toString() }, response.code)
                }
                json.obj("data") ?: throw StorefrontException(listOf("No data in response"), response.code)
            }
        }

    private companion object {
        val JSON = "application/json".toMediaType()
    }
}
