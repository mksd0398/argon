import ArgonUI
import os
import SwiftUI

private let addressLog = Logger(subsystem: "app.storefront", category: "Addresses")

/// A country the address form offers: its ISO `code` and `name`.
private struct CountryChoice {
    let code: String
    let name: String
}

/// The address book with the countries the shop sells to (the form's dropdown; none when they can't be loaded).
private struct AddressBook {
    let addresses: [CustomerAddress]
    let countries: [CountryChoice]
}

// ponytail: the first page of addresses (20). Page through `addresses(after:)` when a store's customers keep more.
@MainActor
private func loadAddresses() async throws -> [CustomerAddress] {
    try await AppGraph.customerAccount.addresses().items
}

@MainActor
private func loadCountries() async -> [CountryChoice] {
    do {
        return try await AppGraph.storefront.localization().availableCountries
            .map { CountryChoice(code: $0.isoCode, name: trimmedText($0.name) == nil ? $0.isoCode : $0.name) }
            .sorted { $0.name < $1.name }
    } catch {
        // the error's type only: a message could carry a URL
        addressLog.warning("countries not loaded (\(String(describing: type(of: error)), privacy: .public))")
        return []
    }
}

@MainActor
private func loadAddressBook() async throws -> AddressBook {
    async let countries = loadCountries()
    let addresses = try await loadAddresses()
    return await AddressBook(addresses: addresses, countries: countries)
}

/// The customer's address book (route `addresses`): each address with Edit, Delete and "Make default", and "Add address".
@MainActor
struct AddressesView: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // not kept: the customer's own data is read again on each visit
        FreshLoader(load: loadAddressBook) { AddressBookContent(book: $0) }
            .background(theme.colors.paper)
            .argonTopBar(title: "Addresses")
    }
}

/// What the form's change and its error go by, among the address ids.
private let formKey = "form"

@MainActor
private struct AddressBookContent: View {
    let book: AddressBook
    @State private var addresses: [CustomerAddress]
    // The form's address (nil: a new one) and the address to delete stay set while their sheet and their question go
    // away, so neither blanks on the way out; `formOpen` and `confirming` show them.
    @State private var editing: CustomerAddress? = nil
    @State private var formOpen = false
    @State private var deleting: CustomerAddress? = nil
    @State private var confirming = false
    // the change in flight and what went wrong, by address id (the form's under `formKey`)
    @State private var busy: String? = nil
    @State private var errors: [String: String] = [:]
    @Environment(\.argonTheme) private var theme

    init(book: AddressBook) {
        self.book = book
        _addresses = State(initialValue: book.addresses)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if addresses.isEmpty {
                    Text("No addresses yet").font(theme.type.body).foregroundStyle(theme.colors.muted)
                }
                ForEach(addresses, id: \.id) { address in
                    AddressCard(
                        address: address,
                        isBusy: busy == address.id,
                        error: errors[address.id],
                        onEdit: { open(address) },
                        onDelete: {
                            deleting = address
                            confirming = true
                        },
                        onMakeDefault: {
                            act(address.id, done: "Default address updated") {
                                _ = try await AppGraph.customerAccount.updateAddress(address.id, isDefault: true)
                            }
                        }
                    )
                }
                ArgonButton(title: "Add address", fullWidth: true) { open(nil) }
            }
            .padding(theme.spacing.l)
        }
        .argonBottomSheet(isPresented: $formOpen, detents: [.large]) {
            AddressFormSheet(original: editing, countries: book.countries, isSaving: busy == formKey, error: errors[formKey]) { typed in
                save(typed, editing)
            }
            // a form per address: what was typed for one never shows for another
            .id(editing?.id)
        }
        .argonModal(
            isPresented: $confirming,
            title: "Delete address?",
            message: deleting.map { addressLines($0).prefix(3).joined(separator: ", ") } ?? "",
            primaryAction: ArgonModalAction("Delete", isDestructive: true) {
                guard let address = deleting else { return }
                act(address.id, done: "Address deleted") { _ = try await AppGraph.customerAccount.deleteAddress(address.id) }
            },
            secondaryAction: ArgonModalAction("Cancel")
        )
    }

    /// Opens the form: for `address`, or for a new one (nil).
    private func open(_ address: CustomerAddress?) {
        errors[formKey] = nil
        editing = address
        formOpen = true
    }

    private func save(_ typed: AddressForm, _ original: CustomerAddress?) {
        act(formKey, done: "Address saved") {
            let api = AppGraph.customerAccount
            if let original = original {
                // the default can only be given, not taken away: another address takes it over
                _ = try await api.updateAddress(original.id, typed.toInput(original), isDefault: typed.isDefault && !original.isDefault ? true : nil)
            } else {
                _ = try await api.createAddress(typed.toInput(), isDefault: typed.isDefault)
            }
        }
    }

    /// Runs `change` apart from the screen (leaving it doesn't drop the change), then says `done` and reads the book again.
    private func act(_ key: String, done: String, _ change: @escaping () async throws -> Void) {
        busy = key
        errors[key] = nil
        Task {
            do {
                try await change()
            } catch {
                errors[key] = error.localizedDescription
                busy = nil
                return
            }
            busy = nil
            if key == formKey { formOpen = false }
            AppGraph.toast.show(done)
            do {
                addresses = try await loadAddresses()
            } catch {
                // the change went through; the list catches up on the next visit
                addressLog.warning("address book not reloaded (\(String(describing: type(of: error)), privacy: .public))")
            }
        }
    }
}

/// An address as Shopify formats it, "Default" on the default one, and its actions; a change that failed shows under them.
@MainActor
private struct AddressCard: View {
    let address: CustomerAddress
    let isBusy: Bool
    let error: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMakeDefault: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Text(addressLines(address).joined(separator: "\n"))
                    .font(theme.type.body)
                    .foregroundStyle(theme.colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if address.isDefault { ArgonTag(text: "Default", style: .info) }
            }
            WrappingRow(spacing: theme.spacing.s, lineSpacing: theme.spacing.s) {
                ArgonButton(title: "Edit", style: .secondary, size: .s, isEnabled: !isBusy, action: onEdit)
                // Shopify refuses to delete the default address: another one has to be made the default first
                ArgonButton(title: "Delete", style: .tertiary, size: .s, isEnabled: !isBusy && !address.isDefault, action: onDelete)
                if !address.isDefault {
                    ArgonButton(title: "Make default", style: .tertiary, size: .s, isLoading: isBusy, action: onMakeDefault)
                }
            }
            if address.isDefault {
                Text("The default address can't be deleted").font(theme.type.caption).foregroundStyle(theme.colors.muted)
            }
            ErrorText(error)
        }
    }
}

/// The address form, in a sheet: for `original`, or empty for a new address. What the form checks itself shows on its
/// fields once "Save address" is tapped; Shopify's own complaints (`error`) show under the form.
@MainActor
private struct AddressFormSheet: View {
    let original: CustomerAddress?
    let countries: [CountryChoice]
    let isSaving: Bool
    let error: String?
    let onSave: (AddressForm) -> Void
    @State private var typed: AddressForm
    @State private var checked = false
    @Environment(\.argonTheme) private var theme

    init(original: CustomerAddress?, countries: [CountryChoice], isSaving: Bool, error: String?, onSave: @escaping (AddressForm) -> Void) {
        self.original = original
        self.countries = countries
        self.isSaving = isSaving
        self.error = error
        self.onSave = onSave
        _typed = State(initialValue: AddressForm.of(original))
    }

    /// The countries the shop sells to, and the address's own when it is none of them (it can still be kept).
    private var choices: [CountryChoice] {
        guard let own = original?.countryCode, !countries.contains(where: { $0.code == own }) else { return countries }
        return countries + [CountryChoice(code: own, name: original?.country ?? own)]
    }

    var body: some View {
        let spacing = theme.spacing
        let problems = checked ? typed.errors() : [:]
        let choices = self.choices
        VStack(spacing: 0) {
            // the fields scroll; the button under them stays in reach, above the keyboard
            ScrollView {
                VStack(alignment: .leading, spacing: spacing.s) {
                    Text(original == nil ? "Add address" : "Edit address")
                        .font(theme.type.title)
                        .foregroundStyle(theme.colors.ink)
                        .accessibilityAddTraits(.isHeader)
                    Group {
                        ArgonInput(label: "First name", text: $typed.firstName)
                        ArgonInput(label: "Last name", text: $typed.lastName)
                        ArgonInput(label: "Company", text: $typed.company)
                        ArgonInput(label: "Address line 1", text: $typed.address1, error: problems[.address1])
                        ArgonInput(label: "Address line 2", text: $typed.address2)
                        ArgonInput(label: "City", text: $typed.city, error: problems[.city])
                        ArgonInput(label: "State / province code", text: $typed.zoneCode, helper: "For example NY or ON")
                        ArgonInput(label: "ZIP / postal code", text: $typed.zip)
                    }
                    if choices.isEmpty {
                        // the countries couldn't be loaded: the code can still be typed
                        ArgonInput(
                            label: "Country code",
                            text: Binding(get: { typed.countryCode ?? "" }, set: { typed.countryCode = $0 }),
                            helper: "Two letters, for example US",
                            error: problems[.country]
                        )
                        .onChange(of: typed.countryCode) { _, code in
                            if let code = code, code.count > 2 { typed.countryCode = String(code.prefix(2)) }
                        }
                    } else {
                        ArgonDropdown(
                            label: "Country",
                            options: choices.map { $0.name },
                            selectedIndex: choices.firstIndex { $0.code == typed.countryCode }
                        ) { index in typed.countryCode = choices[index].code }
                        ErrorText(problems[.country])
                    }
                    ArgonInput(
                        label: "Phone",
                        text: $typed.phone,
                        helper: "With the country code, for example +1 613 555 0123",
                        keyboard: .phone
                    )
                    // the default address stays the default until another one takes over
                    ArgonSwitch(isOn: typed.isDefault, label: "Default address") { typed.isDefault = $0 }
                        .frame(minHeight: 44)
                        .disabled(original?.isDefault == true)
                }
                .padding(.horizontal, spacing.l)
                // clear of the sheet's drag indicator
                .padding(.top, spacing.xl)
                .padding(.bottom, spacing.s)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(alignment: .leading, spacing: spacing.s) {
                ErrorText(error)
                ArgonButton(title: "Save address", isLoading: isSaving, fullWidth: true) {
                    checked = true
                    if typed.errors().isEmpty { onSave(typed) }
                }
            }
            .padding(spacing.l)
        }
        .background { theme.colors.surface.ignoresSafeArea() }
    }
}
