package app.storefront

import android.content.Context
import android.content.res.AssetManager
import app.storefront.data.Storefront
import okhttp3.OkHttpClient

/** The app's single owner of shared objects (no DI framework). Per-store values come from shopify.properties. */
object AppGraph {
    val shopDomain: String = BuildConfig.SHOP_DOMAIN
    val storefrontToken: String = BuildConfig.STOREFRONT_TOKEN
    val customerClientId: String = BuildConfig.CUSTOMER_CLIENT_ID
    val shopId: String = BuildConfig.SHOP_ID
    val apiVersion: String = BuildConfig.API_VERSION
    val pdpMetafields: String = BuildConfig.PDP_METAFIELDS

    private lateinit var assets: AssetManager

    /** Call from every entry activity's onCreate before touching [storefront]. */
    fun init(context: Context) {
        assets = context.applicationContext.assets
    }

    val storefront: Storefront by lazy {
        Storefront(
            domain = shopDomain,
            token = storefrontToken,
            apiVersion = apiVersion,
            loadDocument = { name -> assets.open("queries/$name.graphql").bufferedReader().use { it.readText() } },
            http = OkHttpClient(),
        )
    }
}
