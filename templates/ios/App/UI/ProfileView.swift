import ArgonUI
import SwiftUI

/// The customer's name, email and phone (route `profile`). The name can be changed here; the other two only on the web.
@MainActor
struct ProfileView: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // not kept: the customer's own data is read again on each visit
        FreshLoader(load: { try await AppGraph.customerAccount.customer() }) { ProfileForm(customer: $0) }
            .background(theme.colors.paper)
            .argonTopBar(title: "Profile")
    }
}

@MainActor
private struct ProfileForm: View {
    let customer: Customer
    @State private var first: String
    @State private var last: String
    // the name as last saved: "Save" is for a name that differs from it
    @State private var saved: [String]
    @State private var saving = false
    @State private var error: String? = nil
    @Environment(\.argonTheme) private var theme

    init(customer: Customer) {
        self.customer = customer
        _first = State(initialValue: customer.firstName ?? "")
        _last = State(initialValue: customer.lastName ?? "")
        _saved = State(initialValue: [customer.firstName ?? "", customer.lastName ?? ""])
    }

    var body: some View {
        let typed = [first, last].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // the keyboard pushes the form up instead of covering it (a scroll view keeps clear of it)
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                ArgonInput(label: "First name", text: $first)
                ArgonInput(label: "Last name", text: $last)
                ErrorText(error)
                ArgonButton(title: "Save", isLoading: saving, isEnabled: typed != saved, fullWidth: true) { save(typed) }
                // the Customer Account API changes neither: the store's web account does
                Group {
                    ArgonInput(label: "Email", text: .constant(customer.email ?? ""), keyboard: .email)
                    ArgonInput(label: "Phone", text: .constant(customer.phone ?? ""), keyboard: .phone)
                }
                .disabled(true)
                // dimmed as Argon's own controls are when they are off
                .opacity(0.4)
                Text("Change these in your web account").font(theme.type.caption).foregroundStyle(theme.colors.muted)
            }
            .padding(theme.spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save(_ typed: [String]) {
        saving = true
        error = nil
        // not tied to the screen: leaving it doesn't drop the change
        Task {
            do {
                _ = try await AppGraph.customerAccount.updateName(first: typed[0], last: typed[1])
                saved = typed
                AppGraph.toast.show("Profile saved")
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
