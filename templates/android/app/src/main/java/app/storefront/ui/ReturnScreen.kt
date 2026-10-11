package app.storefront.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import app.argon.ui.components.ArgonTopBar

/** Returning or exchanging items of the order with id [orderId] (`return/{orderId}`). */
@Suppress("UNUSED_PARAMETER") // orderId: the placeholder loads nothing yet
@Composable
fun ReturnScreen(orderId: String, nav: NavController) {
    // placeholder: the route and its title, until the returns flow lands here
    Scaffold(topBar = { ArgonTopBar("Return or exchange", leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize())
    }
}
