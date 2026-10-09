package app.argon.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonTheme

/** A titled section that shows [content] while [isExpanded]; tapping the title calls [onToggle]. Custom: M3 has none. */
@Composable
fun ArgonAccordion(
    title: String,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val turn by animateFloatAsState(if (isExpanded) 180f else 0f, label = "chevron")
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClick = onToggle)
                .semantics { stateDescription = if (isExpanded) "Expanded" else "Collapsed" }
                .padding(horizontal = ArgonTheme.spacing.l, vertical = ArgonTheme.spacing.m),
            horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, Modifier.weight(1f), style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
            ArgonIcon(ArgonIconName.ChevronDown, Modifier.rotate(turn), tint = ArgonTheme.colors.muted)
        }
        AnimatedVisibility(isExpanded) {
            Column(Modifier.fillMaxWidth().padding(start = ArgonTheme.spacing.l, end = ArgonTheme.spacing.l, bottom = ArgonTheme.spacing.l)) {
                content()
            }
        }
    }
}
