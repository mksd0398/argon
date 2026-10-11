package app.argon.ui.components

import android.view.View
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/** A dialog button; destructive ones are drawn in the sale (error) colour. */
data class ArgonModalAction(val title: String, val isDestructive: Boolean = false, val action: () -> Unit = {})

/** A native [AlertDialog]. Either button closes it ([onDismiss]) and then runs its action. */
@Composable
fun ArgonModal(
    isPresented: Boolean,
    title: String,
    message: String,
    primaryAction: ArgonModalAction,
    onDismiss: () -> Unit,
    secondaryAction: ArgonModalAction? = null,
) {
    if (!isPresented) return
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { ModalButton(primaryAction, onDismiss) },
        dismissButton = secondaryAction?.let { { ModalButton(it, onDismiss) } },
        title = { Text(title) },
        text = { Text(message) },
    )
}

@Composable
private fun ModalButton(action: ArgonModalAction, onDismiss: () -> Unit) = TextButton(onClick = { onDismiss(); action.action() }) {
    Text(action.title, color = if (action.isDestructive) MaterialTheme.colorScheme.error else Color.Unspecified)
}

/** [content] over the whole screen under a top bar with [title] and a close button; close and Back call [onDismiss]. */
@Composable
fun ArgonFullScreenModal(isPresented: Boolean, onDismiss: () -> Unit, title: String, content: @Composable () -> Unit) {
    if (!isPresented) return
    Dialog(onDismiss, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        // The dialog has a window of its own, which the activity's system-bar setting doesn't reach: on a light
        // background the status and navigation bars get dark icons (white ones would be unreadable).
        val view = LocalView.current
        val light = MaterialTheme.colorScheme.background.luminance() > 0.5f
        SideEffect {
            // the flags every API level from 26 understands (the module has no androidx.core for WindowCompat)
            @Suppress("DEPRECATION")
            (view.parent as? DialogWindowProvider)?.window?.decorView?.let { decor ->
                val lightBars = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                decor.systemUiVisibility = if (light) decor.systemUiVisibility or lightBars else decor.systemUiVisibility and lightBars.inv()
            }
        }
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                ArgonTopBar(title, leading = listOf(ArgonTopBarAction(ArgonIconName.Close, "Close", action = onDismiss)))
                Box(Modifier.weight(1f).navigationBarsPadding()) { content() }
            }
        }
    }
}

/** Sheet heights: [Medium] is about half the screen, [Large] full height. */
enum class ArgonSheetDetent { Medium, Large }

/**
 * A native [ModalBottomSheet]. With [ArgonSheetDetent.Medium] in [detents] it opens half way; Large alone opens full height.
 * ponytail: M3 can't cap a sheet at Medium, so a Medium-only sheet still drags to full height; cap content height if needed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArgonBottomSheet(
    isPresented: Boolean,
    onDismiss: () -> Unit,
    detents: Set<ArgonSheetDetent> = setOf(ArgonSheetDetent.Medium, ArgonSheetDetent.Large),
    content: @Composable ColumnScope.() -> Unit,
) {
    if (!isPresented) return
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = ArgonSheetDetent.Medium !in detents)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, content = content)
}
