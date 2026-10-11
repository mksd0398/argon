import XCTest
@testable import ArgonStorefront

private struct Offline: Error {}

private func review(_ id: Int, stars: Int = 5) -> Review {
    Review(id: "\(id)", rating: stars, body: "Body \(id)", author: "Ada", verified: true)
}

/// Seven reviews, five a page; review 5 shows again on page 2 (a new review came in between the two calls).
private final class Pages {
    var asked: [Int] = []
    var failing = false

    func load(_ page: Int) throws -> ReviewPage {
        asked.append(page)
        if failing { throw Offline() }
        let ids = page == 1 ? 1...5 : 5...7
        let reviews = ids.map { review($0) }
        return ReviewPage(summary: ReviewSummary(average: 4.6, count: 7, histogram: [5: 7]), reviews: reviews, page: page, hasNextPage: page == 1)
    }
}

/// Without a token: three reviews, two a page, with their count and nothing else.
private func tokenless(_ page: Int) -> ReviewPage {
    ReviewPage(
        summary: ReviewSummary(average: nil, count: 3, histogram: [:]),
        reviews: page == 1 ? [review(1, stars: 5), review(2, stars: 4)] : [review(3, stars: 3)],
        page: page,
        hasNextPage: page == 1
    )
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
        // reviews read without a token, their average not known yet
        let counted = ReviewSummary(average: nil, count: 12, histogram: [:])
        XCTAssertNil(shownRating(counted, rating: nil, ratingCount: nil), "a count is no stars")
        let fallback = shownRating(counted, rating: 4.0, ratingCount: 10)
        XCTAssertEqual(fallback?.value, 4.0)
        XCTAssertEqual(fallback?.count, 10)
    }

    func testReviewsWithoutAnAverageTakeTheRatingMetafieldElseTheirOwnMeanOnceAllAreLoaded() {
        let two = [review(1, stars: 5), review(2, stars: 4)]
        XCTAssertEqual(reviewAverage(rating: 4.2, count: 12, loaded: two), 4.2, "the store's metafield, whatever is loaded")
        XCTAssertEqual(reviewAverage(rating: 4.2, count: 2, loaded: two), 4.2)
        XCTAssertEqual(reviewAverage(rating: nil, count: 2, loaded: two), 4.5, "both reviews are here: their mean")
        XCTAssertNil(reviewAverage(rating: nil, count: 12, loaded: two), "ten more are not loaded")
        XCTAssertNil(reviewAverage(rating: nil, count: 0, loaded: []))
        XCTAssertEqual(reviewAverage(rating: 0, count: 2, loaded: two), 4.5, "a rating of 0 is none")
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
    func testWithoutATokenTheBlockWaitsForAReviewAndTheAverageForAllOfThem() async {
        let reviews = ReviewsState(load: { tokenless($0) }, send: { _ in }, hidesEmpty: true)
        XCTAssertFalse(reviews.isShown, "nothing is known of the store's reviews yet")
        XCTAssertTrue(ReviewsState(load: { tokenless($0) }, send: { _ in }).isShown, "with a token the block is there from the start")
        await reviews.loadFirst()
        XCTAssertTrue(reviews.isShown)
        XCTAssertEqual(reviews.summary, ReviewSummary(average: nil, count: 3, histogram: [:]), "one review is not loaded: the count alone")
        await reviews.loadMore()
        XCTAssertEqual(reviews.summary, ReviewSummary(average: 4.0, count: 3, histogram: [:]), "all three: (5 + 4 + 3) / 3")

        let rated = ReviewsState(load: { tokenless($0) }, send: { _ in }, rating: 4.6, hidesEmpty: true)
        await rated.loadFirst()
        XCTAssertEqual(rated.summary?.average, 4.6, "the product's rating metafield, from the first page on")
    }

    @MainActor
    func testWithoutATokenAProductWithoutReviewsAndAFailedLoadShowNoBlock() async {
        let none = ReviewsState(
            load: { ReviewPage(summary: ReviewSummary(average: nil, count: 0, histogram: [:]), reviews: [], page: $0, hasNextPage: false) },
            send: { _ in },
            hidesEmpty: true
        )
        await none.loadFirst()
        XCTAssertTrue(none.isLoaded)
        XCTAssertFalse(none.isShown)

        let offline = ReviewsState(load: { _ in throw Offline() }, send: { _ in }, hidesEmpty: true)
        await offline.loadFirst()
        XCTAssertTrue(offline.failed)
        XCTAssertFalse(offline.isShown, "no retry line for reviews that may not exist")
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
