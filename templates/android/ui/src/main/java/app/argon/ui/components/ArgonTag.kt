package app.argon.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AssistChip
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import app.argon.ui.ArgonTheme

/** Filter: toggles a filter. Input: a chosen value with a remove button. Info: a label (a chip only when it has an `onClick`). */
enum class ArgonTagStyle { Filter, Input, Info }

/** A native M3 chip: [FilterChip], [InputChip] or [AssistChip] by [style]. [onRemove] adds the Input chip's ✕. */
@Composable
fun ArgonTag(
    text: String,
    modifier: Modifier = Modifier,
    style: ArgonTagStyle = ArgonTagStyle.Filter,
    isSelected: Boolean = false,
    onClick: (() -> Unit)? = null,
    onRemove: (() -> Unit)? = null,
) {
    val click = onClick ?: {}
    when (style) {
        ArgonTagStyle.Filter -> FilterChip(
            selected = isSelected,
            onClick = click,
            label = { Text(text) },
            modifier = modifier,
            leadingIcon = if (isSelected) ({ ArgonIcon(ArgonIconName.Check, size = FilterChipDefaults.IconSize) }) else null,
        )
        ArgonTagStyle.Input -> InputChip(
            selected = isSelected,
            onClick = click,
            label = { Text(text) },
            modifier = modifier,
            trailingIcon = onRemove?.let {
                {
                    ArgonIcon(
                        ArgonIconName.Close,
                        Modifier.clickable(role = Role.Button, onClick = it),
                        size = InputChipDefaults.IconSize,
                        contentDescription = "Remove $text",
                    )
                }
            },
        )
        // A label that does nothing when tapped must not look or act like a button: without [onClick] it is plain
        // text on a quiet fill (no border, no ripple, not a button to a screen reader).
        ArgonTagStyle.Info -> if (onClick != null) {
            AssistChip(onClick = onClick, label = { Text(text) }, modifier = modifier)
        } else {
            Text(
                text,
                modifier
                    .background(ArgonTheme.colors.border.copy(alpha = 0.6f), ArgonTheme.radius.s)
                    .padding(horizontal = ArgonTheme.spacing.m, vertical = ArgonTheme.spacing.xs),
                style = ArgonTheme.type.label,
                color = ArgonTheme.colors.ink,
                maxLines = 1,
            )
        }
    }
}
