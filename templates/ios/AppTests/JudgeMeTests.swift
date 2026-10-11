import XCTest
@testable import ArgonStorefront

/// The `html` of what Judge.me's own storefront widget is answered with (Fixtures/JudgeMeReviews.json): two reviews.
private func tokenlessHtml() throws -> String {
    try XCTUnwrap(try fixture("JudgeMeReviews")["html"] as? String)
}

/// The same answer for a product nobody has reviewed.
private let noReviews = #"{"html":"<div class='jdgm-rev-widg__reviews'></div> <div class='jdgm-paginate' data-per-page='5' "#
    + #"data-url='https://api.judge.me/reviews/reviews_for_widget' style=\"display: none;\"></div>","total_count":0,"page":"1"}"#

/// The Judge.me widget's HTML (Fixtures/JudgeMeWidget.html has its real markup shape) read into reviews.
final class JudgeMeHtmlTests: XCTestCase {
    private func widget() throws -> String { try fixtureText("JudgeMeWidget", type: "html") }

    func testTheSummaryAndItsHistogram() throws {
        let page = JudgeMeHtml.parse(try widget(), page: 1, perPage: 5)
        let summary = try XCTUnwrap(page.summary)
        XCTAssertEqual(try XCTUnwrap(summary.average), 4.33, accuracy: 0.0001)
        XCTAssertEqual(summary.count, 12)
        XCTAssertEqual(summary.histogram, [5: 8, 4: 2, 3: 1, 2: 0, 1: 1], "the row that clears the filter has no rating and is skipped")
    }

    func testEachReview() throws {
        let page = JudgeMeHtml.parse(try widget(), page: 1, perPage: 5)
        XCTAssertEqual(page.reviews, [
            Review(
                id: "11111111-aaaa-4bbb-8ccc-000000000001",
                rating: 5,
                title: "Soft, warm & true to size",
                body: "Bought the olive one in medium. It's heavier than I expected \u{2014} in a good way.\nWashed it twice, no shrinking.",
                author: "Ada L.",
                verified: true,
                date: "2026-10-09T14:22:31Z",
                pictures: ["https://review-images.judgeme.com/example-store/1791654122__crewneck-olive__original.jpeg?quality=80&width=1024"],
                reply: nil
            ),
            Review(
                id: "11111111-aaaa-4bbb-8ccc-000000000002",
                rating: 4,
                title: "Great, sleeves a little long",
                body: "Lovely colour. The sleeves run long on me.",
                author: "Grace H.",
                verified: true,
                date: "2026-09-28T08:05:00Z",
                pictures: [],
                reply: "Thanks Grace! The small has a shorter sleeve \u{2014} happy to exchange it."
            ),
            Review(
                id: "11111111-aaaa-4bbb-8ccc-000000000003",
                rating: 1,
                title: nil,
                body: "Arrived late.",
                author: "Anonymous",
                verified: false,
                date: "2026-09-02T19:40:12Z",
                pictures: [],
                reply: nil
            ),
        ])
    }

    func testMoreFollowWhileTheTotalIsPastThePagesSoFar() throws {
        let html = try widget()
        XCTAssertTrue(JudgeMeHtml.parse(html, page: 1, perPage: 5).hasNextPage, "12 reviews, 5 seen")
        XCTAssertTrue(JudgeMeHtml.parse(html, page: 2, perPage: 5).hasNextPage, "10 seen")
        XCTAssertFalse(JudgeMeHtml.parse(html, page: 3, perPage: 5).hasNextPage, "15 would be seen")
        XCTAssertFalse(JudgeMeHtml.parse(html, page: 1, perPage: 12).hasNextPage)
        XCTAssertEqual(JudgeMeHtml.parse(html, page: 2, perPage: 5).page, 2)
    }

    func testMarkupWithoutReviewsIsAnEmptyPageNotAnError() {
        let empty = JudgeMeHtml.parse("<div class='jdgm-rev-widg' data-average-rating='0.00' data-number-of-reviews='0'></div>", page: 1, perPage: 5)
        XCTAssertEqual(empty, ReviewPage(summary: ReviewSummary(average: 0, count: 0, histogram: [:]), reviews: [], page: 1, hasNextPage: false))
        let unknown = JudgeMeHtml.parse("<p>Something else entirely</p>", page: 1, perPage: 5)
        XCTAssertEqual(unknown, ReviewPage(summary: nil, reviews: [], page: 1, hasNextPage: false))
        XCTAssertEqual(JudgeMeHtml.parse("", page: 1, perPage: 5).reviews, [])
    }

    func testAReviewNeedsOnlyItsIdAndRating() {
        let html = """
        <div class="jdgm-rev jdgm-divider-top" data-review-id="r1"><span class="jdgm-rev__rating" data-score="3"></span>
          <time class="jdgm-rev__timestamp" data-content="2026-01-02 03:04:05 UTC"></time></div>
        <div class='jdgm-rev ' data-review-id='r2'><b class='jdgm-rev__title'>No rating</b></div>
        <div class='jdgm-rev ' data-verified-buyer='true'><span class='jdgm-rev__rating' data-score='5'></span></div>
        """
        XCTAssertEqual(JudgeMeHtml.parse(html, page: 1, perPage: 5).reviews, [
            Review(id: "r1", rating: 3, date: "2026-01-02T03:04:05Z"),
        ], "double-quoted markup reads the same; the date falls back to data-content; reviews without a rating or an id are skipped")
    }

    func testTheTokenlessHtmlIsTheReviewBlocksWithoutASummary() throws {
        let page = JudgeMeHtml.parse(try tokenlessHtml(), page: 1, perPage: 5)
        XCTAssertNil(page.summary, "no average, no count, no histogram")
        XCTAssertEqual(page.reviews, [
            Review(
                id: "22222222-aaaa-4bbb-8ccc-000000000001",
                rating: 5,
                title: "Holds its shape & its colour",
                body: "Third month of wearing the navy one most days. The cuffs haven't stretched.\nWould buy it again.",
                author: "Mira K.",
                verified: true,
                date: "2026-10-06T09:15:42Z",
                pictures: ["https://review-images.judgeme.com/example-store/1791700031__crewneck-navy__original.jpeg?quality=80&width=1024"],
                reply: nil
            ),
            Review(
                id: "22222222-aaaa-4bbb-8ccc-000000000002",
                rating: 4,
                title: "Good, runs warm",
                body: "Nice weight. Too warm for me indoors.",
                author: "Tomas R.",
                verified: false,
                // its timestamp has `data-content` only
                date: "2026-09-19T17:48:03Z",
                pictures: [],
                reply: "Thanks Tomas! The lighter knit is back in spring."
            ),
        ])
        let none = try XCTUnwrap(try json(noReviews)["html"] as? String)
        XCTAssertEqual(JudgeMeHtml.parse(none, page: 1, perPage: 5).reviews, [], "the block around the reviews is not one of them")
    }

    func testHtmlBecomesPlainText() {
        XCTAssertEqual(JudgeMeHtml.text("<p>One</p><p>Two<br>Three<br/>Four</p>"), "One\nTwo\nThree\nFour")
        XCTAssertEqual(JudgeMeHtml.text("  <b>Fish</b> &amp; chips &lt;3 &gt; &quot;hi&quot; it&#39;s&nbsp;fine &mdash; ok "), "Fish & chips <3 > \"hi\" it's fine \u{2014} ok")
        XCTAssertEqual(JudgeMeHtml.text("caf&#233; &#x1F600; &unknown; &amp;lt;"), "caf\u{E9} \u{1F600} &unknown; &lt;", "numeric entities; unknown ones stay; nothing is decoded twice")
        XCTAssertEqual(JudgeMeHtml.text("<div></div>"), "")
    }

    func testTheNumericIdOfAGid() {
        XCTAssertEqual(JudgeMe.numericId("gid://shopify/Product/7982905098262"), "7982905098262")
        XCTAssertEqual(JudgeMe.numericId("gid://shopify/Product/42?foo=bar"), "42")
        XCTAssertEqual(JudgeMe.numericId("42"), "42")
        XCTAssertEqual(JudgeMe.numericId(""), "")
    }
}

/// What the Judge.me client sends (nothing touches the network: `StubProtocol` answers).
final class JudgeMeTests: XCTestCase {
    override func tearDown() {
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
        StubProtocol.status = 200
        super.tearDown()
    }

    private func client(_ body: String, status: Int = 200, token: String = "public-token") -> JudgeMe {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return JudgeMe(shopDomain: "shop.test", token: token, session: URLSession(configuration: configuration))
    }

    /// URLSession hands a protocol the body as a stream.
    private func sentBody(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testReviewsAskTheWidgetApiWithTheTokenInAHeader() async throws {
        let widget = try fixtureText("JudgeMeWidget", type: "html")
        let answer = String(decoding: try JSONSerialization.data(withJSONObject: ["widget": widget]), as: UTF8.self)
        let page = try await client(answer).reviews(productId: "gid://shopify/Product/7982905098262", page: 2, perPage: 5)
        XCTAssertEqual(page.reviews.count, 3)
        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.hasNextPage)

        let request = try XCTUnwrap(StubProtocol.lastRequest)
        let url = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(url.host, "api.judge.me")
        XCTAssertEqual(url.path, "/api/v1/widgets/product_review")
        var query: [String: String] = [:]
        for item in url.queryItems ?? [] { query[item.name] = item.value }
        XCTAssertEqual(query, ["shop_domain": "shop.test", "external_id": "7982905098262", "page": "2", "per_page": "5"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Token"), "public-token")
    }

    func testAnAnswerWithoutAWidgetOrAnHttpErrorThrows() async {
        do {
            _ = try await client(#"{"error":"nope"}"#).reviews(productId: "gid://shopify/Product/1")
            XCTFail("expected a decoding error")
        } catch ArgonAPIError.decoding {
        } catch {
            XCTFail("\(error)")
        }
        do {
            _ = try await client("", status: 401).reviews(productId: "gid://shopify/Product/1")
            XCTFail("expected an HTTP error")
        } catch ArgonAPIError.http(let status) {
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSubmitPostsTheReviewWithoutAToken() async throws {
        try await client("{}").submit(
            productId: "gid://shopify/Product/7982905098262",
            name: "Ada L.",
            email: "ada@example.com",
            rating: 5,
            title: "Soft",
            body: "Warm too."
        )
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.judge.me/api/v1/reviews")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Token"))
        let sent = try sentBody(request)
        XCTAssertEqual(sent["shop_domain"] as? String, "shop.test")
        XCTAssertEqual(sent["platform"] as? String, "shopify")
        XCTAssertEqual(sent["id"] as? Int, 7982905098262)
        XCTAssertEqual(sent["name"] as? String, "Ada L.")
        XCTAssertEqual(sent["email"] as? String, "ada@example.com")
        XCTAssertEqual(sent["rating"] as? Int, 5)
        XCTAssertEqual(sent["title"] as? String, "Soft")
        XCTAssertEqual(sent["body"] as? String, "Warm too.")
        XCTAssertEqual(sent.count, 8)
    }

    func testTheDemoStoresSampleIsOnePageAndSendsNothing() async throws {
        let widget = try fixtureText("JudgeMeWidget", type: "html")
        // a session that would fail the test if anything were sent
        StubProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let sample = JudgeMe(shopDomain: "mock.shop", token: "", session: URLSession(configuration: configuration), sample: { widget })
        XCTAssertTrue(sample.isSample)
        XCTAssertFalse(client("{}").isSample)

        let first = try await sample.reviews(productId: "gid://shopify/Product/1")
        XCTAssertEqual(first.reviews.count, 3)
        XCTAssertEqual(first.summary?.count, 12)
        XCTAssertFalse(first.hasNextPage, "the sample has no second page to load")
        let second = try await sample.reviews(productId: "gid://shopify/Product/1", page: 2)
        XCTAssertTrue(second.reviews.isEmpty)

        try await sample.submit(productId: "gid://shopify/Product/1", name: "Ada", email: "ada@example.com", rating: 5, title: "Lovely", body: "Soft")
        XCTAssertNil(StubProtocol.lastRequest)
        XCTAssertFalse(sample.isTokenless, "a sample is not a store without a token")
    }

    // MARK: Without a token

    func testWithoutATokenTheReviewsComeFromTheWidgetsOwnEndpoint() async throws {
        XCTAssertFalse(client("{}").isTokenless)
        let judgeMe = client(try fixtureText("JudgeMeReviews"), token: "")
        XCTAssertTrue(judgeMe.isTokenless)

        let product = "gid://shopify/Product/7982905098262"
        let page = try await judgeMe.reviews(productId: product)
        XCTAssertEqual(page.summary, ReviewSummary(average: nil, count: 2, histogram: [:]), "the count alone: no average, no breakdown")
        XCTAssertEqual(page.reviews, JudgeMeHtml.parse(try tokenlessHtml(), page: 1, perPage: 5).reviews)
        XCTAssertEqual(page.reviews.count, 2)
        XCTAssertEqual(page.page, 1)
        XCTAssertFalse(page.hasNextPage)

        let request = try XCTUnwrap(StubProtocol.lastRequest)
        let url = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(url.host, "api.judge.me")
        XCTAssertEqual(url.path, "/reviews/reviews_for_widget")
        var query: [String: String] = [:]
        for item in url.queryItems ?? [] { query[item.name] = item.value }
        XCTAssertEqual(query, [
            "url": "shop.test", "shop_domain": "shop.test", "platform": "shopify", "page": "1", "per_page": "5", "product_id": "7982905098262",
        ])
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Token"))

        let first = try await judgeMe.reviews(productId: product, page: 1, perPage: 1)
        XCTAssertTrue(first.hasNextPage, "2 reviews, 1 a page")
        let second = try await judgeMe.reviews(productId: product, page: 2, perPage: 1)
        XCTAssertFalse(second.hasNextPage)

        // writing a review never needed the token
        try await judgeMe.submit(productId: product, name: "Ada", email: "ada@example.com", rating: 5, title: "Lovely", body: "Soft")
        let sent = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://api.judge.me/api/v1/reviews")
    }

    func testAProductWithoutReviewsIsAnEmptyPageAndTheNextProductIsStillAskedFor() async throws {
        let judgeMe = client(noReviews, token: "")
        let page = try await judgeMe.reviews(productId: "gid://shopify/Product/1")
        XCTAssertEqual(page, ReviewPage(summary: ReviewSummary(average: nil, count: 0, histogram: [:]), reviews: [], page: 1, hasNextPage: false))
        StubProtocol.lastRequest = nil
        _ = try await judgeMe.reviews(productId: "gid://shopify/Product/2")
        XCTAssertNotNil(StubProtocol.lastRequest, "no reviews is an answer too: the next product is asked for")
    }

    func testAnyOtherAnswerTurnsTheTokenlessEndpointOffForTheRunWithoutAnError() async throws {
        let answers: [(status: Int, body: String)] = [
            (404, #"{"error":"Not found"}"#),
            (500, ""),
            (200, "<html>Not here</html>"),
            (200, "[]"),
            (200, #"{"widget":"<div></div>"}"#),
            (200, #"{"html":"<div class='jdgm-rev-widg__reviews'></div>"}"#),
            (200, #"{"html":null,"total_count":0}"#),
            (200, #"{"html":"<div class='jdgm-rev-widg__reviews'></div>","total_count":"many"}"#),
        ]
        for answer in answers {
            let what = "\(answer.status) \(answer.body)"
            let judgeMe = client(answer.body, status: answer.status, token: "")
            let first = try await judgeMe.reviews(productId: "gid://shopify/Product/1")
            XCTAssertEqual(first, ReviewPage(summary: nil, reviews: [], page: 1, hasNextPage: false), what)
            XCTAssertNotNil(StubProtocol.lastRequest, what)
            StubProtocol.lastRequest = nil
            let second = try await judgeMe.reviews(productId: "gid://shopify/Product/2", page: 2)
            XCTAssertEqual(second, ReviewPage(summary: nil, reviews: [], page: 2, hasNextPage: false), what)
            XCTAssertNil(StubProtocol.lastRequest, "\(what): asked once, then left alone")
        }
    }

    func testBeingOfflineIsNoAnswerTheNextCallAsksAgain() async throws {
        let judgeMe = client(try fixtureText("JudgeMeReviews"), token: "")
        StubProtocol.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await judgeMe.reviews(productId: "gid://shopify/Product/1")
            XCTFail("expected a network error")
        } catch ArgonAPIError.network {
        } catch {
            XCTFail("\(error)")
        }
        StubProtocol.failure = nil
        let page = try await judgeMe.reviews(productId: "gid://shopify/Product/1")
        XCTAssertEqual(page.reviews.count, 2)
    }
}
