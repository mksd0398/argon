package app.storefront.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WishlistStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private fun store() = WishlistStore(PreferenceDataStoreFactory.create(scope = scope) { File(tmp.root, "wishlist.preferences_pb") }, scope)

    // `ids` follows the DataStore asynchronously: wait for it to reach the expected list.
    private fun WishlistStore.assertIds(vararg expected: String) {
        runBlocking { withTimeoutOrNull(5_000) { ids.first { it == expected.toList() } } }
        assertEquals(expected.toList(), ids.value)
    }

    @Test
    fun toggleAddsThenRemoves() = runBlocking {
        val s = store()
        s.assertIds()
        s.toggle("a")
        s.assertIds("a")
        assertTrue(s.contains("a"))
        s.toggle("a")
        s.assertIds()
        assertFalse(s.contains("a"))
    }

    @Test
    fun newestFirstAndReAddingMovesToFront() = runBlocking {
        val s = store()
        s.toggle("a")
        s.toggle("b")
        s.assertIds("b", "a")
        s.toggle("a") // removed
        s.assertIds("b")
        s.toggle("a") // added again: now the newest
        s.assertIds("a", "b")
    }

    @Test
    fun survivesARestart() = runBlocking {
        val file = File(tmp.root, "wishlist.preferences_pb")
        val first = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        WishlistStore(PreferenceDataStoreFactory.create(scope = first) { file }, first).toggle("a")
        first.coroutineContext[Job]!!.cancelAndJoin() // the process ends: its DataStore is closed
        store().assertIds("a")
    }
}
