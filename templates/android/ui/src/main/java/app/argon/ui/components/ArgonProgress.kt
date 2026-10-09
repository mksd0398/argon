package app.argon.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize

/** A native [LinearProgressIndicator]: [value] 0…1 fills it, null runs it indeterminate. */
@Composable
fun ArgonProgressBar(value: Float? = null, modifier: Modifier = Modifier) =
    if (value == null) LinearProgressIndicator(modifier.fillMaxWidth())
    else LinearProgressIndicator({ value.coerceIn(0f, 1f) }, modifier.fillMaxWidth())

/** A native [CircularProgressIndicator], 16/24/40 dp by [size]. */
@Composable
fun ArgonSpinner(size: ArgonSize = ArgonSize.M, modifier: Modifier = Modifier) {
    val (side, stroke) = when (size) {
        ArgonSize.S -> 16.dp to 2.dp
        ArgonSize.M -> 24.dp to 3.dp
        ArgonSize.L -> 40.dp to 4.dp
    }
    CircularProgressIndicator(modifier.size(side), strokeWidth = stroke)
}
