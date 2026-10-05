package app.storefront.auth

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import app.storefront.AppGraph
import app.storefront.MainActivity
import kotlinx.coroutines.launch

/**
 * Where the browser sends `shop.<SHOP_ID>.app://callback` after sign-in. Hands the URI to [AuthStore.handleCallback] and
 * returns to [MainActivity]. Exported, so any app can open it: AuthStore rejects a callback that isn't for the sign-in in
 * progress. Holds no state of its own, so it also works in a fresh process (StorefrontApp builds AppGraph first).
 */
class CallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.dataString?.let { uri ->
            // on the app's scope: the exchange outlives this activity, which finishes right away
            AppGraph.scope.launch {
                try {
                    AppGraph.auth.handleCallback(uri)
                } catch (e: Exception) {
                    Log.w("CallbackActivity", "sign-in callback not accepted: ${e.message}")
                }
            }
        }
        // MainActivity sits below the Custom Tab in this task: CLEAR_TOP closes the tab, SINGLE_TOP keeps MainActivity as it was.
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
