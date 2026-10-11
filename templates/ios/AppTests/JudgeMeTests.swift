import XCTest
@testable import ArgonStorefront

/// The Judge.me widget's HTML (Fixtures/JudgeMeWidget.html has its real markup shape) read into reviews.
final class JudgeMeHtmlTests: XCTestCase {
    private func widget() throws -> String { try fixtureText("JudgeMeWidget", type: "html") }

    func testTheSummaryAndItsHistogram() throws {
        let page = JudgeMeHtml.parse(try widget(), page: 1, perPage: 5)
        let summary = try XCTUnwrap(page.summary)
        XCTAssertEqual(summary.average, 4.33, accuracy: 0.0001)
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

    private func client(_ body: String, status: Int = 200) -> JudgeMe {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return JudgeMe(shopDomain: "shop.test", token: "public-token", session: URLSession(configuration: configuration))
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
}
