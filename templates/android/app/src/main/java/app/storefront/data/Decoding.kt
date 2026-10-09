package app.storefront.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * How responses are decoded and inputs encoded. A response carries fields a model may not read; a missing or null field
 * takes the model's default. Inputs leave their null fields out.
 */
internal val ArgonJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
}

/** The `__typename` a polymorphic result selects. */
internal val JsonElement.typename: String?
    get() = ((this as? JsonObject)?.get("__typename") as? JsonPrimitive)?.contentOrNull

/**
 * The value at [path] in [operation]'s `data`, decoded; a missing key along the way reads as null. A response the model
 * doesn't fit is an [ArgonApiError.Decoding].
 */
internal inline fun <reified T> decode(operation: String, data: JsonObject, vararg path: String): T {
    val value = path.fold<String, JsonElement?>(data) { node, key -> (node as? JsonObject)?.get(key) } ?: JsonNull
    return try {
        ArgonJson.decodeFromJsonElement(value)
    } catch (e: IllegalArgumentException) { // SerializationException and its subclasses
        throw ArgonApiError.Decoding(operation, e.message ?: e.toString())
    }
}

/** GraphQL variables; null values are left out (an absent variable is null to GraphQL). */
internal fun vars(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(
    pairs.mapNotNull { (name, value) ->
        when (value) {
            null -> null
            is JsonElement -> name to value
            is String -> name to JsonPrimitive(value)
            is Number -> name to JsonPrimitive(value)
            is Boolean -> name to JsonPrimitive(value)
            else -> error("Unsupported variable type ${value::class} for $name")
        }
    }.toMap(),
)

/** A typed input as a GraphQL variable value. */
internal inline fun <reified T> encode(value: T): JsonElement = ArgonJson.encodeToJsonElement(value)

// A connection as the API sends it. `filters` (collection products) and `productFilters` (search) only on product lists.
@Serializable
private class Connection<T>(
    val nodes: List<T> = emptyList(),
    val pageInfo: PageInfo? = null,
    val filters: List<Filter> = emptyList(),
    val productFilters: List<Filter> = emptyList(),
)

@Serializable
private class PageInfo(val hasNextPage: Boolean = false, val endCursor: String? = null)

/** A paged connection (`pageInfo`, `nodes`, a product list's filters) as a [Page]. */
internal class PageSerializer<T>(item: KSerializer<T>) : KSerializer<Page<T>> {
    private val connection = Connection.serializer(item)
    override val descriptor = connection.descriptor

    override fun deserialize(decoder: Decoder): Page<T> = decoder.decodeSerializableValue(connection).let {
        Page(it.nodes, it.pageInfo?.endCursor, it.pageInfo?.hasNextPage == true, it.filters + it.productFilters)
    }

    override fun serialize(encoder: Encoder, value: Page<T>) =
        encoder.encodeSerializableValue(connection, Connection(value.items, PageInfo(value.hasNextPage, value.endCursor), value.filters))
}

/** A connection read without paging (`{ nodes }`) as its list. */
internal class NodesSerializer<T>(item: KSerializer<T>) : KSerializer<List<T>> {
    private val connection = Connection.serializer(item)
    override val descriptor = connection.descriptor

    override fun deserialize(decoder: Decoder): List<T> = decoder.decodeSerializableValue(connection).nodes

    override fun serialize(encoder: Encoder, value: List<T>) = encoder.encodeSerializableValue(connection, Connection(value))
}

/** A JSON scalar kept as JSON text (a filter value's `input`, which Shopify sends as a string holding JSON). */
internal object JsonTextSerializer : KSerializer<String> {
    override val descriptor = PrimitiveSerialDescriptor("app.storefront.data.JsonText", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val value = (decoder as JsonDecoder).decodeJsonElement()
        return (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: value.toString()
    }

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}
