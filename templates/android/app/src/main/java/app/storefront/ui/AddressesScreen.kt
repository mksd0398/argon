package app.storefront.ui

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.navigation.NavController
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonBottomSheet
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDropdown
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonModal
import app.argon.ui.components.ArgonModalAction
import app.argon.ui.components.ArgonSheetDetent
import app.argon.ui.components.ArgonSwitch
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.CustomerAddress
import app.storefront.ui.account.AddressField
import app.storefront.ui.account.AddressForm
import app.storefront.ui.account.ErrorText
import app.storefront.ui.account.Panel
import app.storefront.ui.account.addressLines
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** A country the address form offers: its ISO [code] and [name]. */
private class CountryChoice(val code: String, val name: String)

/** The address book with the countries the shop sells to (the form's dropdown; none when they can't be loaded). */
private class AddressBook(val addresses: List<CustomerAddress>, val countries: List<CountryChoice>)

// ponytail: the first page of addresses (20). Page through `addresses(after)` when a store's customers keep more.
private suspend fun loadAddresses(): List<CustomerAddress> = AppGraph.customerAccount.addresses().items

private suspend fun loadAddressBook(): AddressBook = coroutineScope {
    val countries = async {
        try {
            AppGraph.storefront.localization().availableCountries.map { CountryChoice(it.isoCode, it.name.ifBlank { it.isoCode }) }.sortedBy { it.name }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w("Addresses", "countries not loaded (${e.javaClass.name})")
            emptyList()
        }
    }
    AddressBook(loadAddresses(), countries.await())
}

/** The customer's address book (`addresses`): each address with Edit, Delete and "Make default", and "Add address". */
@Composable
fun AddressesScreen(nav: NavController) {
    Scaffold(topBar = { ArgonTopBar("Addresses", leading = listOf(nav.backAction())) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            // not kept: the customer's own data is read again on each visit
            Loader(::loadAddressBook, keep = false) { AddressBookContent(it) }
        }
    }
}

/** The form that is open: for [original], or for a new address (null). */
private class OpenForm(val original: CustomerAddress?)

private const val FORM = "form"

@Composable
private fun AddressBookContent(book: AddressBook) {
    val spacing = ArgonTheme.spacing
    var addresses by remember { mutableStateOf(book.addresses) }
    var form by remember { mutableStateOf<OpenForm?>(null) }
    var deleting by remember { mutableStateOf<CustomerAddress?>(null) }
    // the change in flight and what went wrong, by address id (the form's under FORM)
    var busy by remember { mutableStateOf<String?>(null) }
    var errors by remember { mutableStateOf(emptyMap<String, String>()) }

    /** Runs [change] on the app's scope (leaving the screen doesn't drop it), then says [done] and reads the book again. */
    fun act(key: String, done: String, change: suspend () -> Unit) {
        busy = key
        errors = errors - key
        AppGraph.scope.launch {
            try {
                change()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errors = errors + (key to (e.message ?: e.toString()))
                return@launch
            } finally {
                busy = null
            }
            if (key == FORM) form = null
            AppGraph.toast.show(done)
            try {
                addresses = loadAddresses()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // the change went through; the list catches up on the next visit
                Log.w("Addresses", "address book not reloaded (${e.javaClass.name})")
            }
        }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        if (addresses.isEmpty()) {
            item { Text("No addresses yet", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted) }
        }
        items(addresses) { address ->
            AddressCard(
                address,
                isBusy = busy == address.id,
                error = errors[address.id],
                onEdit = { errors = errors - FORM; form = OpenForm(address) },
                onDelete = { deleting = address },
                onMakeDefault = { act(address.id, "Default address updated") { AppGraph.customerAccount.updateAddress(address.id, isDefault = true) } },
            )
        }
        item { ArgonButton("Add address", fullWidth = true) { errors = errors - FORM; form = OpenForm(null) } }
    }

    val open = form
    ArgonBottomSheet(open != null, onDismiss = { form = null }, detents = setOf(ArgonSheetDetent.Large)) {
        if (open != null) {
            AddressFormSheet(open.original, book.countries, isSaving = busy == FORM, error = errors[FORM]) { typed ->
                val original = open.original
                act(FORM, "Address saved") {
                    val api = AppGraph.customerAccount
                    if (original == null) {
                        api.createAddress(typed.toInput(), typed.isDefault)
                    } else {
                        // the default can only be given, not taken away: another address takes it over
                        api.updateAddress(original.id, typed.toInput(original), isDefault = if (typed.isDefault && !original.isDefault) true else null)
                    }
                }
            }
        }
    }

    val doomed = deleting
    ArgonModal(
        isPresented = doomed != null,
        title = "Delete address?",
        message = doomed?.let { addressLines(it).take(3).joinToString(", ") }.orEmpty(),
        primaryAction = ArgonModalAction("Delete", isDestructive = true) {
            doomed?.let { address -> act(address.id, "Address deleted") { AppGraph.customerAccount.deleteAddress(address.id) } }
        },
        onDismiss = { deleting = null },
        secondaryAction = ArgonModalAction("Cancel"),
    )
}

/** An address as Shopify formats it, "Default" on the default one, and its actions; a change that failed shows under them. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AddressCard(
    address: CustomerAddress,
    isBusy: Boolean,
    error: String?,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onMakeDefault: () -> Unit,
) = Panel {
    val spacing = ArgonTheme.spacing
    Row(horizontalArrangement = Arrangement.spacedBy(spacing.s), verticalAlignment = Alignment.Top) {
        Text(addressLines(address).joinToString("\n"), Modifier.weight(1f), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
        if (address.isDefault) ArgonTag("Default", style = ArgonTagStyle.Info)
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(spacing.s)) {
        ArgonButton("Edit", style = ArgonButtonStyle.Secondary, size = ArgonSize.S, isEnabled = !isBusy, action = onEdit)
        // Shopify refuses to delete the default address: another one has to be made the default first
        ArgonButton("Delete", style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, isEnabled = !isBusy && !address.isDefault, action = onDelete)
        if (!address.isDefault) {
            ArgonButton("Make default", style = ArgonButtonStyle.Tertiary, size = ArgonSize.S, isLoading = isBusy, action = onMakeDefault)
        }
    }
    if (address.isDefault) Text("The default address can't be deleted", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    ErrorText(error)
}

/**
 * The address form, in a sheet: for [original], or empty for a new address. What the form checks itself shows on its
 * fields once "Save address" is tapped; Shopify's own complaints ([error]) show under the form.
 */
@Composable
private fun ColumnScope.AddressFormSheet(
    original: CustomerAddress?,
    countries: List<CountryChoice>,
    isSaving: Boolean,
    error: String?,
    onSave: (AddressForm) -> Unit,
) {
    val spacing = ArgonTheme.spacing
    var typed by remember(original) { mutableStateOf(AddressForm.of(original)) }
    var checked by remember { mutableStateOf(false) }
    val problems = if (checked) typed.errors() else emptyMap()
    // the countries the shop sells to, and the address's own when it is none of them (it can still be kept)
    val choices = remember(countries, original) {
        val own = original?.countryCode?.takeIf { code -> countries.none { it.code == code } }
        countries + listOfNotNull(own?.let { CountryChoice(it, original.country ?: it) })
    }

    Column(
        // the fields scroll; the button under them stays in reach, above the keyboard
        Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = spacing.l),
        verticalArrangement = Arrangement.spacedBy(spacing.s),
    ) {
        Text(
            if (original == null) "Add address" else "Edit address",
            Modifier.semantics { heading() },
            style = ArgonTheme.type.title,
            color = ArgonTheme.colors.ink,
        )
        ArgonInput("First name", typed.firstName, { typed = typed.copy(firstName = it) })
        ArgonInput("Last name", typed.lastName, { typed = typed.copy(lastName = it) })
        ArgonInput("Company", typed.company, { typed = typed.copy(company = it) })
        ArgonInput("Address line 1", typed.address1, { typed = typed.copy(address1 = it) }, error = problems[AddressField.Address1])
        ArgonInput("Address line 2", typed.address2, { typed = typed.copy(address2 = it) })
        ArgonInput("City", typed.city, { typed = typed.copy(city = it) }, error = problems[AddressField.City])
        ArgonInput("State / province code", typed.zoneCode, { typed = typed.copy(zoneCode = it) }, helper = "For example NY or ON")
        ArgonInput("ZIP / postal code", typed.zip, { typed = typed.copy(zip = it) })
        if (choices.isEmpty()) {
            // the countries couldn't be loaded: the code can still be typed
            ArgonInput(
                "Country code",
                typed.countryCode.orEmpty(),
                { typed = typed.copy(countryCode = it.take(2)) },
                helper = "Two letters, for example US",
                error = problems[AddressField.Country],
            )
        } else {
            ArgonDropdown(
                "Country",
                choices.map { it.name },
                choices.indexOfFirst { it.code == typed.countryCode }.takeIf { it >= 0 },
                { index -> typed = typed.copy(countryCode = choices[index].code) },
            )
            ErrorText(problems[AddressField.Country])
        }
        ArgonInput(
            "Phone",
            typed.phone,
            { typed = typed.copy(phone = it) },
            helper = "With the country code, for example +1 613 555 0123",
            keyboard = ArgonKeyboard.Phone,
        )
        // the default address stays the default until another one takes over
        ArgonSwitch(typed.isDefault, { typed = typed.copy(isDefault = it) }, label = "Default address", isEnabled = original?.isDefault != true)
    }
    Column(Modifier.padding(spacing.l).imePadding(), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
        ErrorText(error)
        ArgonButton("Save address", isLoading = isSaving, fullWidth = true) {
            checked = true
            if (typed.errors().isEmpty()) onSave(typed)
        }
    }
}
