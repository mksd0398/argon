package app.argon.ui.components

import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import kotlin.math.abs
import kotlin.math.roundToInt

/** [value] inside [bounds], snapped to the nearest [step] counted from the lower bound, never past the upper one (iOS `ArgonRange.snap`). */
fun snapToStep(value: Float, bounds: ClosedFloatingPointRange<Float>, step: Float? = null): Float {
    var result = value.coerceIn(bounds.start, bounds.endInclusive)
    if (step != null && step > 0f) {
        result = bounds.start + ((result - bounds.start) / step).roundToInt() * step
        if (result > bounds.endInclusive) result -= step
    }
    return result
}

/** Both thumbs snapped into [bounds]; the lower one stops at the upper one, so lower ≤ upper. */
fun clampRange(lower: Float, upper: Float, bounds: ClosedFloatingPointRange<Float>, step: Float? = null): Pair<Float, Float> {
    val top = snapToStep(upper, bounds, step)
    return minOf(snapToStep(lower, bounds, step), top) to top
}

/** M3's `steps`: the stops between the two ends; 0 (continuous, snapped by [clampRange]) when [step] doesn't divide the range. */
fun sliderSteps(bounds: ClosedFloatingPointRange<Float>, step: Float?): Int {
    if (step == null || step <= 0f) return 0
    val stops = (bounds.endInclusive - bounds.start) / step
    val whole = stops.roundToInt()
    return if (abs(stops - whole) > 1e-3f) 0 else (whole - 1).coerceAtLeast(0)
}

/** Two thumbs picking [lower]…[upper] inside [bounds] (a price filter, say): native [RangeSlider], without tick marks. */
@Composable
fun ArgonRangeSlider(
    lower: Float,
    upper: Float,
    bounds: ClosedFloatingPointRange<Float>,
    onChange: (lower: Float, upper: Float) -> Unit,
    modifier: Modifier = Modifier,
    step: Float? = null,
    isEnabled: Boolean = true,
) {
    val (lo, hi) = clampRange(lower, upper, bounds, step)
    RangeSlider(
        value = lo..hi,
        onValueChange = { range -> clampRange(range.start, range.endInclusive, bounds, step).let { (l, u) -> onChange(l, u) } },
        // the thumbs rest at the screen's edges, where a sideways drag is the system's back gesture: here it is the slider's
        modifier = modifier.systemGestureExclusion(),
        enabled = isEnabled,
        valueRange = bounds,
        steps = sliderSteps(bounds, step),
        // a price range has dozens of stops: ticks would be noise
        colors = SliderDefaults.colors(
            activeTickColor = Color.Transparent,
            inactiveTickColor = Color.Transparent,
            disabledActiveTickColor = Color.Transparent,
            disabledInactiveTickColor = Color.Transparent,
        ),
    )
}
