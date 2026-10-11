package app.storefront

import android.app.Application
import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStoreFile
import app.storefront.auth.AuthStore
import app.storefront.auth.TokenCrypto
import app.storefront.data.Analytics
import app.storefront.data.AnalyticsConsentStore
import app.storefront.data.Brand
import app.storefront.data.BuyerStore
import app.storefront.data.CartStore
import app.storefront.data.CollectionTemplate
import app.storefront.data.CustomerAccountApi
import app.storefront.data.HomeTemplate
import app.storefront.data.JudgeMe
import app.storefront.data.LogSink
import app.storefront.data.OnboardingStore
import app.storefront.data.RecentlyViewedStore
import app.storefront.data.Storefront
import app.storefront.data.StorefrontApi
import app.storefront.data.WishlistStore
import app.storefront.data.firebaseSink
import app.storefront.data.metaSink
import app.storefront.data.moEngageSink
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
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

/** Runs before any activity (in a fresh process too), so [AppGraph] is ready everywhere. */
class StorefrontApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        AppGraph.assets = assets
        AppGraph.analyticsConsent = AnalyticsConsentStore(prefs("analytics"), AppGraph.scope)
        // Every sink the app has. A provider's factory starts its SDK and returns its sink; in an app without the
        // provider it is a stub that returns null (app/build.gradle.kts picks which of the two is compiled in).
        AppGraph.analytics = Analytics(
            listOfNotNull(
                if (BuildConfig.DEBUG) LogSink() else null,
                firebaseSink(this),
                metaSink(this),
                moEngageSink(this),
            ),
            allowed = { AppGraph.analyticsConsent.allowed.value },
        )
        AppGraph.wishlist = WishlistStore(prefs("wishlist"), AppGraph.scope, track = AppGraph.analytics::track)
        AppGraph.recentlyViewed = RecentlyViewedStore(prefs("recent"), AppGraph.scope)
        AppGraph.onboardingStore = OnboardingStore(prefs("onboarding"), AppGraph.scope)
        AppGraph.auth = AuthStore(
            domain = AppGraph.shopDomain,
            clientId = AppGraph.customerClientId,
            redirectUri = "shop.${AppGraph.shopId}.app://callback", // the scheme is the manifest's authScheme
            http = AppGraph.http,
            prefs = prefs("auth"),
            encrypt = TokenCrypto::encrypt,
            decrypt = TokenCrypto::decrypt,
            loadDocument = AppGraph::document,
        )
        AppGraph.cart = CartStore(
            AppGraph.storefront,
            prefs("cart"),
            accessToken = { AppGraph.auth.validAccessToken() },
            track = AppGraph.analytics::track,
            cartAttributes = AppGraph.analytics::cartAttributes,
        )
        AppGraph.buyer = BuyerStore(
            AppGraph.storefront,
            AppGraph.cart,
            prefs("buyer"),
            accessToken = { AppGraph.auth.validAccessToken() },
            companies = { AppGraph.customerAccount.companies() },
            sample = { AppGraph.sampleAccount.value },
        )
        // Web = the store's own checkout branding (Checkout Kit's default is a generic light/dark theme)
        ShopifyCheckoutSheetKit.configure {
            it.colorScheme = ColorScheme.Web()
            it.preloading = Preloading(enabled = true)
        }
        // A preloaded checkout shows the cart and the buyer as they were: a cart change (a PDP add, a stepper tap), a sign-in
        // or a sign-out makes it stale.
        MainScope().launch { merge(AppGraph.cart.cart, AppGraph.auth.signedIn).collect { ShopifyCheckoutSheetKit.invalidate() } }
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

    /** The home screen's layout (`HOME_TEMPLATE`); fashion when unset or unknown. */
    val homeTemplate: HomeTemplate = HomeTemplate.of(BuildConfig.HOME_TEMPLATE)

    /** Where product lists keep sort and filter (`COLLECTION_TEMPLATE`); top when unset or unknown. */
    val collectionTemplate: CollectionTemplate = CollectionTemplate.of(BuildConfig.COLLECTION_TEMPLATE)

    /** The store's Judge.me public token (`JUDGEME_PUBLIC_TOKEN`); empty: reviews without their star breakdown ([judgeMe]). */
    val judgeMeToken: String = BuildConfig.JUDGEME_PUBLIC_TOKEN

    /**
     * Whether product cards and the product page show the vendor (`SHOW_VENDOR`, false unless it is `true`): many stores'
     * vendor is their own name on every product, or an internal label.
     */
    val showVendor: Boolean = BuildConfig.SHOW_VENDOR.trim().equals("true", ignoreCase = true)

    /** Whether a first launch starts with the welcome pages (`ONBOARDING`, true unless it is `false`). */
    val onboarding: Boolean = !BuildConfig.ONBOARDING.trim().equals("false", ignoreCase = true)

    /**
     * The order value from which the store ships for free, in the shop's currency (`FREE_SHIPPING_THRESHOLD`); null when
     * unset or not a number above zero: the cart then shows no free-shipping progress.
     */
    val freeShippingThreshold: Double? = BuildConfig.FREE_SHIPPING_THRESHOLD.trim().toDoubleOrNull()?.takeIf { it > 0 && it.isFinite() }

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
    internal lateinit var recentlyViewed: RecentlyViewedStore
    internal lateinit var onboardingStore: OnboardingStore
    internal lateinit var cart: CartStore
    internal lateinit var auth: AuthStore

    /** The company a signed-in B2B customer buys for; it puts [storefront] and [cart] in that company's context. */
    internal lateinit var buyer: BuyerStore

    /** The text of the bundled file `assets/<path>`. */
    internal fun asset(path: String): String = assets.open(path).bufferedReader().use { it.readText() }

    /** The GraphQL document `assets/queries/<name>.graphql` (written by the CLI from contract/queries). */
    fun document(name: String): String = asset("queries/$name.graphql")

    /** Every Storefront API call, typed; in the device's country and language where the shop sells in them. */
    val storefront: StorefrontApi by lazy {
        val client = Storefront(domain = shopDomain, token = storefrontToken, apiVersion = apiVersion, loadDocument = ::document, http = http)
        StorefrontApi(client::query, Locale.getDefault())
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

    /** Whether there is an account to show: a signed-in customer, or the sample account. */
    val hasAccount: StateFlow<Boolean> by lazy {
        combine(auth.signedIn, sampleAccount) { signedIn, sample -> signedIn || sample }
            .stateIn(scope, SharingStarted.Eagerly, auth.signedIn.value || sampleAccount.value)
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

    /** Shop name, logo, accent and link hosts. The shop is fetched once; a failed fetch is retried by the next caller. */
    suspend fun loadBrand(): Brand = brandState.value ?: storefront.shop().toBrand(shopDomain).also { brandState.value = it }
}
