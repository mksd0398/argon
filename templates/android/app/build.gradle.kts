import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
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

// The analytics providers. Each is compiled into the app only when the store set it up: its SDK, and src/<provider>/java
// (the sink that feeds it, and the sink's factory) in place of src/no<Provider>/java (the same factory, returning null).
// An app with none set up carries no analytics SDK at all.
val firebase = file("google-services.json").exists() // Firebase's own file, from its console
val meta = config("META_APP_ID").isNotBlank()
val moengage = config("MOENGAGE_WORKSPACE_ID").isNotBlank()
if (meta && config("META_CLIENT_TOKEN").isBlank()) {
    throw GradleException("META_APP_ID is set but META_CLIENT_TOKEN is empty — the Facebook SDK needs both (shopify.properties)")
}
if (moengage && config("MOENGAGE_DATA_CENTER").trim() !in listOf("", "1", "2", "3", "4", "5", "6")) {
    throw GradleException("MOENGAGE_DATA_CENTER must be 1 to 6: the N of the workspace's dashboard-0N.moengage.com (shopify.properties)")
}
// Push notifications (`--push`): through the store's Firebase project, so they need its file.
val push = config("PUSH").trim().equals("true", ignoreCase = true)
if (push && !firebase) throw GradleException("PUSH is true but app/google-services.json is missing: push goes through the store's Firebase project")
// Google's plugin turns google-services.json into the resources Firebase starts from; it fails a build without the file.
if (firebase) apply(plugin = libs.plugins.google.services.get().pluginId)

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
            "HOME_TEMPLATE", "COLLECTION_TEMPLATE", "JUDGEME_PUBLIC_TOKEN", "SHOW_VENDOR",
            "ONBOARDING", "FREE_SHIPPING_THRESHOLD", "SETTINGS_URL", "CUSTOMER_REDIRECT_URI",
            "META_APP_ID", "META_CLIENT_TOKEN", "MOENGAGE_WORKSPACE_ID", "MOENGAGE_DATA_CENTER", "SERVER_PURCHASE",
            "PUSH", "DEVICES_URL",
        )) buildConfigField("String", key, javaString(config(key)))
        resValue("string", "app_name", resourceString(config("APP_NAME")))
        manifestPlaceholders["authScheme"] = "shop.${config("SHOP_ID")}.app"
        // where the Facebook SDK reads them; empty, and read by nothing, in an app without Meta
        manifestPlaceholders["metaAppId"] = config("META_APP_ID").trim()
        manifestPlaceholders["metaClientToken"] = config("META_CLIENT_TOKEN").trim()
        // push: the FCM service and the SDK's own token, both off without PUSH
        manifestPlaceholders["push"] = push.toString()
    }

    sourceSets["main"].kotlin.srcDirs(
        "src/${if (firebase) "firebase" else "noFirebase"}/java",
        "src/${if (meta) "meta" else "noMeta"}/java",
        "src/${if (moengage) "moengage" else "noMoengage"}/java",
    )

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
    if (firebase) {
        implementation(platform(libs.firebase.bom))
        implementation(libs.firebase.analytics)
        // its push service is compiled in with Firebase (src/firebase), and runs only with PUSH (the manifest)
        implementation(libs.firebase.messaging)
    }
    if (meta) implementation(libs.facebook.core)
    if (moengage) implementation(libs.moengage)
    testImplementation(libs.junit)
}
