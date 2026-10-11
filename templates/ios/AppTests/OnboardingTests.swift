import XCTest
@testable import ArgonStorefront

final class OnboardingTests: XCTestCase {
    private let suite = UUID().uuidString

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: The pages

    private let stock: (HomeTemplate, Int) -> String? = { template, index in "file:///stock/home-\(template.rawValue)-\(index).jpg" }

    private func brand(shortDescription: String? = nil, slogan: String? = nil) -> Brand {
        Brand(name: "Maison", logo: nil, cover: nil, accent: nil, hosts: [], shortDescription: shortDescription, slogan: slogan)
    }

    /// The first page's text for `brand`.
    private func welcome(_ brand: Brand) -> String {
        Onboarding.pages(brand: brand, template: .fashion, image: stock)[0].text
    }

    func testThreePagesOverTheTemplatesStockBanners() {
        let pages = Onboarding.pages(brand: brand(), template: .grocery, image: stock)
        XCTAssertEqual(pages.map { $0.heading }, ["Welcome to Maison", "Find it fast", "Checkout in a few taps"])
        XCTAssertEqual(pages.map { $0.text }, [
            "Everything from Maison, in one app.",
            "Search, filter and save what you love.",
            "Track your orders and returns from your account.",
        ])
        XCTAssertEqual(pages.map { $0.image }, [
            "file:///stock/home-grocery-1.jpg", "file:///stock/home-grocery-2.jpg", "file:///stock/home-grocery-3.jpg",
        ])
        XCTAssertEqual(Onboarding.pages(brand: brand(), template: .b2b, image: stock)[1].image, "file:///stock/home-b2b-2.jpg")
    }

    func testTheWelcomeIsInTheBrandsOwnWordsWhenItHasThem() {
        XCTAssertEqual(welcome(brand(shortDescription: " Slow fashion, made in Lyon ", slogan: "Wear it longer")), "Slow fashion, made in Lyon")
        XCTAssertEqual(welcome(brand(shortDescription: "  ", slogan: "Wear it longer")), "Wear it longer", "the slogan when there is no description")
        XCTAssertEqual(welcome(brand(shortDescription: "", slogan: " ")), "Everything from Maison, in one app.")
    }

    @MainActor
    func testTheFixtureShopWelcomesByItsName() async throws {
        // mock.shop's brand has neither a short description nor a slogan
        let shop = try await StubServer().storefront().shop()
        let first = Onboarding.pages(brand: Brand(shop: shop, configDomain: "mock.shop"), template: .fashion, image: stock)[0]
        XCTAssertEqual(first.heading, "Welcome to Mock.shop")
        XCTAssertEqual(first.text, "Everything from Mock.shop, in one app.")
    }

    // MARK: The store

    /// A store on this test's defaults: a new one over the same defaults is the app after a restart.
    @MainActor
    private func store() -> OnboardingStore { OnboardingStore(defaults: UserDefaults(suiteName: suite)!) }

    @MainActor
    func testAFirstLaunchHasNotSeenTheWelcomeAndFinishingItIsRemembered() {
        let first = store()
        XCTAssertFalse(first.done)
        first.finish()
        XCTAssertTrue(first.done)

        let again = store()
        XCTAssertTrue(again.done, "not shown on the second launch")
        again.reset()
        XCTAssertFalse(again.done, "the debug row shows it again")
        XCTAssertFalse(store().done, "and on the launch after that")
    }
}
