package app.storefront.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Whether the shopper has been through the first-launch welcome (`onboarding.done`, kept on the device): it is shown
 * once, before the tabs, and never again once finished or skipped.
 */
class OnboardingStore(private val dataStore: DataStore<Preferences>, scope: CoroutineScope) {
    private val key = booleanPreferencesKey("onboarding.done")
    private val state = MutableStateFlow<Boolean?>(null)

    /** Null until the file is read: the app then shows neither the welcome nor the tabs, for a moment. */
    val done: StateFlow<Boolean?> = state

    init {
        // an answer given meanwhile (finish, reset) stands
        scope.launch { state.compareAndSet(null, dataStore.safeData().first()[key] == true) }
    }

    /** The shopper finished or skipped the welcome. */
    suspend fun finish() = save(true)

    /** Shows the welcome again (debug builds' "Show onboarding"). */
    suspend fun reset() = save(false)

    // ponytail: a failed write (IOException) only costs seeing the welcome once more after a restart.
    private suspend fun save(done: Boolean) {
        state.value = done
        try {
            dataStore.edit { it[key] = done }
        } catch (e: IOException) {
            // see above
        }
    }
}
