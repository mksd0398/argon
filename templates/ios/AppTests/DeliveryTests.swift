import XCTest
@testable import App

final class DeliveryTests: XCTestCase {
    private func address(zip: String?, city: String? = nil, countryCode: String? = nil) -> CustomerAddress {
        CustomerAddress(
            id: "a", firstName: nil, lastName: nil, company: nil, address1: nil, address2: nil, city: city,
            province: nil, zoneCode: nil, zip: zip, country: nil, countryCode: countryCode, phoneNumber: nil, formatted: []
        )
    }

    func testDecodesKryptonsAnswer() throws {
        let e = try XCTUnwrap(DeliveryEstimate(json: Data(#"{"pincode":"560001","serviceable":true,"cod":false,"date":"2026-10-24","city":"Bengaluru"}"#.utf8)))
        XCTAssertEqual(e, DeliveryEstimate(pincode: "560001", serviceable: true, cod: false, date: DeliveryEstimate.day("2026-10-24"), city: "Bengaluru"))
        let off = try XCTUnwrap(DeliveryEstimate(json: Data(#"{"pincode":"744101","serviceable":false,"cod":false,"date":null}"#.utf8)))
        XCTAssertFalse(off.serviceable)
        XCTAssertNil(off.date)
        XCTAssertNil(DeliveryEstimate(json: Data(#"{"pincode":"1","serviceable":true,"cod":null}"#.utf8))?.cod, "cod unknown")
        XCTAssertNil(DeliveryEstimate(json: Data(#"{"serviceable":true}"#.utf8)))
        XCTAssertNil(DeliveryEstimate(json: Data("not json".utf8)))
    }

    func testLinesSayTheDateCodOrNoDelivery() {
        let date = DeliveryEstimate.day("2026-10-22")
        let english = Locale(identifier: "en_GB")
        XCTAssertEqual(
            deliveryLines(DeliveryEstimate(pincode: "560001", serviceable: true, cod: true, date: date, city: nil), locale: english),
            [DeliveryLine(text: "Delivery by Thu, 22 Oct", tone: .good), DeliveryLine(text: "Cash on delivery available", tone: .muted)]
        )
        XCTAssertEqual(
            deliveryLines(DeliveryEstimate(pincode: "560001", serviceable: true, cod: nil, date: date, city: nil), locale: english),
            [DeliveryLine(text: "Delivery by Thu, 22 Oct", tone: .good)]
        )
        XCTAssertEqual(
            deliveryLines(DeliveryEstimate(pincode: "744101", serviceable: false, cod: false, date: nil, city: nil)),
            [DeliveryLine(text: "Not delivering to 744101 yet", tone: .bad)]
        )
    }

    func testLocationFromAnIndianAddressOnly() {
        XCTAssertEqual(DeliveryLocation(address: address(zip: "560 001", city: " Bengaluru ", countryCode: "IN")), DeliveryLocation(pincode: "560001", city: "Bengaluru"))
        XCTAssertEqual(DeliveryLocation(address: address(zip: "560001")), DeliveryLocation(pincode: "560001"))
        XCTAssertNil(DeliveryLocation(address: address(zip: "10001", countryCode: "US")))
        XCTAssertNil(DeliveryLocation(address: address(zip: "060001", countryCode: "IN")))
        XCTAssertEqual(DeliveryLocation(pincode: "560001", city: "Bengaluru").label, "560001 · Bengaluru")
        XCTAssertEqual(DeliveryLocation(pincode: "560001", city: " ").label, "560001")
    }

    func testEndpointIsNextToTheSettings() {
        XCTAssertEqual(deliveryEndpoint("https://k.web.app/v1/settings/shop.myshopify.com"), "https://k.web.app/v1/delivery/shop.myshopify.com")
        XCTAssertEqual(deliveryEndpoint(""), "")
        XCTAssertEqual(deliveryEndpoint("https://elsewhere.test/settings.json"), "")
    }

    func testRemoteSettingsReadDelivery() {
        XCTAssertEqual(RemoteSettings(json: Data(#"{"delivery":{"enabled":true}}"#.utf8))?.delivery, true)
        XCTAssertNil(RemoteSettings(json: Data(#"{"delivery":{"enabled":"yes"}}"#.utf8))?.delivery)
        XCTAssertNil(RemoteSettings(json: Data("{}".utf8))?.delivery)
    }

    @MainActor
    func testStoreKeepsTheLocationAndAsksOncePerPincode() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DeliveryTests"))
        defaults.removePersistentDomain(forName: "DeliveryTests")
        let asked = Asked()
        let store = DeliveryStore(defaults: defaults, url: "https://k.test/v1/delivery/s") { request in
            let pin = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
            await asked.add(pin)
            let body = #"{"pincode":"\#(pin)","serviceable":true,"cod":true,"date":"2026-10-24"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        store.prefill(address(zip: "110001", city: "Delhi"))
        XCTAssertEqual(store.location, DeliveryLocation(pincode: "110001", city: "Delhi"))
        store.prefill(address(zip: "560001"))
        XCTAssertEqual(store.location?.pincode, "110001", "prefill never replaces a chosen location")
        store.set(DeliveryLocation(pincode: "560001"))
        XCTAssertEqual(DeliveryStore(defaults: defaults, url: "").location, DeliveryLocation(pincode: "560001"), "kept on the device")
        let first = await store.estimate("560001")
        XCTAssertEqual(first?.date, DeliveryEstimate.day("2026-10-24"))
        _ = await store.estimate("560001")
        let pins = await asked.pins
        XCTAssertEqual(pins, ["560001"])
        let none = await DeliveryStore(defaults: defaults, url: "").estimate("560001")
        XCTAssertNil(none)
    }
}

private actor Asked {
    var pins: [String] = []
    func add(_ pin: String) { pins.append(pin) }
}
