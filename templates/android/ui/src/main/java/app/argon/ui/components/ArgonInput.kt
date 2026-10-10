package app.argon.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation

/** The soft keyboard a field asks for. */
enum class ArgonKeyboard { Text, Email, Number, Phone }

private fun ArgonKeyboard.type(secure: Boolean) = when (this) {
    ArgonKeyboard.Text -> if (secure) KeyboardType.Password else KeyboardType.Text
    ArgonKeyboard.Email -> KeyboardType.Email
    ArgonKeyboard.Number -> if (secure) KeyboardType.NumberPassword else KeyboardType.Number
    ArgonKeyboard.Phone -> KeyboardType.Phone
}

/** A one-line native [OutlinedTextField]. [error] replaces [helper] below the field and marks it invalid. */
@Composable
fun ArgonInput(
    label: String,
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    helper: String? = null,
    error: String? = null,
    keyboard: ArgonKeyboard = ArgonKeyboard.Text,
    isSecure: Boolean = false,
    leadingIcon: ArgonIconName? = null,
    trailingIcon: ArgonIconName? = null,
    isEnabled: Boolean = true,
) = OutlinedTextField(
    value = text,
    onValueChange = onTextChange,
    modifier = modifier.fillMaxWidth(),
    enabled = isEnabled,
    label = { Text(label) },
    placeholder = placeholder?.let { { Text(it) } },
    leadingIcon = leadingIcon?.let { { ArgonIcon(it) } },
    trailingIcon = trailingIcon?.let { { ArgonIcon(it) } },
    supportingText = (error ?: helper)?.let { { Text(it) } },
    isError = error != null,
    visualTransformation = if (isSecure) PasswordVisualTransformation() else VisualTransformation.None,
    keyboardOptions = KeyboardOptions(keyboardType = keyboard.type(isSecure)),
    singleLine = true,
)

/** A multi-line native [OutlinedTextField], at least [minLines] tall; [maxLength] cuts input and shows a counter. */
@Composable
fun ArgonTextArea(
    label: String,
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    minLines: Int = 3,
    maxLength: Int? = null,
    helper: String? = null,
    error: String? = null,
    isEnabled: Boolean = true,
) {
    val note = error ?: helper
    OutlinedTextField(
        value = text,
        onValueChange = { onTextChange(if (maxLength != null) it.take(maxLength) else it) },
        modifier = modifier.fillMaxWidth(),
        enabled = isEnabled,
        label = { Text(label) },
        placeholder = placeholder?.let { { Text(it) } },
        supportingText = if (note == null && maxLength == null) null else {
            {
                Row {
                    Text(note.orEmpty(), Modifier.weight(1f))
                    if (maxLength != null) Text("${text.length}/$maxLength")
                }
            }
        },
        isError = error != null,
        minLines = minLines,
    )
}
