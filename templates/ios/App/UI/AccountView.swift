import SwiftUI

private let isoDate = ISO8601DateFormatter()

/// "Oct 1, 2026" in the device's zone and locale; the text as it came when it isn't an ISO-8601 date-time.
func displayDate(_ iso: String) -> String {
    guard let date = isoDate.date(from: iso) else { return iso }
    return date.formatted(date: .abbreviated, time: .omitted)
}

/// PARTIALLY_REFUNDED -> "Partially refunded".
func displayStatus(_ status: String) -> String {
    let words = status.lowercased().replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + String(words.dropFirst())
}

@MainActor
private func loadCustomer() async throws -> Customer {
    guard let customer = try await AppGraph.auth.customerQuery("Customer").obj("customer") else {
        throw StorefrontException(messages: ["Account not found"], status: nil)
    }
    return try parseCustomer(customer)
}

@MainActor
struct AccountView: View {
    // Each visit loads the customer again: a new order shows, and nothing of this customer outlives a sign-out.
    @State private var visit = 0

    var body: some View {
        VStack {
            // the CLI lets a store skip the Customer Account client: no client id, no sign-in
            if AppGraph.customerClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    Text("Sign-in isn't configured for this store").font(.headline)
                    Text(verbatim: "Set CUSTOMER_CLIENT_ID in ios/Config.xcconfig").font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(32)
            } else if AppGraph.auth.signedIn {
                Loader(load: loadCustomer) { CustomerContent(customer: $0) }.id(visit)
            } else {
                SignedOut()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        // the ArgonUI gallery, to review the components on a phone, signed in or not (debug builds only)
        .safeAreaInset(edge: .bottom) {
            NavigationLink(value: Destination.components) {
                HStack {
                    Text("Components")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
        #endif
        .navigationTitle("Account")
        .onDisappear { visit += 1 }
    }
}

@MainActor
private struct SignedOut: View {
    @State private var starting = false
    @State private var failure: String? = nil

    var body: some View {
        if starting {
            ProgressView()
        } else if let failure = failure {
            ErrorView(message: failure) { signIn() }
        } else {
            VStack(spacing: 12) {
                if let error = AppGraph.auth.signInError {
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button { signIn() } label: { Text("Sign in").onBrand() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
        }
    }

    // Discovery runs first, so a store without the Customer Account API fails here (error + Retry), before any browser opens.
    private func signIn() {
        starting = true
        failure = nil
        Task {
            do {
                try await AppGraph.auth.signIn()
            } catch {
                failure = error.localizedDescription
            }
            starting = false
        }
    }
}

@MainActor
private struct CustomerContent: View {
    let customer: Customer
    @Environment(Router.self) private var router

    var body: some View {
        List {
            if !customer.name.isEmpty || customer.email != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if !customer.name.isEmpty { Text(customer.name).font(.title2) }
                    if let email = customer.email { Text(email).foregroundStyle(.secondary) }
                }
            }
            SwiftUI.Section("Orders") {
                if customer.orders.isEmpty {
                    Text("No orders yet").foregroundStyle(.secondary)
                }
                ForEach(customer.orders, id: \.id) { order in
                    NavigationLink(value: Destination.order(order.id)) { OrderRow(order: order) }
                }
            }
            SwiftUI.Section {
                Button("Sign out") { signOut() }
                // no API deletes a customer account, so the store's contact page takes the request (Apple and Google require the entry)
                Button("Delete account", role: .destructive) {
                    router.open(.web("https://\(AppGraph.shopDomain)/pages/contact"))
                }
            }
        }
    }

    private func signOut() {
        // Not tied to this screen, which goes away as soon as the session does.
        Task {
            // The cart first, so it goes even if the logout call fails or hangs: one the customer was attached to would still
            // check out as them (shopify.dev Checkout Kit "Authenticate checkouts": clear the stored tokens and authenticated
            // carts). Only here, on an explicit sign-out: a session that ends mid-checkout must not lose the cart.
            await AppGraph.cart.completed()
            await AppGraph.auth.signOut()
            // AppRoot invalidates the preloaded checkout on both changes (the cart, then signedIn).
        }
    }
}

@MainActor
private struct OrderRow: View {
    let order: OrderSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.name)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(order.total.display())
        }
    }

    private var detail: String {
        var parts = [displayDate(order.processedAt)]
        if let status = order.financialStatus { parts.append(displayStatus(status)) }
        return parts.joined(separator: " · ")
    }
}
