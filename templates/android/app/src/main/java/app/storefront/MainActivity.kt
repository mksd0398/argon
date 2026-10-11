package app.storefront

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storefront.ui.AppRoot
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { AppRoot() }
    }

    // Back in the foreground (not the first start, which StorefrontApp covers): the B2B buyer's token may have run out.
    override fun onRestart() {
        super.onRestart()
        AppGraph.scope.launch { AppGraph.refreshBuyer() }
    }
}
