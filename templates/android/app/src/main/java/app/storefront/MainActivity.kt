package app.storefront

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storefront.data.Appearance
import app.storefront.data.ArgonTestCrash
import app.storefront.ui.AppRoot
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // the system bars' icons follow the app's light or dark (the settings' appearance), else the device's
        when (AppGraph.appearance) {
            Appearance.System -> enableEdgeToEdge()
            Appearance.Light -> enableEdgeToEdge(SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT), SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT))
            Appearance.Dark -> enableEdgeToEdge(SystemBarStyle.dark(Color.TRANSPARENT), SystemBarStyle.dark(Color.TRANSPARENT))
        }
        setContent { AppRoot() }
        // opened by tapping a notification: its link opens once the tabs are up. Only on a fresh start: an activity the
        // system brings back (after process death, from Recents) has the same intent, whose link was opened already.
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !fromHistory) AppGraph.takeNotificationLink(intent)
        // Debug builds only: `adb shell am start -n <package>/app.storefront.MainActivity --ez argon_test_crash true`
        // crashes three seconds after launch, once a screen and its events are in (the report shows them), to prove crash
        // reports reach the store's Firebase (they are sent at the next launch).
        if (BuildConfig.DEBUG && intent.getBooleanExtra("argon_test_crash", false)) {
            window.decorView.postDelayed({ throw ArgonTestCrash() }, 3_000)
        }
    }

    // a notification tapped while the app is open (the foreground one PushService shows)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        AppGraph.takeNotificationLink(intent)
    }

    // Back in the foreground (not the first start, which StorefrontApp covers): the B2B buyer's token may have run out.
    override fun onRestart() {
        super.onRestart()
        AppGraph.scope.launch { AppGraph.refreshBuyer() }
    }
}
