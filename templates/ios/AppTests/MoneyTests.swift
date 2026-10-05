import XCTest
@testable import ArgonStorefront

final class MoneyTests: XCTestCase {
    func testDisplaysTheAmountInItsCurrency() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(Money(amount: "25.0", currencyCode: "USD").display(locale: us), "$25.00")
        XCTAssertEqual(Money(amount: "1234.5", currencyCode: "USD").display(locale: us), "$1,234.50")
    }

    func testUnknownCurrencyFallsBackToAmountAndCode() {
        XCTAssertEqual(Money(amount: "5.0", currencyCode: "???").display(), "5.0 ???")
    }
}
