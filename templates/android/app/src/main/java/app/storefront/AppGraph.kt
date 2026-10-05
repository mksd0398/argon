package app.storefront

import android.app.Application
import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStoreFile
import app.storefront.data.Brand
import app.storefront.data.CartStore
import app.storefront.data.Storefront
import app.storefront.data.StorefrontException
import app.storefront.data.WishlistStore
import app.storefront.data.obj
import app.storefront.data.parseBrand
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.shopify.checkoutsheetkit.Preloading
import com.shopify.checkoutsheetkit.ShopifyCheckoutSheetKit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient

/** Runs before any activity (in a fresh process too), so [AppGraph] is ready everywhere. */
class StorefrontApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        AppGraph.assets = assets
        AppGraph.wishlist = WishlistStore(prefs("wishlist"), AppGraph.scope)
        AppGraph.cart = CartStore({ name, variables -> AppGraph.storefront.query(name, variables) }, prefs("cart"))
        ShopifyCheckoutSheetKit.configure { it.preloading = Preloading(enabled = true) }
        // A preloaded checkout shows the cart as it was, so every change to the cart (a PDP add, a stepper tap) makes it stale.
        MainScope().launch { AppGraph.cart.cart.collect { ShopifyCheckoutSheetKit.invalidate() } }
        // the Cart tab's badge needs the stored cart before that tab is ever opened
        AppGraph.scope.launch {
            try {
                AppGraph.cart.load()
            } catch (e: Exception) {
                Log.w("AppGraph", "cart load failed", e)
            }
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

    internal lateinit var assets: AssetManager

    /** The one HTTP client; the Customer Account client reuses it. */
    val http = OkHttpClient()

    /** Outlives every screen: a tap that starts a write (wishlist, cart) finishes even if the screen goes away. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    internal lateinit var wishlist: WishlistStore
    internal lateinit var cart: CartStore

    val storefront: Storefront by lazy {
        Storefront(
            domain = shopDomain,
            token = storefrontToken,
            apiVersion = apiVersion,
            loadDocument = { name -> assets.open("queries/$name.graphql").bufferedReader().use { it.readText() } },
            http = http,
        )
    }

    private val brandState = MutableStateFlow<Brand?>(null)
    private val brandLock = Mutex()

    /** The loaded brand (null until [loadBrand] succeeds); the theme follows it. */
    val brand: StateFlow<Brand?> = brandState

    /** Shop name, logo, accent and link hosts. Fetched once; a failed fetch is retried by the next caller. */
    suspend fun loadBrand(): Brand = brandLock.withLock {
        brandState.value ?: parseBrand(
            storefront.query("Shop").obj("shop") ?: throw StorefrontException(listOf("Shop not found"), null),
            shopDomain,
        ).also { brandState.value = it }
    }
}
