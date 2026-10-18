package app.storefront.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PushTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val file by lazy { File(tmp.root, "push.preferences_pb") }

    @After fun stop() = scope.cancel()

    private val topics = mutableListOf<Pair<String, Boolean>>()
    private val reports = mutableListOf<DeviceReport>()

    // each store its own DataStore scope: DataStore allows one active instance per file
    private fun store(fail: Boolean = false): PushStore {
        val own = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        stores += own
        val data = PreferenceDataStoreFactory.create(scope = own) { file }
        return PushStore(data, own, { name, on -> if (fail) error("FCM down"); topics += name to on }, { reports += it })
    }

    private val stores = mutableListOf<CoroutineScope>()

    // the process ends: its DataStore is closed, and the file can be opened again
    private suspend fun closeStores() {
        stores.forEach { it.coroutineContext[Job]!!.cancelAndJoin() }
        stores.clear()
    }

    @Test
    fun theInstallIdIsMadeOnceAndKept() = runBlocking {
        val push = store()
        val first = push.installId()
        assertEquals("asked again", first, push.installId())
        closeStores()
        assertEquals("a new store over the same file", first, store().installId())
        closeStores()
    }

    @Test
    fun enableSubscribesAndReportsDisableUndoes() = runBlocking {
        val push = store()
        push.enable()
        assertEquals(listOf("all" to true, "android" to true), topics)
        assertTrue(push.optedIn.value)
        val id = push.installId()
        assertEquals(listOf(DeviceReport(id, "android", true)), reports)
        push.disable()
        assertEquals(listOf("all" to false, "android" to false), topics.drop(2))
        assertFalse(push.optedIn.value)
        assertEquals(DeviceReport(id, "android", false), reports.last())
        closeStores()
    }

    @Test
    fun aTopicThatFailsLeavesItOff() = runBlocking {
        val push = store(fail = true)
        assertThrows(IllegalStateException::class.java) { runBlocking { push.enable() } }
        assertFalse(push.optedIn.value)
        assertTrue("nothing reported", reports.isEmpty())
        closeStores()
    }

    @Test
    fun theOfferComesOnceAfterAPurchase() = runBlocking {
        val push = store()
        // the file is read: never asked
        repeat(50) { if (push.askedAfterPurchase.value) Thread.sleep(20) }
        assertFalse(push.askedAfterPurchase.value)
        push.purchased()
        assertTrue(push.offering.value)
        push.markAsked()
        assertFalse(push.offering.value)
        push.purchased()
        assertFalse("not again", push.offering.value)
        closeStores()
    }

    @Test
    fun reportJson() {
        assertEquals("""{"installId":"i-1","platform":"android","optedIn":true}""", DeviceReport("i-1", "android", true).json())
    }

    @Test
    fun aNotificationsLinkResolves() {
        val link = PushStore.link(mapOf("link" to " /collections/sale ", "title" to "Sale"))
        assertEquals(Route.Collection("sale"), Links.resolve(link, setOf("shop.test")))
        assertEquals(Route.Screen("winter"), Links.resolve(PushStore.link(mapOf("link" to "app://screens/winter")), setOf("shop.test")))
        assertNull(PushStore.link(mapOf("link" to " ")))
        assertNull(PushStore.link(emptyMap()))
    }

    @Test
    fun onlyPushTrueTurnsItOn() {
        assertTrue(PushStore.enabled("true"))
        assertTrue(PushStore.enabled(" TRUE "))
        assertFalse("an older project has no PUSH", PushStore.enabled(""))
        assertFalse(PushStore.enabled("false"))
        assertFalse(PushStore.enabled("yes"))
    }
}
