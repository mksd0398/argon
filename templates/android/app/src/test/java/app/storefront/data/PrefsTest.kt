package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** A DataStore whose reads fail with [error]. */
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
}
