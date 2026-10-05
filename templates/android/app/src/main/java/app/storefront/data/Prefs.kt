package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch

/** What the store holds; an unreadable file (an IOException) reads as empty, so a broken disk never crashes a screen. */
internal fun DataStore<Preferences>.safeData(): Flow<Preferences> =
    data.catch { if (it is IOException) emit(emptyPreferences()) else throw it }
