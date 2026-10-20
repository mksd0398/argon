package app.storefront.data

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request

/** A merchant's font: its family name and a TTF on Google Fonts' CDN for each CSS weight (100..900). */
data class RemoteFont(val family: String, val files: Map<Int, String>) {
    companion object {
        private const val CDN = "https://fonts.gstatic.com/"

        /**
         * [json] as a font; null when the family is blank, no weight key is valid, there are more than 4 files, or any
         * file isn't on [CDN]. A key that isn't a weight is ignored.
         */
        fun decode(json: JsonObject?): RemoteFont? {
            val family = (json?.get("family") as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()
            if (family.isNullOrEmpty()) return null
            val files = (json["files"] as? JsonObject ?: return null).mapNotNull { (key, value) ->
                val weight = key.trim().toIntOrNull()?.takeIf { it in 100..900 && it % 100 == 0 } ?: return@mapNotNull null
                weight to (value as? JsonPrimitive)?.takeIf { it.isString }?.content
            }
            if (files.size !in 1..4 || files.any { it.second?.startsWith(CDN) != true }) return null
            return RemoteFont(family, files.associate { it.first to it.second!! })
        }
    }
}

/** `appearance.fonts`: [heading] replaces Argon's serif (display, title), [body] its sans (the rest); null keeps Argon's. */
data class RemoteFonts(val heading: RemoteFont? = null, val body: RemoteFont? = null) {
    companion object {
        /** Each role on its own; null when neither is valid. */
        fun decode(json: JsonObject?): RemoteFonts? =
            RemoteFonts(RemoteFont.decode(json?.get("heading") as? JsonObject), RemoteFont.decode(json?.get("body") as? JsonObject))
                .takeIf { it.heading != null || it.body != null }
    }
}

/**
 * The merchant's font files in [dir], one per URL (named by its hash). [family] only reads what is there, so a launch
 * uses a font only when an earlier one downloaded all of it: never a swap mid-session. Failures keep Argon's font.
 */
class FontCache(private val dir: File, private val http: OkHttpClient) {
    private val log = Logger.getLogger("Fonts")

    private fun file(url: String) = File(dir, MessageDigest.getInstance("SHA-256").digest(url.toByteArray()).joinToString("") { "%02x".format(it) } + ".ttf")

    /** [font] as a family when every one of its files is on disk; else null. */
    fun family(font: RemoteFont?): FontFamily? {
        val files = font?.files?.mapValues { file(it.value) } ?: return null
        if (!files.values.all { it.exists() }) return null
        return FontFamily(files.map { (weight, file) -> Font(file, FontWeight(weight)) })
    }

    /** Downloads the files of [fonts] not yet on disk, each written to a temp file and renamed into place. */
    suspend fun download(fonts: RemoteFonts?) = withContext(Dispatchers.IO) {
        val urls = listOfNotNull(fonts?.heading, fonts?.body).flatMap { it.files.values }.filterNot { file(it).exists() }
        for (url in urls) {
            try {
                dir.mkdirs()
                val bytes = http.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    if (response.code != 200) null else response.body.bytes()
                }
                if (bytes == null || !isFont(bytes)) {
                    log.warning("font fetch: not a font")
                    continue
                }
                val target = file(url)
                val temp = File(dir, target.name + ".tmp")
                temp.writeBytes(bytes)
                Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log.warning("font fetch failed (${e.javaClass.name})")
            }
        }
    }

    // a TrueType or OpenType file's first four bytes, so an error page never lands as a font
    private fun isFont(bytes: ByteArray) = bytes.size > 4 && bytes.copyOf(4).let {
        it.contentEquals(byteArrayOf(0, 1, 0, 0)) || String(it, Charsets.ISO_8859_1) in setOf("true", "OTTO")
    }
}
