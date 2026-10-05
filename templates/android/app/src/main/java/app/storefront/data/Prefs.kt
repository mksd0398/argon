package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.retryWhen

/**
 * What the store holds. An unreadable file (an IOException) reads as empty so a broken disk never crashes a screen, and the
 * read is tried again after a second: the flow keeps following the store instead of ending at the first failure.
 */
internal fun DataStore<Preferences>.safeData(): Flow<Preferences> =
    data.retryWhen { cause, _ ->
        if (cause is IOException) {
            emit(emptyPreferences())
            delay(1_000)
            true
        } else {
            false
        }
    }
