package app.storefront.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonModal
import app.argon.ui.components.ArgonModalAction
import app.argon.ui.components.ArgonSwitch
import app.storefront.AppGraph
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Push notifications' screens (only in an app built with PUSH): the Account switch and the one offer after a first
// purchase. Never asked at first launch.

/** Turns notifications on: the OS permission first (Android 13+), then the topics ([app.storefront.data.PushStore.enable]). */
@Composable
private fun rememberTurnOn(): () -> Unit {
    val context = LocalContext.current
    val subscribe = {
        AppGraph.scope.launch {
            try {
                AppGraph.push?.enable()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                AppGraph.toast.show("Couldn't turn on notifications. Try again later.")
            }
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) subscribe() else AppGraph.toast.show("Notifications are off for this app in your phone's settings.")
    }
    return {
        val asked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (asked) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else subscribe()
    }
}

/** The Account row "Notifications": a switch for the push opt-in. Nothing in an app without push. */
@Composable
fun NotificationsSwitch(modifier: Modifier = Modifier) {
    val push = AppGraph.push ?: return
    val on by push.optedIn.collectAsState()
    val turnOn = rememberTurnOn()
    Column(modifier) {
        SectionHeader("Notifications")
        val turnOff = {
            AppGraph.scope.launch {
                try {
                    push.disable()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    AppGraph.toast.show("Couldn't turn off notifications. Try again later.")
                }
            }
        }
        ArgonSwitch(on, { if (it) turnOn() else turnOff() }, label = "Offers and news")
        Text("New arrivals, offers and news from the store.", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    }
}

/** The offer to turn notifications on, once, after a first purchase ([app.storefront.data.PushStore.purchased]). */
@Composable
fun PushOffer() {
    val push = AppGraph.push ?: return
    val offering by push.offering.collectAsState()
    val turnOn = rememberTurnOn()
    val asked = { AppGraph.scope.launch { push.markAsked() } }
    ArgonModal(
        isPresented = offering,
        title = "Hear from us first",
        message = "Turn on notifications for new arrivals and offers. You can turn them off any time in Account.",
        primaryAction = ArgonModalAction("Turn on") { turnOn() },
        onDismiss = { asked() },
        secondaryAction = ArgonModalAction("Not now"),
    )
}
