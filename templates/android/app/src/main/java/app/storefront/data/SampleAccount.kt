package app.storefront.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * A [CustomerAccountApi] transport for the demo store, which has no customer accounts: every operation, mutations too,
 * answers its bundled sample `sample/<Operation>.sample.json` ([read] returns the asset's text; the CLI copies the
 * contract fixtures there for mock.shop only). Nothing is sent and nothing is saved.
 */
internal fun sampleTransport(read: (String) -> String): suspend (String, JsonObject) -> JsonObject = { operation, _ ->
    withContext(Dispatchers.IO) {
        runCatching { Json.parseToJsonElement(read("sample/$operation.sample.json")) as? JsonObject }.getOrNull()
            ?: throw ArgonApiError.Decoding(operation, "no sample")
    }
}
