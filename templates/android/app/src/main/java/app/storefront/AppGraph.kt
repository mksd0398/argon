package app.storefront

import android.app.Application
import android.content.res.AssetManager
import app.storefront.data.Brand
import app.storefront.data.Storefront
import app.storefront.data.StorefrontException
import app.storefront.data.obj
import app.storefront.data.parseBrand
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient

/** Runs before any activity (in a fresh process too), so [AppGraph] is ready everywhere. */
class StorefrontApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() { super.onCreate(); AppGraph.assets = assets }

    // Coil downloads images through the app's one OkHttpClient.
    override fun newImageLoader(context: PlatformContext) =
        ImageLoader.Builder(context).components { add(OkHttpNetworkFetcherFactory(callFactory = { AppGraph.http })) }.build()
}

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
