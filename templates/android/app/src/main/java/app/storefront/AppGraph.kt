package app.storefront

import android.app.Application
import android.content.res.AssetManager
import app.storefront.data.Storefront
import okhttp3.OkHttpClient

/** Runs before any activity (in a fresh process too), so [AppGraph] is ready everywhere. */
class StorefrontApp : Application() {
    override fun onCreate() { super.onCreate(); AppGraph.assets = assets }
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
}
