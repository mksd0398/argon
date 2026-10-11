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
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RecentlyViewedStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private fun file() = File(tmp.root, "recent.preferences_pb")
    private fun store() = RecentlyViewedStore(PreferenceDataStoreFactory.create(scope = scope) { file() }, scope)

    // `ids` follows the DataStore asynchronously: wait for it to reach the expected list.
    private fun RecentlyViewedStore.assertIds(expected: List<String>) {
        runBlocking { withTimeoutOrNull(5_000) { ids.first { it == expected } } }
        assertEquals(expected, ids.value)
    }

    @Test
    fun theNewestIsFirstAndOpeningOneAgainMovesItToTheFront() = runBlocking {
        val s = store()
        s.assertIds(emptyList())
        s.add("a")
        s.add("b")
        s.add("c")
        s.assertIds(listOf("c", "b", "a"))
        s.add("a")
        s.assertIds(listOf("a", "c", "b"))
        s.add("a")
        s.assertIds(listOf("a", "c", "b"))
    }

    @Test
    fun onlyTheLastTwelveAreKept() = runBlocking {
        val s = store()
        for (i in 1..15) s.add("p$i")
        assertEquals(12, RecentlyViewedStore.LIMIT)
        s.assertIds((15 downTo 4).map { "p$it" })
        s.add("p4") // already listed: moved, and nothing falls off
        s.assertIds(listOf("p4") + (15 downTo 5).map { "p$it" })
    }

    @Test
    fun survivesARestart() = runBlocking {
        val first = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        RecentlyViewedStore(PreferenceDataStoreFactory.create(scope = first) { file() }, first).run { add("a"); add("b") }
        first.coroutineContext[Job]!!.cancelAndJoin() // the process ends: its DataStore is closed
        store().assertIds(listOf("b", "a"))
    }
}
