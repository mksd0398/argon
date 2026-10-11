import ArgonUI
import Observation
import os
import SwiftUI

// Block 11 of the product page: the product's Judge.me reviews (summary, list, "Load more") and the sheet to write one.

/// The stars beside the product's title: the reviews' own `summary` once it has loaded with reviews and an average, else
/// the product's rating metafields (`rating`, `ratingCount`). Nil for a product nobody has reviewed.
func shownRating(_ summary: ReviewSummary?, rating: Double?, ratingCount: Int?) -> (value: Double, count: Int?)? {
    if let summary = summary, let average = summary.average, summary.count > 0 { return (average, summary.count) }
    if let rating = rating, ratingCount != 0 { return (rating, ratingCount) }
    return nil
}

/// The average of reviews that come without one (Judge.me without a token): the product's `rating` metafield when the
/// store exposes it (0 is none), else the mean of the `loaded` reviews once they are all `count` of them, else nil: the
/// block then shows the count and the reviews, no stars.
func reviewAverage(rating: Double?, count: Int, loaded: [Review]) -> Double? {
    if let rating = rating, rating > 0 { return rating }
    if loaded.isEmpty || count > loaded.count { return nil }
    return Double(loaded.reduce(0) { $0 + $1.rating }) / Double(loaded.count)
}

/// "1 star", "4 stars".
func starsLabel(_ stars: Int) -> String {
    stars == 1 ? "1 star" : "\(stars) stars"
}

/// "1 review", "128 reviews".
func reviewCountLabel(_ count: Int) -> String {
    count == 1 ? "1 review" : "\(count) reviews"
}

/// "4.6": the average with one decimal.
func averageLabel(_ average: Double) -> String {
    String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), average)
}

/// How much of the bar for `stars` is filled: the share of all the reviews that gave them, 0 to 1.
func histogramShare(_ summary: ReviewSummary, _ stars: Int) -> Double {
    if summary.count <= 0 { return 0 }
    return min(max(Double(summary.histogram[stars] ?? 0) / Double(summary.count), 0), 1)
}

/// What the shopper has put in the write-a-review sheet; `rating` 0 is none chosen yet.
struct ReviewForm: Equatable {
    var rating = 0
    var title = ""
    var body = ""
    var name = ""
    var email = ""
}

/// What is wrong with a `ReviewForm`, by field (nil: nothing).
struct ReviewFormErrors: Equatable {
    var rating: String? = nil
    var body: String? = nil
    var name: String? = nil
    var email: String? = nil

    /// Nothing is wrong: the review can be sent.
    var isEmpty: Bool { self == ReviewFormErrors() }
}

// something@something.something, without spaces: enough to catch a slip, Judge.me checks the rest
private let emailPattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s.]+$"

/// A review needs a rating, a body, a name and a plausible email; the title is optional.
func validate(_ form: ReviewForm) -> ReviewFormErrors {
    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let email = form.email.trimmingCharacters(in: .whitespacesAndNewlines)
    return ReviewFormErrors(
        rating: (1...5).contains(form.rating) ? nil : "Choose a rating",
        body: blank(form.body) ? "Write your review" : nil,
        name: blank(form.name) ? "Enter your name" : nil,
        email: email.range(of: emailPattern, options: .regularExpression) == nil ? "Enter a valid email address" : nil
    )
}

let reviewSent = "Thanks. Your review appears once it's approved."
let reviewNotSent = "Your review couldn't be sent. Try again."

private let reviewsLog = Logger(subsystem: "app.storefront", category: "ProductReviews")

/// A product's reviews as far as they are loaded. `load` fetches a page (from 1), `send` a new review. Loading never
/// throws: a failure sets `failed` (the block shows "Reviews couldn't load" with Retry) and the next `loadMore` asks for
/// the same page again.
@MainActor
@Observable
final class ReviewsState {
    private(set) var summary: ReviewSummary? = nil
    private(set) var items: [Review] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var failed = false
    /// The first page has arrived (there may be no reviews at all).
    private(set) var isLoaded = false

    @ObservationIgnored private var page = 0
    private let load: (_ page: Int) async throws -> ReviewPage
    private let send: (ReviewForm) async throws -> Void
    /// The demo store's bundled sample reviews: the block says so, and nothing a shopper writes is sent.
    let isSample: Bool
    /// The product's `rating` metafield: the average of reviews that come without one (`reviewAverage`).
    private let rating: Double?
    /// Without a Judge.me token nobody has said the store has reviews: the block then waits for a first one (`isShown`).
    private let hidesEmpty: Bool

    /// Whether the page has the block at all: always, but without a token only once there is a review to show.
    var isShown: Bool { !hidesEmpty || !items.isEmpty }

    init(
        load: @escaping (_ page: Int) async throws -> ReviewPage,
        send: @escaping (ReviewForm) async throws -> Void,
        isSample: Bool = false,
        rating: Double? = nil,
        hidesEmpty: Bool = false
    ) {
        self.load = load
        self.send = send
        self.isSample = isSample
        self.rating = rating
        self.hidesEmpty = hidesEmpty
    }

    convenience init(judgeMe: JudgeMe, product: Product) {
        let productId = product.id
        self.init(
            load: { page in try await judgeMe.reviews(productId: productId, page: page) },
            send: { form in
                func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
                try await judgeMe.submit(
                    productId: productId,
                    name: trimmed(form.name),
                    email: trimmed(form.email),
                    rating: form.rating,
                    title: trimmed(form.title),
                    body: trimmed(form.body)
                )
            },
            isSample: judgeMe.isSample,
            rating: product.rating,
            hidesEmpty: judgeMe.isTokenless
        )
    }

    /// The first page, once.
    func loadFirst() async {
        if !isLoaded { await loadMore() }
    }

    /// The next page, added under the ones already here ("Load more", and "Retry" after a failure).
    func loadMore() async {
        if isLoading { return }
        isLoading = true
        failed = false
        do {
            let next = try await load(page + 1)
            page += 1
            // a review that slid onto the next page while a new one came in is not shown twice
            var seen = Set(items.map { $0.id })
            items += next.reviews.filter { seen.insert($0.id).inserted }
            if let summary = next.summary {
                let average = summary.average ?? reviewAverage(rating: rating, count: summary.count, loaded: items)
                self.summary = ReviewSummary(average: average, count: summary.count, histogram: summary.histogram)
            }
            hasMore = next.hasNextPage
            isLoaded = true
        } catch {
            // leaving the page cancels the load: no failure to show, it runs again when the page is back
            if !Task.isCancelled {
                reviewsLog.warning("reviews not loaded: \(error.localizedDescription)")
                failed = true
            }
        }
        isLoading = false
    }

    /// Sends `form` (already valid) to the store; throws when it can't be sent.
    func submit(_ form: ReviewForm) async throws {
        try await send(form)
    }
}

// MARK: - Views

/// The reviews block: the summary (average, stars, count, a bar per star, as far as the reviews carry them), "Write a
/// review" (`onWrite`), the reviews loaded so far, then "Load more" (`onLoadMore`) while there are more. A load that
/// failed shows a quiet line with Retry (also `onLoadMore`); it never takes the page down.
/// ponytail: the loaded reviews are all built at once (five a page, a few pages at most in practice). Upgrade: a lazy
/// stack, for stores whose shoppers page through hundreds.
@MainActor
struct ProductReviews: View {
    let reviews: ReviewsState
    let onWrite: () -> Void
    let onLoadMore: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.l) {
            SectionHeader(title: "Reviews")
            if reviews.isSample { LabelTag(text: "Sample reviews: nothing is sent") }
            if let summary = reviews.summary, summary.count > 0 {
                SummaryView(summary: summary)
            } else if reviews.isLoaded {
                Text("No reviews yet").font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
            ArgonButton(title: "Write a review", style: .secondary, fullWidth: true, action: onWrite)
            ForEach(reviews.items, id: \.id) { review in
                ArgonDivider()
                ReviewView(review: review)
            }
            if reviews.failed {
                HStack {
                    Text("Reviews couldn't load")
                        .font(theme.type.label)
                        .foregroundStyle(theme.colors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ArgonButton(title: "Retry", style: .tertiary, size: .s, action: onLoadMore)
                }
            } else if reviews.isLoading {
                ArgonSpinner(size: .s).frame(maxWidth: .infinity)
            } else if reviews.hasMore {
                ArgonButton(title: "Load more", style: .tertiary, fullWidth: true, action: onLoadMore)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.xl)
    }
}

/// The average with its stars and "128 reviews", beside one bar per star from 5 down to 1. Reviews read without a token
/// have no bars, and until their average is known (`reviewAverage`) only "128 reviews".
@MainActor
private struct SummaryView: View {
    let summary: ReviewSummary
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xl) {
            VStack(spacing: theme.spacing.xs) {
                if let average = summary.average {
                    Text(averageLabel(average)).font(theme.type.display).foregroundStyle(theme.colors.ink)
                    ArgonRating(value: average, size: .m)
                }
                Text(reviewCountLabel(summary.count)).font(theme.type.caption).foregroundStyle(theme.colors.muted)
            }
            if !summary.histogram.isEmpty {
                VStack(spacing: theme.spacing.s) {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { stars in
                        let count = summary.histogram[stars] ?? 0
                        // read as one line: "5 stars, 96 reviews"
                        let line = "\(starsLabel(stars)), \(reviewCountLabel(count))"
                        HStack(spacing: theme.spacing.s) {
                            Text(verbatim: "\(stars)").frame(minWidth: 12)
                            ArgonProgressBar(value: histogramShare(summary, stars))
                            Text(verbatim: "\(count)").frame(minWidth: 28, alignment: .trailing)
                        }
                        .font(theme.type.caption)
                        .foregroundStyle(theme.colors.muted)
                        .accessibilityElement()
                        .accessibilityLabel(line)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One review: its stars and "Verified", title, body, the shopper's photos, who wrote it and when, and the store's reply.
@MainActor
private struct ReviewView: View {
    let review: Review
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                ArgonRating(value: Double(review.rating))
                if review.verified { LabelTag(text: "Verified") }
            }
            if let title = review.title {
                Text(title).font(theme.type.headline).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
            }
            if !review.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(review.body).font(theme.type.body).foregroundStyle(theme.colors.ink)
            }
            if !review.pictures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.s) {
                        ForEach(review.pictures.indices, id: \.self) { index in
                            StoreImage(url: review.pictures[index], alt: "Review photo")
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.s))
                        }
                    }
                }
            }
            if !byline.isEmpty { Text(byline).font(theme.type.caption).foregroundStyle(theme.colors.muted) }
            if let reply = review.reply {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("Reply from the store").font(theme.type.caption).foregroundStyle(theme.colors.muted)
                    Text(reply).font(theme.type.body).foregroundStyle(theme.colors.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.m)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.m))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Ada · Oct 9, 2026": who wrote it and when, as far as the review says.
    private var byline: String {
        let author = review.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : review.author
        return [author, review.date.map { displayDate($0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The write-a-review sheet (the content of `argonBottomSheet`): a star picker, title, review, name and email, then
/// "Submit review". What is missing shows under its field from the first try to send (`validate`). Sent: `onDismiss`
/// closes the sheet and the app says `reviewSent`; not sent: `reviewNotSent` shows above the button and the form stays
/// as it is. `form` is the caller's, so a review half written is still there when the sheet opens again. `submit` sends
/// a valid form.
@MainActor
struct ReviewSheet: View {
    @Binding var form: ReviewForm
    let onDismiss: () -> Void
    let submit: (ReviewForm) async throws -> Void
    @State private var tried = false
    @State private var sending = false
    @State private var notSent = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let errors = tried ? validate(form) : ReviewFormErrors()
        // scrolling, and above the keyboard: every field can be reached while typing
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                Text("Write a review")
                    .font(theme.type.title)
                    .foregroundStyle(theme.colors.ink)
                    .accessibilityAddTraits(.isHeader)
                StarPicker(rating: form.rating) { form.rating = $0 }
                if let error = errors.rating {
                    Text(error).font(theme.type.caption).foregroundStyle(theme.colors.sale)
                }
                ArgonInput(label: "Title", text: $form.title)
                ArgonTextArea(label: "Review", text: $form.body, error: errors.body)
                ArgonInput(label: "Name", text: $form.name, error: errors.name)
                ArgonInput(label: "Email", text: $form.email, error: errors.email, keyboard: .email)
                if notSent {
                    Text(reviewNotSent).font(theme.type.label).foregroundStyle(theme.colors.sale)
                }
                ArgonButton(title: "Submit review", isLoading: sending, fullWidth: true) { send() }
            }
            .padding(.horizontal, theme.spacing.l)
            // clear of the sheet's drag indicator
            .padding(.vertical, theme.spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.paper)
    }

    private func send() {
        tried = true
        guard validate(form).isEmpty else { return }
        sending = true
        notSent = false
        Task {
            do {
                try await submit(form)
                form = ReviewForm()
                tried = false
                onDismiss()
                AppGraph.toast.show(reviewSent)
            } catch {
                notSent = true
            }
            sending = false
        }
    }
}

/// Five stars to tap: the ones up to `rating` are filled.
@MainActor
private struct StarPicker: View {
    let rating: Int
    let onRate: (Int) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { stars in
                Button { onRate(stars) } label: {
                    ArgonIcon(name: stars <= rating ? .starFilled : .star, size: 32, tint: theme.colors.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(starsLabel(stars))
                .accessibilityAddTraits(stars == rating ? .isSelected : [])
            }
        }
    }
}
