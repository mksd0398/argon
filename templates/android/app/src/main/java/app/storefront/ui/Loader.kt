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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException

/** Holds the one result of a screen's [Loader] for as long as its back stack entry lives. */
internal class Loaded : ViewModel() {
    var value: Any? = null
}

/**
 * Shows [content] with the result of [load]: a spinner meanwhile, the error message with Retry on failure.
 * One per screen: the result is kept for the back stack entry, so coming back from a product doesn't reload.
 * ponytail: no refresh until the app restarts; add pull-to-refresh if merchants need live edits.
 */
@Suppress("UNCHECKED_CAST")
@Composable
fun <T : Any> Loader(load: suspend () -> T, content: @Composable (T) -> Unit) {
    val cache = viewModel<Loaded>()
    var attempt by remember { mutableIntStateOf(0) }
    var value by remember(attempt) { mutableStateOf(cache.value as T?) }
    var error by remember(attempt) { mutableStateOf<String?>(null) }
    LaunchedEffect(attempt) {
        if (value == null) {
            try {
                value = load().also { cache.value = it }
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
        failure != null -> ErrorView(failure) { attempt++ }
        else -> Spinner()
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
