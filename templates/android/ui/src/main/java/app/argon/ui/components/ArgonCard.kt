package app.argon.ui.components

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.OutlinedCard
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.argon.ui.ArgonTheme

/** Elevated: surface with a shadow. Outlined: surface with a border. Filled: the border tone, flat. */
enum class ArgonCardStyle { Elevated, Outlined, Filled }

/** A native M3 card; tappable when [onClick] is set. */
@Composable
fun ArgonCard(
    modifier: Modifier = Modifier,
    style: ArgonCardStyle = ArgonCardStyle.Elevated,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    when (style) {
        ArgonCardStyle.Elevated ->
            if (onClick != null) ElevatedCard(onClick, modifier, content = content) else ElevatedCard(modifier, content = content)
        ArgonCardStyle.Outlined ->
            if (onClick != null) OutlinedCard(onClick, modifier, content = content) else OutlinedCard(modifier, content = content)
        ArgonCardStyle.Filled -> {
            val colors = CardDefaults.cardColors(containerColor = ArgonTheme.colors.border, contentColor = ArgonTheme.colors.ink)
            if (onClick != null) Card(onClick, modifier, colors = colors, content = content) else Card(modifier, colors = colors, content = content)
        }
    }
}
