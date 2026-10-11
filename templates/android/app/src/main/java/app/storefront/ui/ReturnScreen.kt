package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.storefront.AppGraph
import app.storefront.ui.returns.ReturnFlow
import app.storefront.ui.returns.ReturnFlowView

/**
 * Returning or exchanging items of the order with id [orderId] (`return/{orderId}`): choose the items, say what to do
 * with each, review, and send the request. The steps are in `returns/`.
 */
@Composable
fun ReturnScreen(orderId: String, nav: NavController) {
    // the loaded flow, for the top bar's back arrow: a step back while there is one, else out of the screen
    var flow by remember { mutableStateOf<ReturnFlow?>(null) }
    val back = ArgonTopBarAction(ArgonIconName.Back, "Back") {
        val current = flow
        if (current != null && current.step > 0 && current.submitted == null && !current.submitting) current.step-- else nav.popBackStack()
    }
    Scaffold(topBar = { ArgonTopBar("Return or exchange", leading = listOf(back)) }) { padding ->
        // the keyboard (a note being typed) pushes the content up instead of covering it
        Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding().fillMaxSize()) {
            // kept for the screen (the default): the flow holds the shopper's choices
            Loader({ ReturnFlow(AppGraph.customerAccount.returnOptions(orderId) ?: error("Order not found")) }) { loaded ->
                LaunchedEffect(loaded) { flow = loaded }
                ReturnFlowView(loaded, orderId, onBackToOrder = { nav.popBackStack() })
            }
        }
    }
}
