package app.storefront

import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.res.AssetManager
import android.provider.Settings
import android.util.Log
import androidx.compose.ui.text.font.FontFamily
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStoreFile
import app.storefront.auth.AuthStore
import app.storefront.auth.KwikPassStore
import app.storefront.auth.TokenCrypto
import app.storefront.data.Analytics
import app.storefront.data.AnalyticsConsentStore
import app.storefront.data.CrashReports
import app.storefront.data.CrashSink
import app.storefront.data.crashBackend
import app.storefront.data.Announcement
import app.storefront.data.Appearance
import app.storefront.data.Brand
import app.storefront.data.BuyerStore
import app.storefront.data.CartBuyerIdentityInput
import app.storefront.data.CartStore
import app.storefront.data.CollectionTemplate
import app.storefront.data.CustomerAccountApi
import app.storefront.data.DeliveryStore
import app.storefront.data.deliveryEndpoint
import app.storefront.data.FontCache
import app.storefront.data.GoKwikConfig
import app.storefront.data.HomeTemplate
import app.storefront.data.JudgeMe
import app.storefront.data.LogSink
import app.storefront.data.Navigation
import app.storefront.data.OnboardingStore
import app.storefront.data.PushStore
import app.storefront.data.RecentlyViewedStore
import app.storefront.data.RemoteSettings
import app.storefront.data.RemoteSettingsStore
import app.storefront.data.Storefront
import app.storefront.data.StorefrontApi
import app.storefront.data.ThemeLook
import app.storefront.data.WishlistStore
import app.storefront.data.firebaseSink
import app.storefront.data.metaSink
import app.storefront.data.moEngageSink
import app.storefront.data.pushTopic
import app.storefront.data.sampleTransport
import app.storefront.data.toBrand
import app.storefront.ui.TabState
import app.storefront.ui.ToastState
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.shopify.checkoutsheetkit.ColorScheme
import com.shopify.checkoutsheetkit.Preloading
import com.shopify.checkoutsheetkit.ShopifyCheckoutSheetKit
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

/** Runs before any activity (in a fresh process too), so [AppGraph] is ready everywhere. */
class StorefrontApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        // Crash reports first, so a crash anywhere below is reported with what the app is (src/firebase, else none)
        CrashReports.backend = crashBackend()
        CrashReports.setKey("shop", BuildConfig.SHOP_DOMAIN)
        CrashReports.setKey("app_version", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        CrashReports.setKey("argon", BuildConfig.ARGON_REVISION)
        // First: the per-store values read the cached settings. The fetch only refreshes that cache, for the next launch.
        // Before the first fetch: the settings the app was built with (assets/built-in/settings.json, the store's or a theme's)
        val builtIn = runCatching { assets.open("built-in/settings.json").bufferedReader().use { it.readText() } }.getOrNull()
        AppGraph.settingsStore = RemoteSettingsStore(filesDir, AppGraph.settingsUrl, AppGraph.http, builtIn)
        // The merchant's fonts when an earlier launch downloaded them; the files the newest settings name are fetched for the next.
        val fonts = FontCache(File(filesDir, "fonts"), AppGraph.http)
        AppGraph.headingFont = fonts.family(AppGraph.settings?.fonts?.heading)
        AppGraph.bodyFont = fonts.family(AppGraph.settings?.fonts?.body)
        AppGraph.scope.launch { fonts.download((AppGraph.settingsStore.refresh() ?: AppGraph.settings)?.fonts) }
        AppGraph.assets = assets
        AppGraph.analyticsConsent = AnalyticsConsentStore(prefs("analytics"), AppGraph.scope)
        // Every sink the app has. A provider's factory starts its SDK and returns its sink; in an app without the
        // provider it is a stub that returns null (app/build.gradle.kts picks which of the two is compiled in).
        AppGraph.analytics = Analytics(
            listOfNotNull(
                if (BuildConfig.DEBUG) LogSink() else null,
                // the breadcrumbs of a crash report
                if (CrashReports.backend != null) CrashSink() else null,
                firebaseSink(this),
                metaSink(this),
                moEngageSink(this),
            ),
            allowed = { AppGraph.analyticsConsent.allowed.value },
        )
        // A provider's SDK collects on its own too, so each is switched with the choice: started off (the manifest), and
        // told the choice once it is read and each time it changes.
        AppGraph.scope.launch { AppGraph.analytics.follow(AppGraph.analyticsConsent.choice) }
        AppGraph.wishlist = WishlistStore(prefs("wishlist"), AppGraph.scope, track = AppGraph.analytics::track)
        AppGraph.recentlyViewed = RecentlyViewedStore(prefs("recent"), AppGraph.scope)
        AppGraph.onboardingStore = OnboardingStore(prefs("onboarding"), AppGraph.scope)
        AppGraph.delivery = DeliveryStore(prefs("delivery"), AppGraph.scope, AppGraph.deliveryUrl, AppGraph.http)
        AppGraph.auth = AuthStore(
            domain = AppGraph.shopDomain,
            clientId = AppGraph.customerClientId,
            shopId = AppGraph.shopId,
            callbackUri = "shop.${AppGraph.shopId}.app://callback", // the scheme is the manifest's authScheme
            redirectUri = AppGraph.customerRedirectUri,
            http = AppGraph.http,
            prefs = prefs("auth"),
            encrypt = TokenCrypto::encrypt,
            decrypt = TokenCrypto::decrypt,
            loadDocument = AppGraph::document,
        )
        // KwikPass (LOGIN=kwikpass): GoKwik's phone sign-in in place of the Customer Account one; none otherwise
        if (AppGraph.goKwik.kwikPass) {
            AppGraph.kwikPass = KwikPassStore(
                AppGraph.goKwik,
                AppGraph.http,
                prefs("kwikpass"),
                encrypt = TokenCrypto::encrypt,
                decrypt = TokenCrypto::decrypt,
                appVersion = BuildConfig.VERSION_NAME,
                deviceId = { Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID).orEmpty() },
            )
        }
        AppGraph.cart = CartStore(
            AppGraph.storefront,
            prefs("cart"),
            accessToken = { AppGraph.auth.validAccessToken() },
            track = AppGraph.analytics::track,
            cartAttributes = AppGraph.analytics::cartAttributes,
            // a KwikPass shopper has no customer token: their email and phone fill in Shopify's checkout instead
            contact = { AppGraph.kwikPass?.user?.value?.let { CartBuyerIdentityInput(email = it.email, phone = it.e164) } },
        )
        AppGraph.buyer = BuyerStore(
            AppGraph.storefront,
            AppGraph.cart,
            prefs("buyer"),
            accessToken = { AppGraph.auth.validAccessToken() },
            companies = { AppGraph.customerAccount.companies() },
            sample = { AppGraph.sampleAccount.value },
        )
        // Push (PUSH, with Firebase): the opt-in, its topics and its reports to DEVICES_URL; none in an app without push
        val topic = pushTopic()
        if (AppGraph.pushEnabled && topic != null) {
            AppGraph.push = PushStore(prefs("push"), AppGraph.scope, topic) { PushStore.post(AppGraph.http, AppGraph.devicesUrl, it) }
        }
        // Web = the store's own checkout branding (Checkout Kit's default is a generic light/dark theme)
        ShopifyCheckoutSheetKit.configure {
            it.colorScheme = ColorScheme.Web()
            it.preloading = Preloading(enabled = true)
        }
        // A preloaded checkout shows the cart and the buyer as they were: a cart change (a PDP add, a stepper tap), a sign-in
        // or a sign-out makes it stale.
        MainScope().launch {
            merge(AppGraph.cart.cart, AppGraph.auth.signedIn, AppGraph.kwikPass?.user ?: emptyFlow()).collect { ShopifyCheckoutSheetKit.invalidate() }
        }
        // the stored KwikPass session, checked with GoKwik (one it refuses signs out)
        AppGraph.kwikPass?.let { kwikPass ->
            AppGraph.scope.launch {
                try {
                    kwikPass.load()
                } catch (e: Exception) {
                    Log.w("AppGraph", "KwikPass session load failed", e)
                }
            }
        }
        // the Cart tab's badge needs the stored cart before that tab is ever opened
        AppGraph.scope.launch {
            try {
                AppGraph.cart.load()
            } catch (e: Exception) {
                Log.w("AppGraph", "cart load failed", e)
            }
        }
        AppGraph.scope.launch {
            // the stored session, so the Account tab opens signed in
            try {
                AppGraph.auth.load()
            } catch (e: Exception) {
                Log.w("AppGraph", "session load failed", e)
            }
            // The B2B buyer follows the session: looked up now (when there is a session), after sign-in and each time the
            // token changes (the Storefront API and the cart hold the token itself), dropped on sign-out. The sample
            // account shows its company the same way. Latest wins: asking for the token may refresh it, which starts
            // this over with the new one.
            combine(AppGraph.auth.tokenChanges, AppGraph.sampleAccount) { _, _ -> }.collectLatest { AppGraph.refreshBuyer() }
        }
    }

    // Coil downloads images through the app's one OkHttpClient.
    override fun newImageLoader(context: PlatformContext) =
        ImageLoader.Builder(context).components { add(OkHttpNetworkFetcherFactory(callFactory = { AppGraph.http })) }.build()
}

/** One preferences file per store; a corrupt file is replaced by an empty one instead of crashing the app. */
internal fun Context.prefs(name: String) = PreferenceDataStoreFactory.create(
    corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
    scope = AppGraph.scope,
) { preferencesDataStoreFile(name) }

/** The app's single owner of shared objects (no DI framework). Per-store values come from shopify.properties. */
object AppGraph {
    val shopDomain: String = BuildConfig.SHOP_DOMAIN
    val storefrontToken: String = BuildConfig.STOREFRONT_TOKEN
    val customerClientId: String = BuildConfig.CUSTOMER_CLIENT_ID
    val shopId: String = BuildConfig.SHOP_ID
    val apiVersion: String = BuildConfig.API_VERSION
    val pdpMetafields: String = BuildConfig.PDP_METAFIELDS

    /** Where the merchant's settings are read (`SETTINGS_URL`); empty: the app runs on shopify.properties alone. */
    val settingsUrl: String = BuildConfig.SETTINGS_URL

    /**
     * The https page Shopify sends the browser back to after sign-in (`CUSTOMER_REDIRECT_URI`), which passes it on to the
     * app's own callback; empty: Shopify comes straight back to the app (see [AuthStore]).
     */
    val customerRedirectUri: String = BuildConfig.CUSTOMER_REDIRECT_URI

    /** Made first thing in [StorefrontApp.onCreate]: the values below read [settings]. */
    internal lateinit var settingsStore: RemoteSettingsStore

    /** The merchant's settings this launch runs with (cached by an earlier launch); null: shopify.properties alone. */
    val settings: RemoteSettings? get() = settingsStore.current

    /** The home screen's layout (the settings', else `HOME_TEMPLATE`); fashion when unset or unknown. */
    val homeTemplate: HomeTemplate by lazy { settings?.homeTemplate ?: HomeTemplate.of(BuildConfig.HOME_TEMPLATE) }

    /** Where product lists keep sort and filter (the settings', else `COLLECTION_TEMPLATE`); top when unset or unknown. */
    val collectionTemplate: CollectionTemplate by lazy { settings?.collectionTemplate ?: CollectionTemplate.of(BuildConfig.COLLECTION_TEMPLATE) }

    /**
     * The store's Judge.me public token (the settings', else `JUDGEME_PUBLIC_TOKEN`); empty: reviews without their star
     * breakdown ([judgeMe]).
     */
    val judgeMeToken: String by lazy { settings?.judgeMeToken ?: BuildConfig.JUDGEME_PUBLIC_TOKEN }

    /**
     * Whether product cards and the product page show the vendor (the settings', else `SHOW_VENDOR`, false unless it is
     * `true`): many stores' vendor is their own name on every product, or an internal label.
     */
    val showVendor: Boolean by lazy { settings?.showVendor ?: BuildConfig.SHOW_VENDOR.trim().equals("true", ignoreCase = true) }

    /** Whether a first launch starts with the welcome pages (the settings', else `ONBOARDING`, true unless it is `false`). */
    val onboarding: Boolean by lazy { settings?.onboarding ?: !BuildConfig.ONBOARDING.trim().equals("false", ignoreCase = true) }

    /**
     * The order value from which the store ships for free, in the shop's currency (`FREE_SHIPPING_THRESHOLD`); null when
     * unset or not a number above zero: the cart then shows no free-shipping progress. The settings' threshold wins when
     * they have one (zero there: no progress either).
     */
    val freeShippingThreshold: Double? by lazy {
        val builtIn = BuildConfig.FREE_SHIPPING_THRESHOLD.trim().toDoubleOrNull()?.takeIf { it > 0 && it.isFinite() }
        settings.let { if (it == null) builtIn else it.freeShippingThreshold(builtIn) }
    }

    /** The tab bar, the top bar and the drawer (the settings', else the built-in five tabs and the template's bar). */
    val navigation: Navigation by lazy { settings?.navigation ?: Navigation() }

    /** The strip above the top bar on the tab roots (the settings'); null: none. */
    val announcement: Announcement? by lazy { settings?.announcement }

    /** Where delivery dates are asked for (Krypton's `/v1/delivery/{shop}`, next to [settingsUrl]); empty: none. */
    val deliveryUrl: String = deliveryEndpoint(settingsUrl)

    /** Whether product pages show the delivery date for the customer's pincode (the settings' `delivery.enabled`). */
    val deliveryEnabled: Boolean by lazy { settings?.delivery == true && deliveryUrl.isNotEmpty() }

    /** Light or dark (the settings', else the device's). */
    val appearance: Appearance by lazy { settings?.appearance ?: Appearance.System }

    /** The theme's background, text, corners and buttons (the settings', else Argon's). */
    val look: ThemeLook by lazy { settings?.look ?: ThemeLook() }

    /** The settings' `appearance.fonts` heading and body, set at launch when their files are on disk; null: Argon's own. */
    internal var headingFont: FontFamily? = null
    internal var bodyFont: FontFamily? = null

    /** Whether the app was built with push notifications (`PUSH`, which takes Firebase). */
    val pushEnabled: Boolean = PushStore.enabled(BuildConfig.PUSH)

    /** Where the push opt-in is reported (`DEVICES_URL`, Krypton's `/v1/devices/{shop}`); empty: nowhere. */
    val devicesUrl: String = BuildConfig.DEVICES_URL

    /** The push opt-in ([PushStore]); null in an app without push. */
    internal var push: PushStore? = null

    /** The `link` of a notification the shopper tapped, until the app's root has opened it. */
    val notificationLink = MutableStateFlow<String?>(null)

    /** Takes the `link` a tapped notification put in [intent] (its extras: FCM's data), once; only in an app with push. */
    internal fun takeNotificationLink(intent: Intent?) {
        if (push == null || intent == null) return
        val link = PushStore.link(mapOf("link" to intent.getStringExtra("link"))) ?: return
        intent.removeExtra("link")
        notificationLink.value = link
    }

    internal lateinit var assets: AssetManager

    /** The one HTTP client; the Customer Account client reuses it. */
    val http = OkHttpClient()

    /** Outlives every screen: a tap that starts a write (wishlist, cart) finishes even if the screen goes away. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Whether the shopper shares usage data (the Account screen's "Privacy" switch); [analytics] reports only while they do. */
    internal lateinit var analyticsConsent: AnalyticsConsentStore

    /** Where every screen and store reports what the shopper does: `analytics.track(event)`. */
    internal lateinit var analytics: Analytics

    internal lateinit var wishlist: WishlistStore
    internal lateinit var delivery: DeliveryStore
    internal lateinit var recentlyViewed: RecentlyViewedStore
    internal lateinit var onboardingStore: OnboardingStore
    internal lateinit var cart: CartStore
    internal lateinit var auth: AuthStore

    /** GoKwik's checkout and KwikPass sign-in, as the app was built (`CHECKOUT`, `LOGIN`, `GOKWIK_*`); both off by default. */
    val goKwik: GoKwikConfig = GoKwikConfig.of(BuildConfig.CHECKOUT, BuildConfig.LOGIN, BuildConfig.GOKWIK_MERCHANT_ID, BuildConfig.GOKWIK_ENVIRONMENT)

    /** The KwikPass session ([goKwik] `kwikPass`), which signs in in place of [auth]; null in an app without it. */
    internal var kwikPass: KwikPassStore? = null

    /** The company a signed-in B2B customer buys for; it puts [storefront] and [cart] in that company's context. */
    internal lateinit var buyer: BuyerStore

    /** The text of the bundled file `assets/<path>`. */
    internal fun asset(path: String): String = assets.open(path).bufferedReader().use { it.readText() }

    /** The GraphQL document `assets/queries/<name>.graphql` (written by the CLI from contract/queries). */
    fun document(name: String): String = asset("queries/$name.graphql")

    /** Every Storefront API call, typed; in the device's country and language where the shop sells in them. */
    val storefront: StorefrontApi by lazy {
        val client = Storefront(domain = shopDomain, token = storefrontToken, apiVersion = apiVersion, loadDocument = ::document, http = http)
        StorefrontApi(client::query, Locale.getDefault(), builtInScreen = { handle -> runCatching { asset("built-in/screen-$handle.json") }.getOrNull() })
    }

    private val liveAccount by lazy { CustomerAccountApi(auth::customerQuery) }
    private val sampleApi by lazy { CustomerAccountApi(sampleTransport(::asset)) }

    /**
     * Every Customer Account API call, typed, as the signed-in customer (the session's token, see [AuthStore]). While
     * [sampleAccount] is on, every call answers its bundled sample instead.
     */
    val customerAccount: CustomerAccountApi get() = if (sampleAccount.value) sampleApi else liveAccount

    /** Whether the app carries a sample account (`assets/sample/`): the demo store, which has no customer accounts. */
    val sampleAvailable: Boolean by lazy { runCatching { assets.open("sample/Customer.sample.json").close() }.isSuccess }

    /**
     * On: the account screens preview the sample account ("Preview with a sample account", offered when
     * [sampleAvailable]), nothing is saved. Sign-out turns it off.
     */
    val sampleAccount = MutableStateFlow(false)

    /** Whether there is an account to show: a signed-in customer (KwikPass's too), or the sample account. */
    val hasAccount: StateFlow<Boolean> by lazy {
        val kwikPassUser = kwikPass?.user ?: MutableStateFlow(null)
        combine(auth.signedIn, sampleAccount, kwikPassUser) { signedIn, sample, user -> signedIn || sample || user != null }
            .stateIn(scope, SharingStarted.Eagerly, auth.signedIn.value || sampleAccount.value || kwikPassUser.value != null)
    }

    /**
     * Product reviews (Judge.me). Without a [judgeMeToken] they are read the way Judge.me's own storefront widget reads
     * them, and a store that has none shows none (see [JudgeMe]). The demo store's app has bundled sample reviews
     * instead (`assets/sample/JudgeMeWidget.sample.html`, which the CLI copies for mock.shop only).
     */
    val judgeMe: JudgeMe by lazy {
        val sample = "sample/JudgeMeWidget.sample.html"
        when {
            judgeMeToken.isNotBlank() -> JudgeMe(shopDomain, judgeMeToken, http)
            runCatching { assets.open(sample).close() }.isSuccess ->
                JudgeMe(shopDomain, "", http, sample = { assets.open(sample).bufferedReader().use { it.readText() } })
            else -> JudgeMe(shopDomain, "", http)
        }
    }

    /** Sends the shopper to another tab from anywhere: `tabs.select(AppTab.Shop)`. */
    val tabs = TabState()

    /** Shows a short message over whichever screen is open: `toast.show(message)`. */
    val toast = ToastState()

    /**
     * Looks the B2B buyer up again: the company of the signed-in customer (or of the sample account), retail for anyone
     * else. Run whenever the buyer may have changed, and when the app is back in the foreground (the token may have run
     * out meanwhile: the refresh asks for a valid one).
     */
    internal suspend fun refreshBuyer() {
        if (auth.signedIn.value || sampleAccount.value) buyer.refresh() else buyer.clear()
    }

    private val brandState = MutableStateFlow<Brand?>(null)

    /** The loaded brand (null until [loadBrand] succeeds); the theme follows it. */
    val brand: StateFlow<Brand?> = brandState

    /**
     * Shop name, logo, accent (the settings' when they have one) and link hosts. The shop is fetched once; a failed fetch
     * is retried by the next caller.
     */
    suspend fun loadBrand(): Brand = brandState.value
        ?: storefront.shop().toBrand(shopDomain).let { settings?.brand(it) ?: it }.also { brandState.value = it }
}
