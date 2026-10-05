package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.preferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** A DataStore whose reads are [reads]; writes are not used. */
private fun storeReading(reads: Flow<Preferences>) = object : DataStore<Preferences> {
    override val data: Flow<Preferences> = reads
    override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences = throw UnsupportedOperationException()
}

/** A DataStore whose reads and writes fail with [error]. */
internal fun failingStore(error: Exception) = object : DataStore<Preferences> {
    override val data: Flow<Preferences> = flow { throw error }
    override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences = throw error
}

class PrefsTest {
    @Test
    fun anIoErrorReadsAsEmpty() = runBlocking {
        assertEquals(emptyPreferences(), failingStore(IOException("disk")).safeData().first())
    }

    @Test
    fun otherErrorsStillFail() {
        assertThrows(IllegalStateException::class.java) { runBlocking { failingStore(IllegalStateException("bug")).safeData().first() } }
    }

    @Test
    fun keepsFollowingAfterAnIoError() = runBlocking {
        val saved = preferencesOf(stringPreferencesKey("k") to "v")
        var reads = 0
        val store = storeReading(flow { if (reads++ == 0) throw IOException("blip") else emit(saved) })
        // empty for the failed read, then the value once the read is retried
        assertEquals(listOf(emptyPreferences(), saved), store.safeData().take(2).toList())
    }
}
