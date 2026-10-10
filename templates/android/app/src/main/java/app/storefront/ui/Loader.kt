package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException

/** Holds the one result of a screen's [Loader] for as long as its back stack entry lives. */
internal class Loaded : ViewModel() {
    var value: Any? = null
}

/**
 * Shows [content] with the result of [load]: a spinner meanwhile, the error message with Retry on failure.
 * A failed load also runs again by itself when the screen comes back to the foreground (see [RetryOnResume]).
 * One per screen: the result is kept for the back stack entry, so coming back from a product doesn't reload.
 * With [keep] false nothing is kept: the screen loads again each time it is shown (the customer's own data).
 * ponytail: no refresh until the app restarts; add pull-to-refresh if merchants need live edits.
 */
@Suppress("UNCHECKED_CAST")
@Composable
fun <T : Any> Loader(load: suspend () -> T, keep: Boolean = true, content: @Composable (T) -> Unit) {
    val cache = viewModel<Loaded>()
    var attempt by remember { mutableIntStateOf(0) }
    var value by remember(attempt) { mutableStateOf(if (keep) cache.value as T? else null) }
    var error by remember(attempt) { mutableStateOf<String?>(null) }
    LaunchedEffect(attempt) {
        if (value == null) {
            try {
                value = load().also { if (keep) cache.value = it }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: e.toString()
            }
        }
    }
    val loaded = value
    val failure = error
    when {
        loaded != null -> content(loaded)
        failure != null -> {
            RetryOnResume { attempt++ }
            ErrorView(failure) { attempt++ }
        }
        else -> Spinner()
    }
}

/**
 * Runs [retry] when the screen returns to the foreground, so a load that failed offline or behind the lock screen
 * (Android cuts the network while the device dozes) recovers without a tap.
 */
@Composable
private fun RetryOnResume(retry: () -> Unit) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        // A new observer is replayed the events up to the current state: that ON_RESUME is not a return
        var replayed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (replayed) replayed = false else retry()
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
}

@Composable
fun Spinner() = Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

@Composable
fun ErrorView(message: String, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, textAlign = TextAlign.Center)
        Button(onClick = onRetry) { Text("Retry") }
    }
}
