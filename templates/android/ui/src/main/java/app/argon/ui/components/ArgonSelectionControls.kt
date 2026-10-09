package app.argon.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Checkbox
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme

/** A native [Checkbox]; with a [label] the whole row toggles it. */
@Composable
fun ArgonCheckbox(
    isChecked: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    isEnabled: Boolean = true,
) {
    if (label == null) return Checkbox(isChecked, onChange, modifier, isEnabled)
    LabeledRow(modifier.toggleable(isChecked, enabled = isEnabled, role = Role.Checkbox, onValueChange = onChange), label, isEnabled) {
        Checkbox(isChecked, null, enabled = isEnabled)
    }
}

/** A native [RadioButton] with its [label]; the whole row selects it. */
@Composable
fun ArgonRadioButton(
    isSelected: Boolean,
    label: String,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: Boolean = true,
) = LabeledRow(modifier.selectable(isSelected, enabled = isEnabled, role = Role.RadioButton, onClick = onSelect), label, isEnabled) {
    RadioButton(isSelected, null, enabled = isEnabled)
}

/** One of [options], stacked; none selected when [selectedIndex] is null. */
@Composable
fun ArgonRadioGroup(
    options: List<String>,
    selectedIndex: Int?,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: Boolean = true,
) = Column(modifier.selectableGroup()) {
    options.forEachIndexed { i, option -> ArgonRadioButton(i == selectedIndex, option, { onSelect(i) }, isEnabled = isEnabled) }
}

/** A native [Switch]; with a [label] (before the switch) the whole row toggles it. */
@Composable
fun ArgonSwitch(
    isOn: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    isEnabled: Boolean = true,
) {
    if (label == null) return Switch(isOn, onChange, modifier, enabled = isEnabled)
    LabeledRow(modifier.toggleable(isOn, enabled = isEnabled, role = Role.Switch, onValueChange = onChange), label, isEnabled, controlAtEnd = true) {
        Switch(isOn, null, enabled = isEnabled)
    }
}

@Composable
private fun LabeledRow(
    modifier: Modifier,
    label: String,
    isEnabled: Boolean,
    controlAtEnd: Boolean = false,
    control: @Composable () -> Unit,
) = Row(
    modifier.fillMaxWidth().heightIn(min = 48.dp),
    horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m),
    verticalAlignment = Alignment.CenterVertically,
) {
    if (!controlAtEnd) control()
    Text(
        label,
        Modifier.weight(1f),
        style = ArgonTheme.type.body,
        color = ArgonTheme.colors.ink.copy(alpha = if (isEnabled) 1f else 0.38f),
    )
    if (controlAtEnd) control()
}
