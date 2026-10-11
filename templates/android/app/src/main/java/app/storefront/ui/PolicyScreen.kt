package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph

/**
 * One of the shop's policies (`policy/{handle}`: privacy-policy, terms-of-service, refund-policy, shipping-policy, ...),
 * its body rendered as a product description is.
 */
@Composable
fun PolicyScreen(handle: String, nav: NavController) {
    // the top bar's title, once the policy is here
    var title by remember { mutableStateOf("") }
    Scaffold(topBar = { ArgonTopBar(title, leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ AppGraph.storefront.policies().policy(handle) ?: error("This policy isn't available") }) { policy ->
                LaunchedEffect(policy) { title = policy.title }
                HtmlText(policy.body, Modifier.verticalScroll(rememberScrollState()).padding(ArgonTheme.spacing.l))
            }
        }
    }
}
