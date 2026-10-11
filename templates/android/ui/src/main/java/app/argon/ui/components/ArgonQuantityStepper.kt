package app.argon.ui.components

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme

/**
 * [value] moved [delta] steps (+1, -1) and kept on the quantity grid: [min], `min + step`, `min + 2 * step`, ... up to
 * [max] (null: no limit). A value off the grid lands on the grid point below where the move takes it. As iOS.
 */
fun steppedQuantity(value: Int, delta: Int, min: Int = 1, max: Int? = null, step: Int = 1): Int {
    val s = step.coerceAtLeast(1)
    // the highest grid point that max allows (never below min)
    val top = max?.let { min + (it - min).coerceAtLeast(0) / s * s }
    var next = value + delta * s
    if (next > min) next = min + (next - min) / s * s
    next = next.coerceAtLeast(min)
    return if (top != null) next.coerceAtMost(top) else next
}

/**
 * A quantity with a minus and a plus: each tap moves it one [step] between [min] and [max] ([steppedQuantity]) and
 * reports it; a button that can't move it is off. 32/40/48 dp tall by [size]. The caller owns the value. Custom on both
 * platforms.
 */
@Composable
fun ArgonQuantityStepper(
    value: Int,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    min: Int = 1,
    max: Int? = null,
    step: Int = 1,
    size: ArgonSize = ArgonSize.M,
    isEnabled: Boolean = true,
) {
    val side = when (size) {
        ArgonSize.S -> 32.dp
        ArgonSize.M -> 40.dp
        ArgonSize.L -> 48.dp
    }
    val less = steppedQuantity(value, -1, min, max, step)
    val more = steppedQuantity(value, 1, min, max, step)
    // no clip on the row: a small button's touch target reaches past its circle
    Row(
        modifier.height(side).alpha(if (isEnabled) 1f else 0.4f).border(1.dp, ArgonTheme.colors.border, ArgonTheme.radius.pill),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepButton(ArgonIconName.Minus, "Decrease quantity", side, isEnabled, less != value) { onChange(less) }
        Text(
            "$value",
            Modifier.widthIn(min = side * 0.8f).semantics { contentDescription = "Quantity $value" },
            style = ArgonTheme.type.label,
            color = ArgonTheme.colors.ink,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
        StepButton(ArgonIconName.Plus, "Increase quantity", side, isEnabled, more != value) { onChange(more) }
    }
}

/** [isOn]: a tap would move the quantity (false at the end of the range: the button is dimmed). */
@Composable
private fun StepButton(icon: ArgonIconName, label: String, side: Dp, isEnabled: Boolean, isOn: Boolean, onClick: () -> Unit) = Box(
    Modifier.size(side).clip(CircleShape).clickable(enabled = isEnabled && isOn, role = Role.Button, onClick = onClick).alpha(if (isOn) 1f else 0.3f),
    contentAlignment = Alignment.Center,
) {
    ArgonIcon(icon, size = side * 0.4f, tint = ArgonTheme.colors.ink, contentDescription = label)
}
