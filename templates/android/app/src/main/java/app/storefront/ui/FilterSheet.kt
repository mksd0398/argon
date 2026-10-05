package app.storefront.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.storefront.data.Filter
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** `{"price":{"min":x,"max":y}}` for the min/max fields (either may be empty); null when neither is a number. */
internal fun priceFilter(min: String, max: String): String? {
    val low = min.trim().toDoubleOrNull()
    val high = max.trim().toDoubleOrNull()
    if (low == null && high == null) return null
    return buildJsonObject {
        put("price", buildJsonObject {
            low?.let { put("min", it) }
            high?.let { put("max", it) }
        })
    }.toString()
}

private fun priceObject(input: String) = runCatching { Json.parseToJsonElement(input).jsonObject["price"]?.jsonObject }.getOrNull()

/** The Sort menu and, when the response has filters (or some are applied), the Filter button with its sheet. */
@Composable
fun ListingBar(l: Listing) {
    var menu by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box {
            TextButton(onClick = { menu = true }) {
                Text("Sort: ${l.sort.label}")
                Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                for (s in l.sorts) DropdownMenuItem(text = { Text(s.label) }, onClick = { menu = false; l.reload(sort = s) })
            }
        }
        Spacer(Modifier.weight(1f))
        if (l.filters.isNotEmpty() || l.applied.isNotEmpty()) {
            TextButton(onClick = { sheet = true }) { Text(if (l.applied.isEmpty()) "Filter" else "Filter (${l.applied.size})") }
        }
    }
    if (sheet) {
        FilterSheet(l.filters, l.applied, onApply = { sheet = false; l.reload(applied = it) }, onDismiss = { sheet = false })
    }
}

/**
 * One section per [Filter]: checkboxes for a list, min/max fields for a price range. [applied] and [onApply] are the
 * selected values' `input` JSON strings (the price range as `{"price":{...}}`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterSheet(filters: List<Filter>, applied: List<String>, onApply: (List<String>) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        var picked by remember { mutableStateOf(applied.filter { priceObject(it) == null }.toSet()) }
        fun bound(key: String) = applied.firstNotNullOfOrNull { priceObject(it)?.get(key)?.jsonPrimitive?.content }.orEmpty()
        var min by remember { mutableStateOf(bound("min")) }
        var max by remember { mutableStateOf(bound("max")) }
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            for (filter in filters) {
                Text(filter.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
                if (filter.type == "PRICE_RANGE") {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        PriceField("Min", min, { min = it }, Modifier.weight(1f))
                        PriceField("Max", max, { max = it }, Modifier.weight(1f))
                    }
                } else {
                    for (v in filter.values) {
                        val on = v.input in picked
                        Row(
                            Modifier.fillMaxWidth().clickable { picked = if (on) picked - v.input else picked + v.input },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(checked = on, onCheckedChange = null)
                            Text("${v.label} (${v.count})", Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp))
                        }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = { onApply(emptyList()) }, Modifier.weight(1f)) { Text("Clear") }
            Button(onClick = { onApply(picked.toList() + listOfNotNull(priceFilter(min, max))) }, Modifier.weight(1f)) { Text("Apply") }
        }
    }
}

@Composable
private fun PriceField(label: String, value: String, onChange: (String) -> Unit, modifier: Modifier) = OutlinedTextField(
    value = value,
    onValueChange = onChange,
    label = { Text(label) },
    singleLine = true,
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
    modifier = modifier,
)
