package app.storefront.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.io.IOException
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

class OnboardingTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    // The pages

    private fun brand(shortDescription: String? = null, slogan: String? = null) =
        Brand("Maison", logo = null, cover = null, accent = null, hosts = emptySet(), shortDescription = shortDescription, slogan = slogan)

    @Test
    fun threePagesOverTheTemplatesStockBanners() {
        val pages = Onboarding.pages(brand(), HomeTemplate.Grocery)
        assertEquals(listOf("Welcome to Maison", "Find it fast", "Checkout in a few taps"), pages.map { it.heading })
        assertEquals(
            listOf("Everything from Maison, in one app.", "Search, filter and save what you love.", "Track your orders and returns from your account."),
            pages.map { it.text },
        )
        assertEquals((1..3).map { StockImages.url(HomeTemplate.Grocery, it) }, pages.map { it.image })
        assertEquals("file:///android_asset/home/home-b2b-2.jpg", Onboarding.pages(brand(), HomeTemplate.B2B)[1].image)
    }

    @Test
    fun theWelcomeIsInTheBrandsOwnWordsWhenItHasThem() {
        fun welcome(brand: Brand) = Onboarding.pages(brand, HomeTemplate.Fashion)[0].text
        assertEquals("Slow fashion, made in Lyon", welcome(brand(shortDescription = " Slow fashion, made in Lyon ", slogan = "Wear it longer")))
        assertEquals("the slogan when there is no description", "Wear it longer", welcome(brand(shortDescription = "  ", slogan = "Wear it longer")))
        assertEquals("Everything from Maison, in one app.", welcome(brand(shortDescription = "", slogan = " ")))
    }

    @Test
    fun theFixtureShopWelcomesByItsName() = runBlocking {
        // mock.shop's brand has neither a short description nor a slogan
        val brand = fixtureStorefront().shop().toBrand("mock.shop")
        val first = Onboarding.pages(brand, HomeTemplate.Fashion)[0]
        assertEquals("Welcome to Mock.shop", first.heading)
        assertEquals("Everything from Mock.shop, in one app.", first.text)
    }

    // The store

    private fun file() = File(tmp.root, "onboarding.preferences_pb")
    private fun store(on: CoroutineScope = scope) = OnboardingStore(PreferenceDataStoreFactory.create(scope = on) { file() }, on)

    /** [OnboardingStore.done] once the file has been read. */
    private fun OnboardingStore.read(): Boolean? = runBlocking { withTimeoutOrNull(5_000) { done.first { it != null } } }

    @Test
    fun aFirstLaunchHasNotSeenTheWelcomeAndFinishingItIsRemembered() = runBlocking {
        val first = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val s = store(first)
        assertEquals(false, s.read())
        s.finish()
        assertEquals(true, s.done.value)
        first.coroutineContext[Job]!!.cancelAndJoin() // the process ends: its DataStore is closed

        val again = store()
        assertEquals("not shown on the second launch", true, again.read())
        again.reset()
        assertEquals("the debug row shows it again", false, again.done.value)
    }

    @Test
    fun anAnswerGivenBeforeTheFileIsReadStands() = runBlocking {
        val s = store()
        s.finish()
        assertEquals(true, s.read())
        assertEquals(true, s.done.value)
    }

    @Test
    fun unreadableStorageShowsTheWelcomeAndStillLetsItFinish() = runBlocking {
        val s = OnboardingStore(failingStore(IOException("disk")), scope)
        assertEquals(false, s.read())
        s.finish() // the write fails; the welcome is done for this run all the same
        assertEquals(true, s.done.value)
    }

    // The onboarding screen

    private fun screen(section: String) = """{"sections":[$section]}"""

    @Test
    fun theScreensPagesInOrderAPageWithoutAPictureOverTheStockOneForItsPlace() {
        val json = screen(
            """{"id":"w","type":"onboarding","settings":{},"blocks":[
              {"id":"a","type":"page","settings":{"heading":"Fresh","text":"Daily","image":{"url":"https://cdn.shopify.com/a.jpg"},"button_label":"Go on"}},
              {"id":"b","type":"page","settings":{"video":"https://cdn.shopify.com/v.mp4"}},
              {"id":"x","type":"slide","settings":{"heading":"not a page"}},
              {"id":"c","type":"page","settings":{"video":"http://insecure.test/v.mp4"}},
              {"id":"d","type":"page"}]}""",
        )
        val pages = (Onboarding.fromScreen(json, HomeTemplate.Fashion) as Welcome.Pages).pages
        assertEquals(
            listOf(
                OnboardingPage("https://cdn.shopify.com/a.jpg", "Fresh", "Daily", button = "Go on"),
                OnboardingPage(StockImages.url(HomeTemplate.Fashion, 2), "", "", video = "https://cdn.shopify.com/v.mp4"),
                OnboardingPage(StockImages.url(HomeTemplate.Fashion, 3), "", ""),
                OnboardingPage(StockImages.url(HomeTemplate.Fashion, 1), "", ""),
            ),
            pages,
        )
    }

    @Test
    fun aScreenThatTurnsTheWelcomeOffOrHidesIt() {
        val page = """{"id":"a","type":"page","settings":{"heading":"Hi"}}"""
        assertEquals(Welcome.Off, Onboarding.fromScreen(screen("""{"id":"w","type":"onboarding","settings":{"enabled":false},"blocks":[$page]}"""), HomeTemplate.Fashion))
        assertEquals(Welcome.Off, Onboarding.fromScreen(screen("""{"id":"w","type":"onboarding","hidden":true,"blocks":[$page]}"""), HomeTemplate.Fashion))
    }

    @Test
    fun noScreenNoSectionOrNoPagesIsTheAppsOwnWelcome() {
        for (json in listOf(null, "not json", screen(""), screen("""{"id":"b","type":"banner"}"""), screen("""{"id":"w","type":"onboarding","blocks":[]}"""))) {
            assertEquals(json, null, Onboarding.fromScreen(json, HomeTemplate.Fashion))
        }
    }
}
