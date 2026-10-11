package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import app.argon.ui.components.ArgonTopBar

/** The customer's orders, newest first (`orders`). */
@Composable
fun OrdersScreen(nav: NavController) {
    // placeholder: the route and its title, until the orders page lands here
    Scaffold(topBar = { ArgonTopBar("Orders", leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize())
    }
}
