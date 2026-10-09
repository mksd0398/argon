// Argon UI: the app's themed component library. Plain values in, callbacks out; it never imports app code.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.argon.ui"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // api: the components' signatures use Compose and Material 3 types
    api(platform(libs.compose.bom))
    api(libs.compose.material3)
    implementation(libs.coil.compose)
    testImplementation(libs.junit)
}
