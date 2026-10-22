package app.storefront.ui.product

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonBottomSheet
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonSheetDetent
import app.storefront.AppGraph
import app.storefront.data.DeliveryEstimate
import app.storefront.data.DeliveryLocation
import app.storefront.data.DeliveryTone
import app.storefront.data.deliveryLines
import java.util.logging.Logger
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

private val log = Logger.getLogger("Delivery")

/**
 * The delivery block, under availability: "Deliver to 560001 · Bengaluru  Change" and, for that pincode, "Delivery by
 * Thu, 24 Oct" and COD (or that the store doesn't deliver there). A tap opens [DeliverySheet]. Only with
 * [AppGraph.deliveryEnabled]; an estimate that can't be had shows the location alone.
 */
@Composable
internal fun ProductDelivery(modifier: Modifier = Modifier) {
    val store = AppGraph.delivery
    val location by store.location.collectAsState()
    val signedIn by AppGraph.auth.signedIn.collectAsState()
    var estimate by remember { mutableStateOf<DeliveryEstimate?>(null) }
    var picking by rememberSaveable { mutableStateOf(false) }

    // No location yet: the signed-in customer's default address, else the device's location when the app already may
    // read it (never asked for here: only "Use my location" asks)
    val context = LocalContext.current
    LaunchedEffect(signedIn) {
        if (location != null) return@LaunchedEffect
        if (signedIn) {
            try {
                store.prefill(AppGraph.customerAccount.customer().defaultAddress)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log.warning("default address unread (${e.javaClass.name})")
            }
        }
        if (store.unset() && mayLocate(context)) store.fill(detectLocation(context))
    }
    LaunchedEffect(location?.pincode) {
        val pin = location
        if (pin == null) {
            estimate = null
            return@LaunchedEffect
        }
        estimate = store.estimate(pin.pincode)
        // a typed pincode learns its city from the answer
        val city = estimate?.city
        if (pin.city == null && city != null) store.set(pin.copy(city = city))
    }

    val spacing = ArgonTheme.spacing
    val colors = ArgonTheme.colors
    Column(
        modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.m),
        verticalArrangement = Arrangement.spacedBy(spacing.xs),
    ) {
        Row(
            Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = "Change delivery location") { picking = true },
            horizontalArrangement = Arrangement.spacedBy(spacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ArgonIcon(ArgonIconName.Location, size = 16.dp, tint = colors.ink)
            Text(
                location?.let { "Deliver to ${it.label}" } ?: "Check the delivery date",
                Modifier.weight(1f),
                style = ArgonTheme.type.label,
                color = colors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(if (location == null) "Enter pincode" else "Change", style = ArgonTheme.type.label, color = colors.accent)
        }
        estimate?.takeIf { it.pincode == location?.pincode }?.let { shown ->
            deliveryLines(shown).forEach { line ->
                val color = when (line.tone) {
                    DeliveryTone.Good -> colors.success
                    DeliveryTone.Muted -> colors.muted
                    DeliveryTone.Bad -> colors.sale
                }
                Row(horizontalArrangement = Arrangement.spacedBy(spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    ArgonIcon(if (line.tone == DeliveryTone.Good) ArgonIconName.Truck else ArgonIconName.Info, size = 16.dp, tint = color)
                    Text(line.text, style = ArgonTheme.type.label, color = color)
                }
            }
        }
    }

    val scope = rememberCoroutineScope()
    DeliverySheet(picking, location, onDismiss = { picking = false }) { picked ->
        picking = false
        scope.launch { store.set(picked) }
    }
}

/**
 * Where to deliver: a pincode typed in, the device's location (asked for only on a tap), or one of the signed-in
 * customer's saved addresses.
 */
@Composable
private fun DeliverySheet(isPresented: Boolean, current: DeliveryLocation?, onDismiss: () -> Unit, onPick: (DeliveryLocation) -> Unit) {
    ArgonBottomSheet(isPresented, onDismiss, detents = setOf(ArgonSheetDetent.Large)) {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        val spacing = ArgonTheme.spacing
        val colors = ArgonTheme.colors
        var pincode by rememberSaveable { mutableStateOf(current?.pincode.orEmpty()) }
        var locating by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        val signedIn by AppGraph.auth.signedIn.collectAsState()
        var saved by remember { mutableStateOf<List<Pair<String, DeliveryLocation>>>(emptyList()) }
        LaunchedEffect(signedIn) {
            if (!signedIn) return@LaunchedEffect
            saved = try {
                AppGraph.customerAccount.addresses().items.mapNotNull { address ->
                    DeliveryLocation.of(address)?.let { (address.address1 ?: address.formatted.firstOrNull() ?: it.pincode) to it }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emptyList()
            }
        }

        val detect = {
            locating = true
            error = null
            scope.launch {
                val found = detectLocation(context)
                locating = false
                if (found != null) onPick(found) else error = "Couldn't find your pincode. Enter it instead."
            }
        }
        val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            if (granted.values.any { it }) detect() else error = "Location is off for this app. Enter your pincode instead."
        }

        Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
            Text("Delivery location", style = ArgonTheme.type.headline, color = colors.ink)
            ArgonInput(
                label = "Pincode",
                text = pincode,
                onTextChange = { pincode = it.filter(Char::isDigit).take(6); error = null },
                keyboard = ArgonKeyboard.Number,
                error = error,
            )
            ArgonButton("Check", isEnabled = DeliveryLocation.isPincode(pincode), fullWidth = true) {
                onPick(DeliveryLocation(pincode, current?.city?.takeIf { current.pincode == pincode }))
            }
            ArgonButton("Use my location", style = ArgonButtonStyle.Secondary, icon = ArgonIconName.Location, isLoading = locating, fullWidth = true) {
                permission.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
            }
            if (saved.isNotEmpty()) {
                Text("Your addresses", style = ArgonTheme.type.label, color = colors.muted)
                saved.forEach { (name, location) ->
                    Row(
                        Modifier.fillMaxWidth().clickable(role = Role.Button) { onPick(location) }.padding(vertical = spacing.s),
                        horizontalArrangement = Arrangement.spacedBy(spacing.s),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        ArgonIcon(ArgonIconName.Location, size = 16.dp, tint = colors.muted)
                        Column(Modifier.weight(1f)) {
                            Text(name, style = ArgonTheme.type.body, color = colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(location.label, style = ArgonTheme.type.caption, color = colors.muted)
                        }
                    }
                }
            }
        }
    }
}

/** Whether the app may already read the device's location (approximate or precise). */
private fun mayLocate(context: Context): Boolean =
    listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
        .any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

/**
 * The device's pincode and city: one location fix (a fresh one, else the last known), turned into an address by the
 * device's geocoder. The coordinates stay on the device. Null when there is no fix, no geocoder, or no Indian pincode.
 */
@SuppressLint("MissingPermission") // asked for just before
private suspend fun detectLocation(context: Context): DeliveryLocation? = withContext(Dispatchers.IO) {
    try {
        val manager = context.getSystemService(LocationManager::class.java) ?: return@withContext null
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
        val fresh = providers.firstOrNull()?.let { provider ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) withTimeoutOrNull(10_000) { currentLocation(manager, provider) } else null
        }
        val fix = fresh ?: providers.mapNotNull { manager.getLastKnownLocation(it) }.maxByOrNull { it.time } ?: return@withContext null
        if (!Geocoder.isPresent()) return@withContext null
        @Suppress("DEPRECATION") // the listener variant is API 33+; this one runs on the IO thread
        val address = Geocoder(context).getFromLocation(fix.latitude, fix.longitude, 1)?.firstOrNull() ?: return@withContext null
        val pin = address.postalCode?.filter(Char::isDigit) ?: return@withContext null
        if (address.countryCode?.uppercase()?.let { it != "IN" } == true || !DeliveryLocation.isPincode(pin)) return@withContext null
        DeliveryLocation(pin, (address.locality ?: address.subAdminArea)?.trim()?.ifEmpty { null })
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        log.warning("location lookup failed (${e.javaClass.name})")
        null
    }
}

@SuppressLint("MissingPermission")
@androidx.annotation.RequiresApi(Build.VERSION_CODES.R)
private suspend fun currentLocation(manager: LocationManager, provider: String): Location? = suspendCancellableCoroutine { done ->
    val cancel = CancellationSignal()
    done.invokeOnCancellation { cancel.cancel() }
    manager.getCurrentLocation(provider, cancel, Runnable::run) { done.resume(it) }
}
