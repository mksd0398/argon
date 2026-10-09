package app.argon.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme

/** Primary: filled accent. Secondary: outlined. Tertiary: text only. Destructive: filled sale colour. */
enum class ArgonButtonStyle { Primary, Secondary, Tertiary, Destructive }

/**
 * A native M3 pill button (Button, OutlinedButton or TextButton by [style]), 44/48/56 dp tall by [size].
 * [isLoading] swaps the icon for a spinner and ignores taps.
 */
@Composable
fun ArgonButton(
    title: String,
    modifier: Modifier = Modifier,
    style: ArgonButtonStyle = ArgonButtonStyle.Primary,
    size: ArgonSize = ArgonSize.M,
    icon: ArgonIconName? = null,
    isLoading: Boolean = false,
    isEnabled: Boolean = true,
    fullWidth: Boolean = false,
    action: () -> Unit,
) {
    val height = when (size) {
        ArgonSize.S -> 44.dp
        ArgonSize.M -> 48.dp
        ArgonSize.L -> 56.dp
    }
    val m = modifier.heightIn(min = height).let { if (fullWidth) it.fillMaxWidth() else it }
    val padding = PaddingValues(horizontal = if (size == ArgonSize.S) ArgonTheme.spacing.m else ArgonTheme.spacing.xl)
    val enabled = isEnabled && !isLoading
    val iconSize = if (size == ArgonSize.L) 20.dp else 17.dp
    val label: @Composable RowScope.() -> Unit = {
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(iconSize), color = LocalContentColor.current, strokeWidth = 2.dp)
        } else if (icon != null) {
            ArgonIcon(icon, size = iconSize)
        }
        if (isLoading || icon != null) Spacer(Modifier.width(ArgonTheme.spacing.s))
        Text(title, style = ArgonTheme.type.label, maxLines = 1)
    }
    when (style) {
        ArgonButtonStyle.Primary -> Button(action, m, enabled, contentPadding = padding, content = label)
        ArgonButtonStyle.Destructive -> Button(
            action, m, enabled,
            colors = ButtonDefaults.buttonColors(MaterialTheme.colorScheme.error, MaterialTheme.colorScheme.onError),
            contentPadding = padding,
            content = label,
        )
        // secondary and tertiary are ink, like iOS, not the accent
        ArgonButtonStyle.Secondary -> OutlinedButton(
            action, m, enabled,
            colors = ButtonDefaults.outlinedButtonColors(contentColor = ArgonTheme.colors.ink),
            border = BorderStroke(1.dp, ArgonTheme.colors.ink.copy(alpha = if (enabled) 1f else 0.38f)),
            contentPadding = padding,
            content = label,
        )
        ArgonButtonStyle.Tertiary -> TextButton(
            action, m, enabled,
            colors = ButtonDefaults.textButtonColors(contentColor = ArgonTheme.colors.ink),
            contentPadding = padding,
            content = label,
        )
    }
}

/** One choice of a few: native single-choice segmented buttons. */
@Composable
fun ArgonButtonGroup(options: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) =
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, option ->
            SegmentedButton(
                selected = i == selectedIndex,
                onClick = { onSelect(i) },
                shape = SegmentedButtonDefaults.itemShape(i, options.size),
            ) { Text(option, maxLines = 1) }
        }
    }
