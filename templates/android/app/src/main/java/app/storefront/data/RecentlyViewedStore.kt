package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * The ids of the products the shopper last opened, newest first, at most [LIMIT], kept on the device like the wishlist.
 * [ids] follows the DataStore (empty until the file is read).
 */
class RecentlyViewedStore(private val dataStore: DataStore<Preferences>, scope: CoroutineScope) {
    private val key = stringPreferencesKey("ids")

    val ids: StateFlow<List<String>> =
        dataStore.safeData().map { decodeIds(it[key]) }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    /** Puts [productId] at the front (moving it there when it is already listed); the oldest falls off past [LIMIT]. */
    suspend fun add(productId: String) {
        dataStore.edit { prefs -> prefs[key] = encodeIds((listOf(productId) + (decodeIds(prefs[key]) - productId)).take(LIMIT)) }
    }

    companion object {
        const val LIMIT = 12
    }
}
