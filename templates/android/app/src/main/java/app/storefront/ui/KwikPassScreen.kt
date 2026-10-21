package app.storefront.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonInputOTP
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListTrailing
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.auth.KwikPassStep
import app.storefront.auth.KwikPassStore
import app.storefront.auth.indianMobile
import app.storefront.data.AnalyticsEvent
import app.storefront.data.AnalyticsUser
import app.storefront.ui.account.ErrorText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// KwikPass's codes are 4 digits, by phone and by email (its SDK's own screens)
private const val CODE_LENGTH = 4

/** Where the KwikPass sign-in is: the phone, its code, then (when GoKwik asks) the email and its code. */
private sealed interface KwikPassForm {
    data object Phone : KwikPassForm
    data class PhoneCode(val phone: String, val wait: Int) : KwikPassForm
    data object Email : KwikPassForm
    data class Choose(val emails: List<String>) : KwikPassForm
    data class EmailCode(val email: String) : KwikPassForm
}

/**
 * KwikPass sign-in (`kwikpass`, LOGIN=kwikpass), where "Sign in" leads in place of Shopify's: the shopper's Indian mobile
 * number and the code sent to it; then, as GoKwik answers, their email (a new number), a choice of emails (a number
 * several customers share) or the code sent to their email (an existing account). Signed in, it goes back.
 */
@Composable
fun KwikPassScreen(nav: NavController) {
    val kwikPass = AppGraph.kwikPass ?: return
    val spacing = ArgonTheme.spacing
    val screen = rememberCoroutineScope()
    var form by remember { mutableStateOf<KwikPassForm>(KwikPassForm.Phone) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    /** Runs a step of the sign-in with the form busy; how it failed shows on the form. */
    fun act(block: suspend () -> Unit) {
        busy = true
        error = null
        screen.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: e.toString()
            } finally {
                busy = false
            }
        }
    }

    fun go(step: KwikPassStep) {
        form = when (step) {
            KwikPassStep.SignedIn -> return signedIn(kwikPass, nav)
            KwikPassStep.EnterEmail -> KwikPassForm.Email
            is KwikPassStep.ChooseEmail -> KwikPassForm.Choose(step.emails)
            is KwikPassStep.EmailCode -> KwikPassForm.EmailCode(step.email)
        }
    }

    Scaffold(topBar = { ArgonTopBar("Sign in", leading = listOf(nav.backAction())) }) { padding ->
        // the keyboard pushes the form up instead of covering it
        Box(Modifier.padding(padding).consumeWindowInsets(padding).imePadding().fillMaxSize()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.m)) {
                when (val current = form) {
                    KwikPassForm.Phone -> PhoneForm(busy, error) { phone -> act { form = KwikPassForm.PhoneCode(phone, kwikPass.sendCode(phone)) } }
                    is KwikPassForm.PhoneCode -> CodeForm(
                        "Enter the code sent to +91 ${current.phone}",
                        current.wait,
                        busy,
                        error,
                        onVerify = { code -> act { go(kwikPass.verifyCode(code)) } },
                        onResend = { act { form = current.copy(wait = kwikPass.sendCode(current.phone)) } },
                        onChangeNumber = { error = null; form = KwikPassForm.Phone },
                    )
                    KwikPassForm.Email -> EmailForm(busy, error) { email -> act { go(kwikPass.submitEmail(email)) } }
                    is KwikPassForm.Choose -> {
                        Text("Choose your email", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
                        Text("More than one account uses this number.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
                        ErrorText(error)
                        for (email in current.emails) {
                            ArgonListItem(email, trailing = ArgonListTrailing.Chevron, onClick = { if (!busy) act { go(kwikPass.submitEmail(email)) } })
                        }
                    }
                    is KwikPassForm.EmailCode -> CodeForm(
                        "Enter the code sent to ${current.email}",
                        30,
                        busy,
                        error,
                        onVerify = { code -> act { go(kwikPass.verifyEmailCode(current.email, code)) } },
                        onResend = { act { kwikPass.sendEmailCode(current.email) } },
                    )
                }
            }
        }
    }
}

/** Signed in: analytics hears who it is, and the screen goes back (to the Account tab, now signed in). */
private fun signedIn(kwikPass: KwikPassStore, nav: NavController) {
    kwikPass.user.value?.let { AppGraph.analytics.identify(AnalyticsUser(it.shopifyCustomerId, email = it.email, phone = it.e164)) }
    AppGraph.analytics.track(AnalyticsEvent.Login)
    nav.popBackStack()
}

/** The mobile number, after a fixed +91: "Send code" once it is a 10-digit Indian mobile. */
@Composable
private fun PhoneForm(busy: Boolean, error: String?, onSend: (String) -> Unit) {
    var typed by remember { mutableStateOf("") }
    val phone = indianMobile(typed)
    Text("Sign in with your phone", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    Text("We'll send a code to your mobile number.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        // level with the field's box, which starts under the room its label floats in
        Text("+91", Modifier.padding(top = 8.dp), style = ArgonTheme.type.body, color = ArgonTheme.colors.ink)
        ArgonInput(
            "Mobile number",
            typed,
            { typed = it.filter(Char::isDigit).take(10) },
            Modifier.weight(1f),
            error = error,
            keyboard = ArgonKeyboard.Phone,
            isEnabled = !busy,
        )
    }
    ArgonButton("Send code", isLoading = busy, isEnabled = phone != null, fullWidth = true) { phone?.let(onSend) }
}

/**
 * A code: [title], its digits (verified as soon as the last is in, or with "Verify"), and "Resend code" once [wait]
 * seconds have passed since it was sent; with [onChangeNumber], "Change number" goes back to the phone.
 */
@Composable
private fun CodeForm(
    title: String,
    wait: Int,
    busy: Boolean,
    error: String?,
    onVerify: (String) -> Unit,
    onResend: () -> Unit,
    onChangeNumber: (() -> Unit)? = null,
) {
    var code by remember(title) { mutableStateOf("") }
    var sent by remember(title) { mutableIntStateOf(0) } // counts the sends: each restarts the wait
    var left by remember(title) { mutableIntStateOf(wait) }
    LaunchedEffect(title, sent) {
        left = wait
        while (left > 0) {
            delay(1_000)
            left--
        }
    }
    Text(title, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    ArgonInputOTP(code, { code = it }, { if (!busy) onVerify(it) }, length = CODE_LENGTH)
    ErrorText(error)
    ArgonButton("Verify", isLoading = busy, isEnabled = code.length == CODE_LENGTH, fullWidth = true) { onVerify(code) }
    ArgonButton(
        if (left > 0) "Resend code in ${left}s" else "Resend code",
        style = ArgonButtonStyle.Tertiary,
        isEnabled = left == 0 && !busy,
        fullWidth = true,
    ) {
        code = ""
        sent++
        onResend()
    }
    onChangeNumber?.let { ArgonButton("Change number", style = ArgonButtonStyle.Tertiary, isEnabled = !busy, fullWidth = true, action = it) }
}

/** A new number's email: GoKwik finds the customer by it, or creates one. */
@Composable
private fun EmailForm(busy: Boolean, error: String?, onSubmit: (String) -> Unit) {
    var email by remember { mutableStateOf("") }
    Text("What's your email?", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    Text("Your orders and account are kept under it.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
    ArgonInput("Email", email, { email = it }, error = error, keyboard = ArgonKeyboard.Email, isEnabled = !busy)
    ArgonButton("Continue", isLoading = busy, isEnabled = email.contains('@'), fullWidth = true) { onSubmit(email.trim()) }
}
