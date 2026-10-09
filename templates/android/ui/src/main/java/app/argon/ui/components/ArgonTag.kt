package app.argon.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.material3.AssistChip
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role

/** Filter: toggles a filter. Input: a chosen value with a remove button. Info: a label. */
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
        ArgonTagStyle.Info -> AssistChip(onClick = click, label = { Text(text) }, modifier = modifier)
    }
}
