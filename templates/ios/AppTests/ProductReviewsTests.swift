import XCTest
@testable import ArgonStorefront

private struct Offline: Error {}

/// Seven reviews, five a page; review 5 shows again on page 2 (a new review came in between the two calls).
private final class Pages {
    var asked: [Int] = []
    var failing = false

    func load(_ page: Int) throws -> ReviewPage {
        asked.append(page)
        if failing { throw Offline() }
        let ids = page == 1 ? 1...5 : 5...7
        let reviews = ids.map { Review(id: "\($0)", rating: 5, body: "Body \($0)", author: "Ada", verified: true) }
        return ReviewPage(summary: ReviewSummary(average: 4.6, count: 7, histogram: [5: 7]), reviews: reviews, page: page, hasNextPage: page == 1)
    }
}

final class ProductReviewsTests: XCTestCase {
    // MARK: The write-a-review form

    private let valid = ReviewForm(rating: 5, title: "", body: "Soft and warm.", name: "Ada", email: "ada@example.com")

    /// `valid` with one field changed.
    private func form(_ change: (inout ReviewForm) -> Void) -> ReviewForm {
        var form = valid
        change(&form)
        return form
    }

    func testAReviewWithARatingABodyANameAndAnEmailCanBeSent() {
        XCTAssertTrue(validate(valid).isEmpty)
        XCTAssertTrue(validate(form { $0.title = "Love it" }).isEmpty, "the title is optional")
        XCTAssertTrue(validate(form { $0.email = " ada@example.com " }).isEmpty, "spaces around the email are not the shopper's mistake")
    }

    func testAnEmptyFormSaysWhatIsMissingFieldByField() {
        XCTAssertEqual(
            validate(ReviewForm()),
            ReviewFormErrors(rating: "Choose a rating", body: "Write your review", name: "Enter your name", email: "Enter a valid email address")
        )
        XCTAssertFalse(validate(ReviewForm()).isEmpty)
    }

    func testTheRatingMustBeChosen() {
        XCTAssertEqual(validate(form { $0.rating = 0 }), ReviewFormErrors(rating: "Choose a rating"))
        XCTAssertEqual(validate(form { $0.rating = 6 }), ReviewFormErrors(rating: "Choose a rating"))
        for stars in 1...5 { XCTAssertNil(validate(form { $0.rating = stars }).rating) }
    }

    func testTheBodyAndTheNameMustNotBeBlank() {
        XCTAssertEqual(validate(form { $0.body = "  \n " }), ReviewFormErrors(body: "Write your review"))
        XCTAssertEqual(validate(form { $0.name = " " }), ReviewFormErrors(name: "Enter your name"))
    }

    func testTheEmailMustBePlausible() {
        for email in ["ada@example.com", "a@b.co", "first.last+tag@mail.example.org"] {
            XCTAssertNil(validate(form { $0.email = email }).email, email)
        }
        for email in ["", "ada", "ada@", "ada@example", "@example.com", "ada@.com", "ada@example.", "a da@example.com", "ada@@example.com"] {
            XCTAssertEqual(validate(form { $0.email = email }).email, "Enter a valid email address", email)
        }
    }

    // MARK: The summary

    private func summary(_ count: Int, _ histogram: [Int: Int] = [:]) -> ReviewSummary {
        ReviewSummary(average: 4.6, count: count, histogram: histogram)
    }

    func testTheTitlesStarsComeFromTheReviewsElseFromTheRatingMetafields() {
        let reviewed = shownRating(summary(128), rating: 4.0, ratingCount: 10)
        XCTAssertEqual(reviewed?.value, 4.6)
        XCTAssertEqual(reviewed?.count, 128)
        let unloaded = shownRating(summary(0), rating: 4.0, ratingCount: 10)
        XCTAssertEqual(unloaded?.value, 4.0, "no reviews loaded: the metafields")
        XCTAssertEqual(unloaded?.count, 10)
        let uncounted = shownRating(nil, rating: 4.0, ratingCount: nil)
        XCTAssertEqual(uncounted?.value, 4.0)
        XCTAssertNotNil(uncounted)
        XCTAssertNil(uncounted?.count)
        XCTAssertNil(shownRating(nil, rating: 4.0, ratingCount: 0), "rated by nobody")
        XCTAssertNil(shownRating(nil, rating: nil, ratingCount: 5))
        XCTAssertNil(shownRating(summary(0), rating: nil, ratingCount: nil))
    }

    func testAHistogramBarIsItsShareOfAllReviews() {
        let reviews = summary(128, [5: 96, 4: 32])
        XCTAssertEqual(histogramShare(reviews, 5), 0.75)
        XCTAssertEqual(histogramShare(reviews, 4), 0.25)
        XCTAssertEqual(histogramShare(reviews, 1), 0)
        XCTAssertEqual(histogramShare(summary(0), 5), 0, "no reviews, no division")
    }

    func testCountsAndAveragesReadAsWords() {
        XCTAssertEqual(starsLabel(1), "1 star")
        XCTAssertEqual(starsLabel(5), "5 stars")
        XCTAssertEqual(reviewCountLabel(1), "1 review")
        XCTAssertEqual(reviewCountLabel(128), "128 reviews")
        XCTAssertEqual(reviewCountLabel(0), "0 reviews")
        XCTAssertEqual(averageLabel(4.56), "4.6")
        XCTAssertEqual(averageLabel(5.0), "5.0")
    }

    // MARK: Loading

    @MainActor
    func testLoadMoreAddsTheNextPageUnderTheFirst() async {
        let pages = Pages()
        let reviews = ReviewsState(load: { try pages.load($0) }, send: { _ in })
        XCTAssertFalse(reviews.isLoaded)
        await reviews.loadFirst()
        XCTAssertTrue(reviews.isLoaded)
        XCTAssertEqual(reviews.summary?.count, 7)
        XCTAssertEqual(reviews.items.map { $0.id }, ["1", "2", "3", "4", "5"])
        XCTAssertTrue(reviews.hasMore)
        await reviews.loadFirst()
        XCTAssertEqual(pages.asked, [1], "the first page is loaded once")
        await reviews.loadMore()
        XCTAssertEqual(reviews.items.map { $0.id }, ["1", "2", "3", "4", "5", "6", "7"], "a review seen on both pages shows once")
        XCTAssertFalse(reviews.hasMore)
        XCTAssertFalse(reviews.isLoading)
    }

    @MainActor
    func testAFailedLoadIsQuietAndRetryAsksForTheSamePage() async {
        let pages = Pages()
        let reviews = ReviewsState(load: { try pages.load($0) }, send: { _ in })
        pages.failing = true
        await reviews.loadFirst()
        XCTAssertTrue(reviews.failed)
        XCTAssertFalse(reviews.isLoaded)
        XCTAssertFalse(reviews.isLoading)
        XCTAssertEqual(reviews.items, [])
        pages.failing = false
        await reviews.loadMore()
        XCTAssertFalse(reviews.failed)
        XCTAssertEqual(pages.asked, [1, 1])
        XCTAssertEqual(reviews.items.count, 5)

        pages.failing = true
        await reviews.loadMore()
        XCTAssertTrue(reviews.failed)
        XCTAssertEqual(reviews.items.count, 5, "what was loaded stays")
        XCTAssertTrue(reviews.hasMore)
        pages.failing = false
        await reviews.loadMore()
        XCTAssertEqual(pages.asked, [1, 1, 2, 2])
        XCTAssertEqual(reviews.items.count, 7)
    }

    @MainActor
    func testSubmitSendsTheForm() async throws {
        var sent: [ReviewForm] = []
        let reviews = ReviewsState(
            load: { ReviewPage(summary: nil, reviews: [], page: $0, hasNextPage: false) },
            send: { sent.append($0) }
        )
        try await reviews.submit(valid)
        XCTAssertEqual(sent, [valid])
    }
}
