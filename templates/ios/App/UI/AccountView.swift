import ArgonUI
import os
import SwiftUI

private let accountLog = Logger(subsystem: "app.storefront", category: "Account")

/// `load`'s result, or nil when it fails: for the parts of a page that are left out rather than failing it.
@MainActor
private func optional<T>(_ what: String, _ load: () async throws -> T) async -> T? {
    do {
        return try await load()
    } catch {
        // the error's type only: a message could carry a URL
        accountLog.warning("\(what, privacy: .public) not loaded (\(String(describing: type(of: error)), privacy: .public))")
        return nil
    }
}

/// The shop's policies, each a row that opens it; none while they can't be loaded.
@MainActor
private func loadPolicies() async -> [ShopPolicy] {
    await optional("policies") { try await AppGraph.storefront.policies().all } ?? []
}

/// The Account tab. Signed out: what an account is for, "Sign in", and on the demo store "Preview with a sample account".
/// With an account (a signed-in customer, or the sample one): the customer, their company, store credit and latest order,
/// and the ways on (orders, profile, addresses, wishlist, policies, help).
@MainActor
struct AccountView: View {
    @State private var screen = ScreenSlot("account")
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Group {
            if let session = AppGraph.kwikPass?.session, session.complete, !AppGraph.sampleAccount {
                KwikPassAccount(session: session, screen: screen)
            } else if AppGraph.hasAccount {
                // not kept: a new order shows on the next visit, and nothing of this customer outlives a sign-out
                FreshLoader(load: loadAccount) { SignedIn(account: $0, screen: screen) }
            } else {
                SignedOut(screen: screen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.paper)
        .argonTopBar(title: "Account")
        .task { await screen.load() }
    }
}

// MARK: Signed out

@MainActor
private struct SignedOut: View {
    let screen: ScreenSlot
    @State private var starting = false
    @State private var failure: String? = nil
    @State private var policies: [ShopPolicy] = []
    // KwikPass's sign-in screens are up (LOGIN=kwikpass)
    @State private var kwikPassSignIn = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // the CLI lets a store skip the Customer Account client: no client id, no sign-in (KwikPass needs none)
        let canSignIn = AppGraph.canSignIn
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenSections(slot: screen, part: .above, bottom: theme.spacing.l)
                Text("Your account")
                    .font(theme.type.title)
                    .foregroundStyle(theme.colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, theme.spacing.l)
                VStack(spacing: 0) {
                    ArgonListItem(title: "Track your orders", leading: .icon(.truck))
                    ArgonListItem(title: "Faster checkout", leading: .icon(.bag))
                    ArgonListItem(title: "Returns in a few taps", leading: .icon(.returns))
                }
                .padding(.horizontal, theme.spacing.l)
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    ErrorText(failure ?? AppGraph.auth.signInError)
                    if canSignIn {
                        ArgonButton(title: "Sign in", isLoading: starting, fullWidth: true) { signIn() }
                    } else {
                        Text("Sign-in isn't configured for this store").font(theme.type.label).foregroundStyle(theme.colors.ink)
                        Text(verbatim: "Set CUSTOMER_CLIENT_ID in ios/Config.xcconfig")
                            .font(theme.type.caption)
                            .foregroundStyle(theme.colors.muted)
                    }
                    // the demo store has no customer accounts: its sample one shows the signed-in pages
                    if AppGraph.sampleAvailable {
                        ArgonButton(
                            title: "Preview with a sample account",
                            style: canSignIn ? .secondary : .primary,
                            fullWidth: true
                        ) { AppGraph.sampleAccount = true }
                    }
                }
                .padding(theme.spacing.l)
                ArgonDivider()
                VStack(spacing: 0) {
                    StoreRows(policies: policies)
                    DebugRows()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, theme.spacing.l)
                Privacy().padding(theme.spacing.l)
                NotificationsRow().padding([.horizontal, .bottom], theme.spacing.l)
                ScreenSections(slot: screen, part: .below, top: theme.spacing.l)
            }
            .padding(.vertical, theme.spacing.l)
        }
        .task { policies = await loadPolicies() }
        .argonFullScreenModal(isPresented: $kwikPassSignIn, title: "Sign in") {
            if let kwikPass = AppGraph.kwikPass {
                KwikPassSignIn(store: kwikPass) { kwikPassSignIn = false }
            }
        }
    }

    // Discovery runs first, so a store without the Customer Account API fails here (the error shows), before any browser opens.
    private func signIn() {
        if AppGraph.kwikPass != nil {
            kwikPassSignIn = true
            return
        }
        starting = true
        failure = nil
        Task {
            do {
                try await AppGraph.auth.signIn()
                // analytics' `login`: signIn() also returns quietly when the browser was closed or the callback refused,
                // which leave the shopper signed out
                if AppGraph.auth.signedIn { AppGraph.analytics.track(.login) }
            } catch {
                failure = error.localizedDescription
            }
            starting = false
        }
    }
}

/// The rows anyone gets, signed in or not: each of the shop's policies, and "Help" (the store's contact page).
@MainActor
private struct StoreRows: View {
    let policies: [ShopPolicy]
    @Environment(Router.self) private var router

    var body: some View {
        ForEach(policies, id: \.handle) { policy in
            ArgonListItem(title: policy.title, trailing: .chevron) { router.open(.policy(policy.handle)) }
        }
        ArgonListItem(title: "Help", trailing: .chevron) { router.open(contactRoute()) }
    }
}

/// Debug builds only: the Argon UI gallery, to review every component on a device, and (in an app with the welcome on)
/// "Show onboarding", which runs it again.
@MainActor
private struct DebugRows: View {
    @Environment(Router.self) private var router

    var body: some View {
        #if DEBUG
        ArgonListItem(title: "Components", trailing: .chevron) { router.path.append(.components) }
        if AppGraph.onboarding {
            ArgonListItem(title: "Show onboarding", trailing: .chevron) { AppGraph.onboardingStore.reset() }
        }
        #endif
    }
}

/// "Privacy", for anyone, signed in or not: the switch that lets the app share what the shopper does in it with the
/// store's analytics (`AppGraph.analytics` reports only while it is on). On until they turn it off.
@MainActor
private struct Privacy: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Privacy")
            ArgonSwitch(isOn: AppGraph.analyticsConsent.allowed, label: "Share usage data") { AppGraph.analyticsConsent.set($0) }
                .frame(minHeight: 44)
            Text("Helps improve the app and the offers you see.").font(theme.type.caption).foregroundStyle(theme.colors.muted)
        }
    }
}

// MARK: Signed in

/// What the signed-in screen shows. Only `customer` has to load: the rest is left out when its call fails.
private struct Account {
    let customer: Customer
    let latestOrder: OrderSummary?
    let credit: [Money]
    let policies: [ShopPolicy]
}

/// The profile with, side by side, the newest order, the store credit and the shop's policies.
@MainActor
private func loadAccount() async throws -> Account {
    let api = AppGraph.customerAccount
    async let order = optional("latest order") { try await api.orders().items.first }
    async let credit = optional("store credit") { try await creditBalances(api.storeCredit()) }
    async let policies = loadPolicies()
    let customer = try await api.customer()
    // analytics learns who the customer is where they are loaded; the sample account is nobody
    if !AppGraph.sampleAccount { AppGraph.analytics.identify(customer.analyticsUser()) }
    return await Account(customer: customer, latestOrder: order ?? nil, credit: credit ?? [], policies: policies)
}

@MainActor
private struct SignedIn: View {
    let account: Account
    let screen: ScreenSlot
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let spacing = theme.spacing
        let customer = account.customer
        let latest = account.latestOrder
        ScrollView {
            VStack(alignment: .leading, spacing: spacing.l) {
                ScreenSections(slot: screen, part: .above)
                Group {
                    if AppGraph.sampleAccount {
                        ArgonTag(text: "Sample account: nothing is saved", style: .info)
                    }
                    AccountHeader(customer: customer)
                    // the company comes from the buyer store: it follows the session by itself, and is nil for a retail customer
                    if let company = AppGraph.buyer.company {
                        CompanyCard(company: company)
                    }
                    if !account.credit.isEmpty {
                        ArgonListItem(title: "Store credit", trailing: .text(account.credit.map { $0.display() }.joined(separator: ", ")))
                    }
                    if let latest = latest {
                        VStack(alignment: .leading, spacing: spacing.s) {
                            SectionHeader(title: "Latest order", actionLabel: "All orders", onAction: { router.path.append(.orders) })
                            OrderCard(order: latest) { router.path.append(.order(latest.id)) }
                        }
                    }
                    VStack(spacing: 0) {
                        // no latest order to show (none yet, or it couldn't be loaded): the orders are still a row away
                        if latest == nil {
                            ArgonListItem(title: "All orders", trailing: .chevron) { router.path.append(.orders) }
                        }
                        ArgonListItem(title: "Profile", trailing: .chevron) { router.path.append(.profile) }
                        ArgonListItem(title: "Addresses", trailing: .chevron) { router.path.append(.addresses) }
                        ArgonListItem(title: "Wishlist", trailing: .chevron) { AppGraph.tabs.selected = .wishlist }
                        EmailOffers(customer: customer)
                        StoreRows(policies: account.policies)
                        ArgonListItem(title: "Manage account on the web", trailing: .chevron) {
                            router.open(.web("https://shopify.com/\(AppGraph.shopId)/account"))
                        }
                        DebugRows()
                    }
                    .buttonStyle(.plain)
                    Privacy()
                    NotificationsRow()
                    VStack(spacing: spacing.s) {
                        ArgonButton(title: "Sign out", style: .secondary, fullWidth: true) { signOut() }
                        // no API deletes a customer account, so the store's contact page takes the request (Apple and Google require the entry)
                        ArgonButton(title: "Delete account", style: .tertiary, fullWidth: true) { router.open(contactRoute()) }
                    }
                }
                .padding(.horizontal, spacing.l)
                ScreenSections(slot: screen, part: .below)
            }
            .padding(.vertical, spacing.l)
        }
    }
}

/// The avatar (the customer's picture, else their initials), their name and email.
@MainActor
private struct AccountHeader: View {
    let customer: Customer
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let name = accountName(customer)
        HStack(spacing: theme.spacing.m) {
            ArgonAvatar(
                imageUrl: customer.imageUrl.flatMap { URL(string: $0) },
                initials: initials(customer.firstName, customer.lastName, customer.email),
                size: .l
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(name ?? "Your account").font(theme.type.headline).foregroundStyle(theme.colors.ink).lineLimit(1)
                if let email = customer.email, email != name {
                    Text(email).font(theme.type.body).foregroundStyle(theme.colors.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The company the customer buys for and the location; with several locations, a dropdown to buy for another.
@MainActor
private struct CompanyCard: View {
    let company: BuyerCompany
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Panel {
            Text("Company").font(theme.type.caption).foregroundStyle(theme.colors.muted)
            Text(company.companyName).font(theme.type.headline).foregroundStyle(theme.colors.ink)
            if company.locations.count > 1 {
                ArgonDropdown(
                    label: "Location",
                    options: company.locations.map { $0.name },
                    selectedIndex: company.locations.firstIndex { $0.id == company.locationId }
                ) { index in
                    // not tied to the screen: the choice is stored and applied to the shop and the cart, whatever the screen does
                    Task { await AppGraph.buyer.select(company.locations[index].id) }
                }
            } else if let location = company.location {
                Text(location.name).font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
        }
    }
}

/// "Email offers": on subscribes the customer to the store's marketing emails, off unsubscribes; a refusal shows under it.
@MainActor
private struct EmailOffers: View {
    @State private var subscribed: Bool
    @State private var busy = false
    @State private var error: String? = nil

    init(customer: Customer) {
        _subscribed = State(initialValue: isSubscribed(customer.emailAddress?.marketingState))
    }

    var body: some View {
        ArgonSwitch(isOn: subscribed, label: "Email offers") { on in
            busy = true
            error = nil
            // not tied to the screen: leaving the tab doesn't drop the change
            Task {
                do {
                    let api = AppGraph.customerAccount
                    let answer = try await on ? api.subscribeEmailMarketing() : api.unsubscribeEmailMarketing()
                    subscribed = isSubscribed(answer.marketingState)
                } catch {
                    self.error = error.localizedDescription
                }
                busy = false
            }
        }
        .frame(minHeight: 44)
        .disabled(busy)
        ErrorText(error)
    }
}

// MARK: KwikPass

/// The account of a shopper signed in with KwikPass (`LOGIN=kwikpass`): their phone and email, and the rows that need no
/// Customer Account API (KwikPass gives the app no token for it: no orders, profile, addresses or returns here).
@MainActor
private struct KwikPassAccount: View {
    let session: KwikPassSession
    let screen: ScreenSlot
    @State private var policies: [ShopPolicy] = []
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let spacing = theme.spacing
        ScrollView {
            VStack(alignment: .leading, spacing: spacing.l) {
                ScreenSections(slot: screen, part: .above)
                Group {
                    HStack(spacing: spacing.m) {
                        ArgonAvatar(imageUrl: nil, initials: initials(nil, nil, session.email), size: .l)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "+91 \(session.phone)").font(theme.type.headline).foregroundStyle(theme.colors.ink)
                            Text(session.email).font(theme.type.body).foregroundStyle(theme.colors.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Your order updates arrive by SMS and email.").font(theme.type.caption).foregroundStyle(theme.colors.muted)
                    VStack(spacing: 0) {
                        ArgonListItem(title: "Wishlist", trailing: .chevron) { AppGraph.tabs.selected = .wishlist }
                        StoreRows(policies: policies)
                        DebugRows()
                    }
                    .buttonStyle(.plain)
                    Privacy()
                    NotificationsRow()
                    VStack(spacing: spacing.s) {
                        ArgonButton(title: "Sign out", style: .secondary, fullWidth: true) { signOut() }
                        // the store's contact page takes the request, as for any account
                        ArgonButton(title: "Delete account", style: .tertiary, fullWidth: true) { router.open(contactRoute()) }
                    }
                }
                .padding(.horizontal, spacing.l)
                ScreenSections(slot: screen, part: .below)
            }
            .padding(.vertical, spacing.l)
        }
        .task { policies = await loadPolicies() }
    }
}

/// Leaves the account: the sample one is just switched off; a signed-in customer is signed out, not tied to the screen
/// (which goes away as soon as the session does).
@MainActor
private func signOut() {
    if let kwikPass = AppGraph.kwikPass, kwikPass.signedIn {
        Task {
            // the cart carries the shopper's email and phone: it goes with them
            await AppGraph.cart.completed()
            await kwikPass.signOut()
        }
        return
    }
    let signedIn = AppGraph.auth.signedIn
    AppGraph.sampleAccount = false
    if !signedIn { return }
    AppGraph.analytics.identify(nil)
    Task {
        // The cart first, so it goes even if the logout call fails or hangs: one the customer was attached to would still
        // check out as them (shopify.dev Checkout Kit "Authenticate checkouts": clear the stored tokens and authenticated
        // carts). Only here, on an explicit sign-out: a session that ends mid-checkout must not lose the cart.
        await AppGraph.cart.completed()
        await AppGraph.auth.signOut()
        // AppRoot invalidates the preloaded checkout on both changes (the cart, then signedIn).
    }
}
