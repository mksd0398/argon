package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.data.Customer
import app.storefront.ui.account.ErrorText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** The customer's name, email and phone (`profile`). The name can be changed here; the other two only on the web. */
@Composable
fun ProfileScreen(nav: NavController) {
    Scaffold(topBar = { ArgonTopBar("Profile", leading = listOf(nav.backAction())) }) { padding ->
        // the keyboard pushes the form up instead of covering it
        Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding().fillMaxSize()) {
            // not kept: the customer's own data is read again on each visit
            Loader({ AppGraph.customerAccount.customer() }, keep = false) { ProfileForm(it) }
        }
    }
}

@Composable
private fun ProfileForm(customer: Customer) {
    val spacing = ArgonTheme.spacing
    var first by remember { mutableStateOf(customer.firstName.orEmpty()) }
    var last by remember { mutableStateOf(customer.lastName.orEmpty()) }
    // the name as last saved: "Save" is for a name that differs from it
    var saved by remember { mutableStateOf(customer.firstName.orEmpty() to customer.lastName.orEmpty()) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val typed = first.trim() to last.trim()

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
        ArgonInput("First name", first, { first = it })
        ArgonInput("Last name", last, { last = it })
        ErrorText(error)
        ArgonButton("Save", isLoading = saving, isEnabled = typed != saved, fullWidth = true) {
            saving = true
            error = null
            // on the app's scope: leaving the screen doesn't drop the change
            AppGraph.scope.launch {
                try {
                    AppGraph.customerAccount.updateName(typed.first, typed.second)
                    saved = typed
                    AppGraph.toast.show("Profile saved")
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.message ?: e.toString()
                } finally {
                    saving = false
                }
            }
        }
        // the Customer Account API changes neither: the store's web account does
        ArgonInput("Email", customer.email.orEmpty(), {}, keyboard = ArgonKeyboard.Email, isEnabled = false)
        ArgonInput("Phone", customer.phoneNumber?.phoneNumber.orEmpty(), {}, keyboard = ArgonKeyboard.Phone, isEnabled = false)
        Text("Change these in your web account", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    }
}
