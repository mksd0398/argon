import XCTest
@testable import ArgonStorefront

final class RemoteSettingsTests: XCTestCase {
    private let full = """
    {
      "version": 1,
      "brand": { "accent": "#1F6FEB" },
      "home": { "template": "beauty" },
      "collection": { "template": "bottom" },
      "onboarding": { "enabled": false, "pages": [ { "heading": "Hello", "text": "Silks since 1928" }, { "heading": "", "text": "" } ] },
      "cart": { "freeShippingThreshold": 50 },
      "product": { "showVendor": true },
      "reviews": { "judgeMePublicToken": "jm-1" },
      "analytics": { "metaAppId": "123", "serverPurchase": true }
    }
    """

    private func settings(_ json: String) -> RemoteSettings? { RemoteSettings(json: Data(json.utf8)) }

    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: Decoding

    func testReadsEverySetting() throws {
        let read = try XCTUnwrap(settings(full))
        XCTAssertEqual(read.accent, "#1F6FEB")
        XCTAssertEqual(read.homeTemplate, .beauty)
        XCTAssertEqual(read.collectionTemplate, .bottom)
        XCTAssertEqual(read.onboarding, false)
        XCTAssertEqual(read.pages, [RemoteSettings.Page(heading: "Hello", text: "Silks since 1928"), RemoteSettings.Page(heading: "", text: "")])
        XCTAssertEqual(read.freeShippingThreshold, 50)
        XCTAssertEqual(read.showVendor, true)
        XCTAssertEqual(read.judgeMeToken, "jm-1")
    }

    func testAFieldOfTheWrongTypeOrAnInvalidValueIsDroppedOnItsOwn() throws {
        let read = try XCTUnwrap(settings("""
        {
          "brand": { "accent": "blue" },
          "home": { "template": "grocery" },
          "collection": { "template": "sideways" },
          "onboarding": { "enabled": "yes", "pages": [ "not a page", { "heading": 3, "text": "Second" } ] },
          "cart": { "freeShippingThreshold": "50" },
          "product": { "showVendor": 1 },
          "reviews": { "judgeMePublicToken": "  " },
          "extra": { "anything": [1, 2] }
        }
        """))
        XCTAssertNil(read.accent)
        XCTAssertEqual(read.homeTemplate, .grocery, "the valid field next to them still applies")
        XCTAssertNil(read.collectionTemplate)
        XCTAssertNil(read.onboarding)
        XCTAssertEqual(read.pages, [RemoteSettings.Page(), RemoteSettings.Page(text: "Second")], "each page keeps its place")
        XCTAssertNil(read.freeShippingThreshold)
        XCTAssertNil(read.showVendor)
        XCTAssertNil(read.judgeMeToken)

        XCTAssertNil(settings(##"{"brand":{"accent":"#1F6FE"}}"##)?.accent, "#RRGGBB only")
        XCTAssertNil(settings(#"{"cart":{"freeShippingThreshold":-5}}"#)?.freeShippingThreshold)
        XCTAssertNil(settings(#"{"home":"fashion"}"#)?.homeTemplate, "a section that isn't an object")
        XCTAssertEqual(settings(#"{"home":{"template":" B2B "}}"#)?.homeTemplate, .b2b)
    }

    func testAnEmptyObjectIsSettingsWithNothingSet() {
        XCTAssertEqual(settings("{}"), RemoteSettings())
    }

    func testAnythingButAJSONObjectIsNoSettings() {
        for garbage in ["", "not json", "[]", "[{}]", "\"text\"", "42", "null", "{\"home\":"] {
            XCTAssertNil(settings(garbage), garbage)
        }
    }

    // MARK: Overrides

    func testTheFreeShippingThreshold() {
        XCTAssertEqual(settings(#"{"cart":{"freeShippingThreshold":75.5}}"#)?.freeShippingThreshold(over: 40), 75.5)
        XCTAssertNil(settings(#"{"cart":{"freeShippingThreshold":0}}"#)?.freeShippingThreshold(over: 40), "zero: no progress bar")
        XCTAssertEqual(settings("{}")?.freeShippingThreshold(over: 40), 40, "absent: the built-in one")
        XCTAssertNil(settings("{}")?.freeShippingThreshold(over: nil))
    }

    func testTheWelcomePagesTakeTheMerchantsNonEmptyWords() throws {
        let brand = Brand(name: "Maison", logo: nil, cover: nil, accent: nil, hosts: [])
        let words = try XCTUnwrap(settings(full)?.pages)
        let pages = Onboarding.pages(brand: brand, template: .fashion, words: words, image: { _, _ in nil })
        XCTAssertEqual(pages.map { $0.heading }, ["Hello", "Find it fast", "Checkout in a few taps"])
        XCTAssertEqual(pages.map { $0.text }, [
            "Silks since 1928",
            "Search, filter and save what you love.",
            "Track your orders and returns from your account.",
        ])
        let more = Array(repeating: RemoteSettings.Page(heading: "X", text: "Y"), count: 5)
        XCTAssertEqual(Onboarding.pages(brand: brand, template: .fashion, words: more, image: { _, _ in nil }).count, 3)
    }

    @MainActor
    func testTheMerchantsAccentReplacesTheShops() async throws {
        let shop = try await StubServer().storefront().shop()
        let own = Brand(shop: shop, configDomain: "mock.shop").accent
        XCTAssertEqual(Brand(shop: shop, configDomain: "mock.shop", accent: nil).accent, own)
        XCTAssertEqual(Brand(shop: shop, configDomain: "mock.shop", accent: "#1F6FEB").accent, "#1F6FEB")
    }

    // MARK: The cache

    private func store(status: Int = 200, body: String = "", fails: Bool = false) -> RemoteSettingsStore {
        RemoteSettingsStore(file: directory.appending(path: "remote-settings.json"), fetch: { request in
            if fails { throw URLError(.timedOut) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        })
    }

    private let url = URL(string: "https://krypton.test/v1/settings/mock.shop")!

    func testAFetchIsKeptForTheNextLaunch() async throws {
        XCTAssertNil(store().load(), "nothing before the first fetch")
        await store(body: full).refresh(from: url)
        XCTAssertEqual(store().load(), settings(full))
    }

    func testAFailedFetchKeepsTheCache() async throws {
        await store(body: full).refresh(from: url)
        await store(fails: true).refresh(from: url)
        await store(status: 500, body: #"{"home":{"template":"b2b"}}"#).refresh(from: url)
        await store(body: "<html>").refresh(from: url)
        await store(body: "[]").refresh(from: url)
        XCTAssertEqual(store().load(), settings(full))
    }

    func testTheFetchAsksForTheURLWithAShortTimeout() async throws {
        let asked = Asked()
        let store = RemoteSettingsStore(file: directory.appending(path: "remote-settings.json"), fetch: { request in
            asked.request = request
            throw URLError(.notConnectedToInternet)
        })
        await store.refresh(from: url)
        XCTAssertEqual(asked.request?.url, url)
        XCTAssertEqual(asked.request?.httpMethod, "GET")
        XCTAssertEqual(asked.request?.timeoutInterval, 5)
    }

    func testAnUnreadableCacheIsNoSettings() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: directory.appending(path: "remote-settings.json"))
        XCTAssertNil(store().load())
    }
}

/// The request a test's fetch was given.
private final class Asked: @unchecked Sendable {
    var request: URLRequest? = nil
}
