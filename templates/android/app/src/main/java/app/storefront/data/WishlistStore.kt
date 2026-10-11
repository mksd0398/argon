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
 * Saved product ids, newest first, no duplicates, kept on the device. The DataStore is the source of truth; [ids]
 * follows it (empty for the first few milliseconds after launch, until the file is read).
 */
class WishlistStore(private val dataStore: DataStore<Preferences>, scope: CoroutineScope) {
    private val key = stringPreferencesKey("ids")

    val ids: StateFlow<List<String>> =
        dataStore.safeData().map { decodeIds(it[key]) }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    fun contains(id: String) = id in ids.value

    /** Adds [productId] as the newest, or removes it when saved. */
    suspend fun toggle(productId: String) {
        dataStore.edit { prefs ->
            val saved = decodeIds(prefs[key])
            prefs[key] = encodeIds(if (productId in saved) saved - productId else listOf(productId) + saved)
        }
    }
}
