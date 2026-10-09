package app.argon.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.flow.drop

// M3 date pickers speak UTC midnight millis; Argon speaks calendar dates.
private fun LocalDate.utcMillis() = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
private fun Long.utcDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

@OptIn(ExperimentalMaterial3Api::class)
private class Bounds(private val min: LocalDate?, private val max: LocalDate?) : SelectableDates {
    override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis.utcDate().let { (min == null || it >= min) && (max == null || it <= max) }
    override fun isSelectableYear(year: Int) = (min == null || year >= min.year) && (max == null || year <= max.year)
}

private fun years(min: LocalDate?, max: LocalDate?) =
    (min?.year ?: DatePickerDefaults.YearRange.first)..(max?.year ?: DatePickerDefaults.YearRange.last)

/** A native inline [DatePicker] for one date between [minDate] and [maxDate], titled [label]. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArgonDatePicker(
    selection: LocalDate?,
    onChange: (LocalDate?) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "Date",
    minDate: LocalDate? = null,
    maxDate: LocalDate? = null,
) {
    val state = rememberDatePickerState(selection?.utcMillis(), yearRange = years(minDate, maxDate), selectableDates = Bounds(minDate, maxDate))
    val latest by rememberUpdatedState(onChange)
    LaunchedEffect(selection) { state.selectedDateMillis = selection?.utcMillis() }
    LaunchedEffect(state) { snapshotFlow { state.selectedDateMillis }.drop(1).collect { latest(it?.utcDate()) } }
    // the title slot's padding is M3's own (DatePickerTitlePadding)
    DatePicker(state, modifier, title = { Text(label, Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp)) })
}

/**
 * A native [DateRangePicker] for [start]…[end] between [minDate] and [maxDate].
 * It scrolls months vertically, so inside a scrolling column give it a fixed height.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArgonDateRangePicker(
    start: LocalDate?,
    end: LocalDate?,
    onChange: (start: LocalDate?, end: LocalDate?) -> Unit,
    modifier: Modifier = Modifier,
    minDate: LocalDate? = null,
    maxDate: LocalDate? = null,
) {
    val state = rememberDateRangePickerState(
        start?.utcMillis(), end?.utcMillis(), yearRange = years(minDate, maxDate), selectableDates = Bounds(minDate, maxDate),
    )
    val latest by rememberUpdatedState(onChange)
    LaunchedEffect(start, end) {
        // setSelection rejects an end without a start or before it
        if (end == null || (start != null && !end.isBefore(start))) state.setSelection(start?.utcMillis(), end?.utcMillis())
    }
    LaunchedEffect(state) {
        snapshotFlow { state.selectedStartDateMillis to state.selectedEndDateMillis }.drop(1)
            .collect { (s, e) -> latest(s?.utcDate(), e?.utcDate()) }
    }
    DateRangePicker(state, modifier)
}
