import Foundation

// The account pages' rules, kept free of UI so they can be tested (and read side by side with Android).

/// `text` without the whitespace around it; nil when that leaves nothing (or there was no text).
func trimmedText(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

extension Array {
    /// The elements whose `key` wasn't seen before, in order.
    func distinct<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

/// The avatar's letters: the first of each name ("AL"), of the one name there is ("A"), else of the email. Nil when there
/// is nothing to go by (the avatar then shows its person icon).
func initials(_ firstName: String?, _ lastName: String?, _ email: String?) -> String? {
    func first(_ text: String?) -> String? {
        guard let character = trimmedText(text)?.first, character.isLetter || character.isNumber else { return nil }
        return String(character).uppercased()
    }
    let letters = [first(firstName), first(lastName)].compactMap { $0 }.joined()
    return letters.isEmpty ? first(email) : letters
}

/// What to call the customer: their name, else Shopify's display name (often the email), else the email; nil with none of them.
func accountName(_ customer: Customer) -> String? {
    [customer.name, customer.displayName, customer.email].compactMap { trimmedText($0) }.first
}

/// Whether the "Email offers" switch is on: subscribed, or waiting for the customer to confirm by email (PENDING).
func isSubscribed(_ marketingState: String?) -> Bool {
    marketingState == "SUBSCRIBED" || marketingState == "PENDING"
}

extension Money {
    /// An amount above zero (Shopify sends "0.0" for none).
    func isPositive() -> Bool {
        guard let value = Double(amount), value.isFinite else { return false }
        return value > 0
    }
}

extension Optional where Wrapped == Money {
    /// An amount above zero; false when there is none.
    func isPositive() -> Bool { self?.isPositive() ?? false }
}

/// The store credit there is to spend: the balances above zero, one per currency.
func creditBalances(_ accounts: [StoreCreditAccount]) -> [Money] {
    accounts.map { $0.balance }.filter { $0.isPositive() }
}

/// An address as lines: Shopify's own formatting, or its parts when that is missing.
func addressLines(_ address: CustomerAddress) -> [String] {
    if !address.formatted.isEmpty { return address.formatted }
    return [
        [address.firstName, address.lastName].compactMap { $0 }.joined(separator: " "),
        address.company,
        address.address1,
        address.address2,
        [address.city, address.zoneCode ?? address.province, address.zip].compactMap { $0 }.joined(separator: " "),
        address.country ?? address.countryCode,
    ].compactMap { trimmedText($0) }
}

/// A country's name in the address form's picker: the store's `name` for it, else the device's own name for the ISO
/// `code` ("CA" is "Canada"; a store may send no names), else the code itself.
func countryName(_ code: String, _ name: String?, locale: Locale = .current) -> String {
    if let name = name, trimmedText(name) != nil { return name }
    return trimmedText(locale.localizedString(forRegionCode: code)) ?? code
}

/// The fields the address form checks itself.
enum AddressField {
    case address1, city, country
}

/// The address form as typed. `countryCode`: the country picked (ISO code), nil until one is.
struct AddressForm: Equatable {
    var firstName = ""
    var lastName = ""
    var company = ""
    var address1 = ""
    var address2 = ""
    var city = ""
    var zoneCode = ""
    var zip = ""
    var countryCode: String? = nil
    var phone = ""
    var isDefault = false

    /// What stops the form from being sent, by field; empty when it can go. Only what every country needs: Shopify checks
    /// the rest (a postal code's format, a province that exists, a phone number) and its messages show under the form.
    func errors() -> [AddressField: String] {
        var problems: [AddressField: String] = [:]
        if trimmedText(address1) == nil { problems[.address1] = "Enter an address" }
        if trimmedText(city) == nil { problems[.city] = "Enter a city" }
        if trimmedText(countryCode) == nil { problems[.country] = "Choose a country" }
        return problems
    }

    /// The form as the API's input, trimmed. A field left empty is left out, except one that `original` (the address being
    /// edited) had a value for: that one is sent empty, or the update would keep the old value. The province code goes in
    /// capitals and the phone number without its spaces and punctuation ("+1 613 555-0123" is "+16135550123").
    func toInput(_ original: CustomerAddress? = nil) -> CustomerAddressInput {
        func text(_ value: String, _ was: String?) -> String? {
            if let typed = trimmedText(value) { return typed }
            return trimmedText(was) == nil ? nil : ""
        }
        return CustomerAddressInput(
            firstName: text(firstName, original?.firstName),
            lastName: text(lastName, original?.lastName),
            company: text(company, original?.company),
            address1: text(address1, original?.address1),
            address2: text(address2, original?.address2),
            city: text(city, original?.city),
            zoneCode: text(zoneCode.uppercased(), original?.zoneCode),
            zip: text(zip, original?.zip),
            countryCode: trimmedText(countryCode)?.uppercased(),
            phoneNumber: text(phone.filter { !$0.isWhitespace && !"-().·".contains($0) }, original?.phoneNumber)
        )
    }

    /// The form for `address`; empty for a new one.
    static func of(_ address: CustomerAddress?) -> AddressForm {
        guard let address = address else { return AddressForm() }
        return AddressForm(
            firstName: address.firstName ?? "",
            lastName: address.lastName ?? "",
            company: address.company ?? "",
            address1: address.address1 ?? "",
            address2: address.address2 ?? "",
            city: address.city ?? "",
            zoneCode: address.zoneCode ?? "",
            zip: address.zip ?? "",
            countryCode: address.countryCode,
            phone: address.phoneNumber ?? "",
            isDefault: address.isDefault
        )
    }
}
