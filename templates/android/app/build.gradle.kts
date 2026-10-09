import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Per-store config written by the Argon CLI: ASCII with \uXXXX escapes, so java.util.Properties reads it as-is.
val shopify = Properties().apply {
    val file = rootProject.file("shopify.properties")
    if (!file.exists()) throw GradleException("shopify.properties missing — generate this project with npx @mksd0398/argon")
    file.inputStream().use { load(it) }
}
fun config(key: String): String = shopify.getProperty(key, "")

// Each sink has its own escaping: a Java string literal for BuildConfig, string-resource text for resValue.
// resValue XML-escapes `&` and `<` itself (AGP 9.4), so only aapt's own escapes are added: \ ' " and a leading @ or ?.
fun javaString(v: String) = "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
fun resourceString(v: String) = v.replace("\\", "\\\\").replace("'", "\\'").replace("\"", "\\\"")
    .let { if (it.startsWith("@") || it.startsWith("?")) "\\" + it else it }

android {
    namespace = "app.storefront"
    compileSdk = 36

    defaultConfig {
        applicationId = config("BUNDLE_ID")
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        for (key in listOf(
            "SHOP_DOMAIN", "STOREFRONT_TOKEN", "CUSTOMER_CLIENT_ID", "SHOP_ID",
            "API_VERSION", "APP_NAME", "BUNDLE_ID", "PDP_METAFIELDS",
        )) buildConfigField("String", key, javaString(config(key)))
        resValue("string", "app_name", resourceString(config("APP_NAME")))
        manifestPlaceholders["authScheme"] = "shop.${config("SHOP_ID")}.app"
    }

    buildFeatures {
        compose = true
        buildConfig = true
        resValues = true
    }
}

dependencies {
    implementation(project(":ui"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    implementation(libs.activity.compose)
    implementation(libs.navigation.compose)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.browser)
    implementation(libs.checkout.sheet.kit)
    implementation(libs.datastore.preferences)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
}
