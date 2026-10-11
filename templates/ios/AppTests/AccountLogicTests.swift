import XCTest
@testable import ArgonStorefront

/// The account pages' rules (Android's AccountLogicTest, case for case).
final class AccountLogicTests: XCTestCase {
    // the contract fixtures: the sample account
    @MainActor
    private func account() -> CustomerAccountAPI {
        StubServer().customerAccount()
    }

    /// An address with only these parts, and none of Shopify's own formatting.
    private func address(
        firstName: String? = nil,
        address1: String? = nil,
        city: String? = nil,
        province: String? = nil,
        zip: String? = nil,
        countryCode: String? = nil
    ) -> CustomerAddress {
        CustomerAddress(
            id: "a", firstName: firstName, lastName: nil, company: nil, address1: address1, address2: nil, city: city,
            province: province, zoneCode: nil, zip: zip, country: nil, countryCode: countryCode, phoneNumber: nil, formatted: []
        )
    }

    // MARK: The avatar and the name

    func testInitialsAreTheFirstLetterOfEachName() {
        XCTAssertEqual(initials("Ada", "Lovelace", "ada@example.com"), "AL")
        XCTAssertEqual(initials(" ada ", "lovelace", nil), "AL")
        XCTAssertEqual(initials("Ada", nil, "x@example.com"), "A", "one name")
        XCTAssertEqual(initials("", "Lovelace", nil), "L")
    }

    func testWithoutANameTheEmailGivesTheInitialAndWithNeitherThereIsNone() {
        XCTAssertEqual(initials(nil, nil, "grace@example.com"), "G")
        XCTAssertEqual(initials(" ", "", "grace@example.com"), "G")
        XCTAssertNil(initials(nil, nil, nil))
        XCTAssertNil(initials("", "", " "))
        XCTAssertNil(initials("-", nil, nil), "a name that starts with a symbol gives no letter")
    }

    @MainActor
    func testACustomerGoesByTheirNameThenTheDisplayNameThenTheEmail() async throws {
        let email = CustomerEmailAddress(emailAddress: "ada@example.com", marketingState: nil)
        XCTAssertEqual(
            accountName(Customer(id: "c", firstName: "Ada", lastName: "Lovelace", displayName: "Ada L.", emailAddress: email)),
            "Ada Lovelace"
        )
        XCTAssertEqual(
            accountName(Customer(id: "c", firstName: nil, lastName: nil, displayName: "ada@example.com", emailAddress: email)),
            "ada@example.com"
        )
        XCTAssertEqual(accountName(Customer(id: "c", firstName: " ", lastName: nil, displayName: "", emailAddress: email)), "ada@example.com")
        XCTAssertNil(accountName(Customer(id: "c", firstName: nil, lastName: nil, displayName: "")), "a customer with nothing to go by")
        let sample = try await account().customer()
        XCTAssertEqual(accountName(sample), "Ada Lovelace", "the sample customer")
    }

    // MARK: Email offers and store credit

    func testEmailOffersAreOnWhenSubscribedOrWaitingForConfirmation() {
        XCTAssertTrue(isSubscribed("SUBSCRIBED"))
        XCTAssertTrue(isSubscribed("PENDING"))
        XCTAssertFalse(isSubscribed("UNSUBSCRIBED"))
        XCTAssertFalse(isSubscribed("NOT_SUBSCRIBED"))
        XCTAssertFalse(isSubscribed(nil))
    }

    @MainActor
    func testStoreCreditShowsOnlyBalancesAboveZero() async throws {
        let credit = Money(amount: "25.0", currencyCode: "CAD")
        let accounts = [
            StoreCreditAccount(id: "a", balance: credit),
            StoreCreditAccount(id: "b", balance: Money(amount: "0.0", currencyCode: "USD")),
            StoreCreditAccount(id: "c", balance: Money(amount: "n/a", currencyCode: "EUR")),
        ]
        XCTAssertEqual(creditBalances(accounts), [credit])
        XCTAssertEqual(creditBalances([]), [])
        let sample = try await account().storeCredit()
        XCTAssertEqual(creditBalances(sample), [credit], "the sample account has credit")
        let none: Money? = nil
        XCTAssertFalse(none.isPositive())
    }

    // MARK: Addresses

    @MainActor
    func testAnAddressReadsAsShopifyFormatsItElseFromItsParts() async throws {
        let addresses = try await account().addresses().items
        XCTAssertEqual(addressLines(addresses[0]), ["Ada Lovelace", "150 Elgin St", "Suite 400", "Ottawa ON K2P 1L4", "Canada"])
        let bare = address(firstName: "Ada", address1: "1 Front St W", city: "Toronto", province: "Ontario", zip: "M5J 2X5", countryCode: "CA")
        XCTAssertEqual(addressLines(bare), ["Ada", "1 Front St W", "Toronto Ontario M5J 2X5", "CA"])
        XCTAssertEqual(addressLines(address()), [])
    }

    func testTheFormNeedsAnAddressACityAndACountry() {
        XCTAssertEqual(
            AddressForm(firstName: "Ada", address1: "  ", countryCode: "").errors(),
            [.address1: "Enter an address", .city: "Enter a city", .country: "Choose a country"]
        )
        XCTAssertEqual(AddressForm(address1: "1 Front St W", countryCode: "CA").errors(), [.city: "Enter a city"])
        XCTAssertEqual(AddressForm(address1: "1 Front St W", city: "Toronto", countryCode: "CA").errors(), [:])
    }

    func testANewAddressLeavesOutWhatWasLeftEmpty() {
        let form = AddressForm(
            firstName: " Ada ", lastName: "Lovelace", address1: "1 Front St W", city: "Toronto", zoneCode: "on", zip: " M5J 2X5 ",
            countryCode: "ca", phone: "+1 (613) 555-0123", isDefault: true
        )
        XCTAssertEqual(
            form.toInput(),
            CustomerAddressInput(
                firstName: "Ada", lastName: "Lovelace", company: nil, address1: "1 Front St W", address2: nil, city: "Toronto",
                zoneCode: "ON", zip: "M5J 2X5", countryCode: "CA", phoneNumber: "+16135550123"
            )
        )
    }

    @MainActor
    func testAnEditSendsAClearedFieldEmptySoItIsNotKept() async throws {
        let original = try await account().addresses().items[0] // has "Suite 400" and a phone number, no company
        var form = AddressForm.of(original)
        form.address2 = ""
        form.phone = " "
        form.city = "Gatineau"
        let input = form.toInput(original)
        XCTAssertEqual(input.address2, "", "cleared: sent empty")
        XCTAssertEqual(input.phoneNumber, "")
        XCTAssertNil(input.company, "was empty and still is: left out")
        XCTAssertEqual(input.city, "Gatineau")
        XCTAssertEqual(input.address1, "150 Elgin St")
        XCTAssertEqual(input.countryCode, "CA")
    }

    @MainActor
    func testTheFormStartsFromTheAddressBeingEdited() async throws {
        let addresses = try await account().addresses().items
        XCTAssertEqual(
            AddressForm.of(addresses[0]),
            AddressForm(
                firstName: "Ada", lastName: "Lovelace", company: "", address1: "150 Elgin St", address2: "Suite 400", city: "Ottawa",
                zoneCode: "ON", zip: "K2P 1L4", countryCode: "CA", phone: "+16135550123", isDefault: true
            )
        )
        XCTAssertFalse(AddressForm.of(addresses[1]).isDefault, "the second address isn't the default")
        XCTAssertEqual(AddressForm.of(nil), AddressForm())
        XCTAssertEqual(AddressForm.of(addresses[0]).toInput(addresses[0]).address2, "Suite 400", "an unchanged form changes nothing it had")
    }
}
