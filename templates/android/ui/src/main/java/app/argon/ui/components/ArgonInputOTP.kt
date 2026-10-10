package app.argon.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme

/**
 * The code after the field's text changed from [old] to [input]: ASCII digits only, at most [length]. A paste of a
 * whole code replaces what was there. The flag is true only on the change that completes the code, so it fires once.
 */
fun otpInput(old: String, input: String, length: Int = 6): Pair<String, Boolean> {
    fun digits(s: String) = s.filter { it in '0'..'9' }
    val pasted = if (input.startsWith(old)) digits(input.substring(old.length)) else ""
    val code = (if (pasted.length >= length) pasted else digits(input)).take(length)
    return code to (code.length == length && code != digits(old).take(length))
}

/**
 * One box per digit of a [length]-digit one-time code. [onComplete] runs once when the last digit lands (typed,
 * pasted or autofilled from SMS). Custom: one hidden text field drawn as boxes.
 */
@Composable
fun ArgonInputOTP(
    code: String,
    onCodeChange: (String) -> Unit,
    onComplete: (String) -> Unit,
    modifier: Modifier = Modifier,
    length: Int = 6,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    BasicTextField(
        // the cursor stays at the end: digits are only added or removed there
        value = TextFieldValue(code, TextRange(code.length)),
        onValueChange = {
            val (next, complete) = otpInput(code, it.text, length)
            if (next != code) onCodeChange(next)
            if (complete) onComplete(next)
        },
        modifier = modifier.semantics {
            contentType = ContentType.SmsOtpCode
            contentDescription = "One-time code, $length digits"
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        singleLine = true,
        interactionSource = interaction,
        decorationBox = { field ->
            Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
                repeat(length) { i ->
                    val active = focused && i == minOf(code.length, length - 1)
                    Box(
                        Modifier.size(48.dp, 52.dp)
                            .background(ArgonTheme.colors.surface, ArgonTheme.radius.m)
                            .border(
                                if (active) 2.dp else 1.dp,
                                if (active) ArgonTheme.colors.accent else ArgonTheme.colors.border,
                                ArgonTheme.radius.m,
                            ),
                        contentAlignment = Alignment.Center,
                    ) { Text(code.getOrNull(i)?.toString().orEmpty(), style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink) }
                }
            }
            Box(Modifier.alpha(0f).size(1.dp)) { field() }
        },
    )
}
