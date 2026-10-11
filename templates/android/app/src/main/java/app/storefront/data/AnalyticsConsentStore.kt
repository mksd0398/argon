package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * Whether the shopper lets the app share what they do in it ("Share usage data" on the Account screen), kept on the
 * device: on until they turn it off. The DataStore is the source of truth; [allowed] follows it.
 * ponytail: one switch, on by default. A store selling in the EU needs a prompt before the first event.
 */
class AnalyticsConsentStore(private val dataStore: DataStore<Preferences>, scope: CoroutineScope) {
    private val key = booleanPreferencesKey("analytics.allowed")

    /** The choice as it is stored: nothing until the file is read, then the choice, and each change of it. */
    val choice: Flow<Boolean> = dataStore.safeData().map { it[key] ?: true }.distinctUntilChanged()

    /** False for the first few milliseconds after launch, until the file is read: nothing is reported before the choice is known. */
    val allowed: StateFlow<Boolean> = choice.stateIn(scope, SharingStarted.Eagerly, false)

    suspend fun set(allowed: Boolean) {
        dataStore.edit { it[key] = allowed }
    }
}
