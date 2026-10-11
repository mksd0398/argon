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
 * follows it (empty for the first few milliseconds after launch, until the file is read). [track] gets a product's
 * `add_to_wishlist` once it is saved.
 */
class WishlistStore(
    private val dataStore: DataStore<Preferences>,
    scope: CoroutineScope,
    private val track: (AnalyticsEvent) -> Unit = {},
) {
    private val key = stringPreferencesKey("ids")

    val ids: StateFlow<List<String>> =
        dataStore.safeData().map { decodeIds(it[key]) }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    fun contains(id: String) = id in ids.value

    /**
     * Adds [productId] as the newest, or removes it when saved. [added] is the event to report when this adds it: the
     * store holds ids alone, so the caller, which has the product, describes it.
     */
    suspend fun toggle(productId: String, added: AnalyticsEvent.AddToWishlist? = null) {
        var isNew = false
        dataStore.edit { prefs ->
            val saved = decodeIds(prefs[key])
            isNew = productId !in saved
            prefs[key] = encodeIds(if (isNew) listOf(productId) + saved else saved - productId)
        }
        if (isNew && added != null) track(added)
    }
}
