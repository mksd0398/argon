package app.storefront.ui

import android.net.Uri
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavController
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAvatar
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonDropdown
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListLeading
import app.argon.ui.components.ArgonListTrailing
import app.argon.ui.components.ArgonSwitch
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.argon.ui.components.ArgonTopBar
import app.storefront.AppGraph
import app.storefront.BuildConfig
import app.storefront.data.BuyerCompany
import app.storefront.data.Customer
import app.storefront.data.Money
import app.storefront.data.OrderSummary
import app.storefront.data.Placement
import app.storefront.data.Policy
import app.storefront.data.Route
import app.storefront.data.analyticsUser
import app.storefront.ui.account.ErrorText
import app.storefront.ui.account.Panel
import app.storefront.ui.account.accountName
import app.storefront.ui.account.contactRoute
import app.storefront.ui.account.creditBalances
import app.storefront.ui.account.initials
import app.storefront.ui.account.isSubscribed
import app.storefront.ui.orders.OrderCard
import app.storefront.ui.sections.SectionColumn
import app.storefront.ui.sections.SectionEnv
import app.storefront.ui.sections.rememberScreenSections
import app.storefront.ui.sections.rememberSectionEnv
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** "Oct 1, 2026" in the device's zone and locale. */
internal fun displayDate(iso: String): String = runCatching {
    Instant.parse(iso).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
}.getOrDefault(iso)

/** PARTIALLY_REFUNDED -> "Partially refunded". */
internal fun displayStatus(status: String) = status.lowercase().replace('_', ' ').replaceFirstChar { it.uppercase() }

/** [load]'s result, or null when it fails: for the parts of a page that are left out rather than failing it. */
private suspend fun <T> optional(what: String, load: suspend () -> T): T? = try {
    load()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    Log.w("Account", "$what not loaded (${e.javaClass.name})")
    null
}

/**
 * The Account tab. Signed out: what an account is for, "Sign in", and on the demo store "Preview with a sample account".
 * With an account (a signed-in customer, or the sample one): the customer, their company, store credit and latest order,
 * and the ways on (orders, profile, addresses, wishlist, policies, help). The store's sections (screens v2) go above
 * and below either.
 */
@Composable
fun AccountScreen(nav: NavController) {
    // screens v2: the store's sections above and below the account's own content, signed in or not
    val sections = rememberScreenSections("account")
    val env = rememberSectionEnv(sections, { nav.open(it) })
    val placement = sections?.placement
    Scaffold(topBar = { ArgonTopBar("Account", leading = nav.tabLeading("account")) }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val hasAccount by AppGraph.hasAccount.collectAsState()
            // not kept: a new order shows on the next visit, and nothing of this customer outlives a sign-out
            if (hasAccount) Loader(::loadAccount, keep = false) { SignedIn(it, nav, placement, env) } else SignedOut(nav, placement, env)
        }
    }
}

/** The shop's policies, each a row that opens it; none while they can't be loaded. */
private suspend fun loadPolicies(): List<Policy> = optional("policies") { AppGraph.storefront.policies().all }.orEmpty()

// Signed out

@Composable
private fun SignedOut(nav: NavController, sections: Placement?, env: SectionEnv?) {
    val spacing = ArgonTheme.spacing
    val context = LocalContext.current
    val screen = rememberCoroutineScope()
    val callbackError by AppGraph.auth.signInError.collectAsState()
    var starting by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    // the CLI lets a store skip the Customer Account client: no client id, no sign-in
    val canSignIn = AppGraph.customerClientId.isNotBlank()

    // Discovery runs first, so a store without the Customer Account API fails here (the error shows), before any browser opens.
    fun signIn() {
        starting = true
        failure = null
        screen.launch {
            try {
                AppGraph.auth.signIn { url -> CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e.message ?: e.toString()
            } finally {
                starting = false
            }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = spacing.l)) {
        SectionColumn(sections?.above.orEmpty(), env, Modifier.padding(bottom = spacing.l))
        Text(
            "Your account",
            Modifier.padding(horizontal = spacing.l).semantics { heading() },
            style = ArgonTheme.type.title,
            color = ArgonTheme.colors.ink,
        )
        ArgonListItem("Track your orders", leading = ArgonListLeading.Icon(ArgonIconName.Truck))
        ArgonListItem("Faster checkout", leading = ArgonListLeading.Icon(ArgonIconName.Bag))
        ArgonListItem("Returns in a few taps", leading = ArgonListLeading.Icon(ArgonIconName.Returns))
        Column(Modifier.padding(spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            ErrorText(failure ?: callbackError)
            if (canSignIn) {
                ArgonButton("Sign in", isLoading = starting, fullWidth = true) { signIn() }
            } else {
                Text("Sign-in isn't configured for this store", style = ArgonTheme.type.label, color = ArgonTheme.colors.ink)
                Text("Set CUSTOMER_CLIENT_ID in android/shopify.properties", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
            }
            // the demo store has no customer accounts: its sample one shows the signed-in pages
            if (AppGraph.sampleAvailable) {
                ArgonButton(
                    "Preview with a sample account",
                    style = if (canSignIn) ArgonButtonStyle.Secondary else ArgonButtonStyle.Primary,
                    fullWidth = true,
                ) { AppGraph.sampleAccount.value = true }
            }
        }
        ArgonDivider()
        val policies by produceState(emptyList<Policy>()) { value = loadPolicies() }
        StoreRows(policies, nav)
        DebugRows(nav)
        NotificationsSwitch(Modifier.padding(start = spacing.l, end = spacing.l, top = spacing.l))
        Privacy(Modifier.padding(spacing.l))
        SectionColumn(sections?.below.orEmpty(), env, Modifier.padding(top = spacing.l))
    }
}

/** The rows anyone gets, signed in or not: each of the shop's policies, and "Help" (the store's contact page). */
@Composable
private fun StoreRows(policies: List<Policy>, nav: NavController) {
    for (policy in policies) ArgonListItem(policy.title, trailing = ArgonListTrailing.Chevron, onClick = { nav.open(Route.Policy(policy.handle)) })
    ArgonListItem("Help", trailing = ArgonListTrailing.Chevron, onClick = { nav.open(contactRoute()) })
}

/**
 * Debug builds only: the Argon UI gallery, to review every component on a device, and (in an app with the welcome on)
 * "Show onboarding", which runs it again.
 */
@Composable
private fun DebugRows(nav: NavController) {
    if (!BuildConfig.DEBUG) return
    ArgonListItem("Components", trailing = ArgonListTrailing.Chevron, onClick = { nav.navigate("components") })
    if (AppGraph.onboarding) {
        ArgonListItem("Show onboarding", trailing = ArgonListTrailing.Chevron, onClick = { AppGraph.scope.launch { AppGraph.onboardingStore.reset() } })
    }
}

/**
 * "Privacy", for anyone, signed in or not: the switch that lets the app share what the shopper does in it with the
 * store's analytics (`AppGraph.analytics` reports only while it is on). On until they turn it off.
 */
@Composable
private fun Privacy(modifier: Modifier) {
    val allowed by AppGraph.analyticsConsent.allowed.collectAsState()
    Column(modifier) {
        SectionHeader("Privacy")
        ArgonSwitch(
            allowed,
            { on ->
                // on the app's scope: leaving the tab doesn't drop the change
                AppGraph.scope.launch {
                    // a failed write leaves the switch as it was; it must not crash the app
                    try {
                        AppGraph.analyticsConsent.set(on)
                    } catch (e: IOException) {
                        Log.w("Account", "usage data choice not saved", e)
                    }
                }
            },
            label = "Share usage data",
        )
        Text("Helps improve the app and the offers you see.", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    }
}

// Signed in

/** What the signed-in screen shows. Only [customer] has to load: the rest is left out when its call fails. */
private class Account(val customer: Customer, val latestOrder: OrderSummary?, val credit: List<Money>, val policies: List<Policy>)

/** The profile with, side by side, the newest order, the store credit and the shop's policies. */
private suspend fun loadAccount(): Account = coroutineScope {
    val api = AppGraph.customerAccount
    val order = async { optional("latest order") { api.orders().items.firstOrNull() } }
    val credit = async { optional("store credit") { creditBalances(api.storeCredit()) }.orEmpty() }
    val policies = async { loadPolicies() }
    val customer = api.customer()
    // analytics learns who the customer is where they are loaded; the sample account is nobody
    if (!AppGraph.sampleAccount.value) AppGraph.analytics.identify(customer.analyticsUser())
    Account(customer, order.await(), credit.await(), policies.await())
}

@Composable
private fun SignedIn(account: Account, nav: NavController, sections: Placement?, env: SectionEnv?) {
    val spacing = ArgonTheme.spacing
    val customer = account.customer
    val sample by AppGraph.sampleAccount.collectAsState()
    // the company comes from the buyer store: it follows the session by itself, and is null for a retail customer
    val company by AppGraph.buyer.company.collectAsState()
    val gutter = Modifier.padding(horizontal = spacing.l)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = spacing.l), verticalArrangement = Arrangement.spacedBy(spacing.l)) {
        SectionColumn(sections?.above.orEmpty(), env)
        if (sample) ArgonTag("Sample account: nothing is saved", gutter, style = ArgonTagStyle.Info)
        AccountHeader(customer, gutter)
        company?.let { CompanyCard(it, gutter) }
        if (account.credit.isNotEmpty()) {
            ArgonListItem("Store credit", trailing = ArgonListTrailing.Text(account.credit.joinToString(", ") { it.display() }))
        }
        val latest = account.latestOrder
        if (latest != null) {
            Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.s)) {
                SectionHeader("Latest order", actionLabel = "All orders", onAction = { nav.navigate("orders") })
                OrderCard(latest, onOpen = { nav.navigate("order/${Uri.encode(latest.id)}") })
            }
        }
        Column {
            // no latest order to show (none yet, or it couldn't be loaded): the orders are still a row away
            if (latest == null) ArgonListItem("All orders", trailing = ArgonListTrailing.Chevron, onClick = { nav.navigate("orders") })
            ArgonListItem("Profile", trailing = ArgonListTrailing.Chevron, onClick = { nav.navigate("profile") })
            ArgonListItem("Addresses", trailing = ArgonListTrailing.Chevron, onClick = { nav.navigate("addresses") })
            ArgonListItem("Wishlist", trailing = ArgonListTrailing.Chevron, onClick = { AppGraph.tabs.select(AppTab.Wishlist) })
            EmailOffers(customer, gutter)
            StoreRows(account.policies, nav)
            ArgonListItem(
                "Manage account on the web",
                trailing = ArgonListTrailing.Chevron,
                onClick = { nav.open(Route.Web("https://shopify.com/${AppGraph.shopId}/account")) },
            )
            DebugRows(nav)
        }
        NotificationsSwitch(gutter)
        Privacy(gutter)
        Column(gutter, verticalArrangement = Arrangement.spacedBy(spacing.s)) {
            ArgonButton("Sign out", style = ArgonButtonStyle.Secondary, fullWidth = true) { signOut() }
            // no API deletes a customer account, so the store's contact page takes the request (Apple and Google require the entry)
            ArgonButton("Delete account", style = ArgonButtonStyle.Tertiary, fullWidth = true) { nav.open(contactRoute()) }
        }
        SectionColumn(sections?.below.orEmpty(), env)
    }
}

/** The avatar (the customer's picture, else their initials), their name and email. */
@Composable
private fun AccountHeader(customer: Customer, modifier: Modifier) {
    val name = accountName(customer)
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.CenterVertically) {
        ArgonAvatar(imageUrl = customer.imageUrl, initials = initials(customer.firstName, customer.lastName, customer.email), size = ArgonSize.L)
        Column(Modifier.weight(1f)) {
            Text(name ?: "Your account", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            customer.email?.takeIf { it != name }?.let {
                Text(it, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** The company the customer buys for and the location; with several locations, a dropdown to buy for another. */
@Composable
private fun CompanyCard(company: BuyerCompany, modifier: Modifier) = Panel(modifier) {
    Text("Company", style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
    Text(company.companyName, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    if (company.locations.size > 1) {
        ArgonDropdown(
            "Location",
            company.locations.map { it.name },
            company.locations.indexOfFirst { it.id == company.locationId }.takeIf { it >= 0 },
            // on the app's scope: the choice is stored and applied to the shop and the cart, whatever the screen does
            { index -> AppGraph.scope.launch { AppGraph.buyer.select(company.locations[index].id) } },
        )
    } else {
        company.location?.let { Text(it.name, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted) }
    }
}

/** "Email offers": on subscribes the customer to the store's marketing emails, off unsubscribes; a refusal shows under it. */
@Composable
private fun EmailOffers(customer: Customer, gutter: Modifier) {
    var subscribed by remember { mutableStateOf(isSubscribed(customer.emailAddress?.marketingState)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    ArgonSwitch(
        subscribed,
        { on ->
            busy = true
            error = null
            // on the app's scope: leaving the tab doesn't drop the change
            AppGraph.scope.launch {
                try {
                    val api = AppGraph.customerAccount
                    val answer = if (on) api.subscribeEmailMarketing() else api.unsubscribeEmailMarketing()
                    subscribed = isSubscribed(answer.marketingState)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    error = e.message ?: e.toString()
                } finally {
                    busy = false
                }
            }
        },
        gutter,
        label = "Email offers",
        isEnabled = !busy,
    )
    ErrorText(error, gutter)
}

/**
 * Leaves the account: the sample one is just switched off; a signed-in customer is signed out, on the app's scope so it
 * finishes even if the shopper leaves the tab.
 */
private fun signOut() {
    val signedIn = AppGraph.auth.signedIn.value
    AppGraph.sampleAccount.value = false
    if (!signedIn) return
    AppGraph.analytics.identify(null)
    AppGraph.scope.launch {
        try {
            // the cart too: one the customer was attached to would still check out as them (shopify.dev
            // Checkout Kit "Authenticate checkouts": clear the stored tokens and authenticated carts).
            // Only here, on an explicit sign-out: a session that ends mid-checkout must not lose the cart.
            // First, so a slow or failing logout call can't leave it behind.
            try {
                AppGraph.cart.completed()
            } finally {
                AppGraph.auth.signOut()
            }
        } catch (e: Exception) {
            Log.w("Account", "sign-out failed", e)
        }
    }
}
