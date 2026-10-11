import Foundation

/// A product's review totals. `histogram` is stars (1...5) to the number of reviews with that many.
struct ReviewSummary: Equatable, Sendable {
    let average: Double
    let count: Int
    let histogram: [Int: Int]
}

/// One review. `date` is ISO-8601; `pictures` are image URLs; `reply` is the store's answer.
struct Review: Equatable, Sendable {
    let id: String
    let rating: Int
    var title: String? = nil
    var body = ""
    var author = ""
    var verified = false
    var date: String? = nil
    var pictures: [String] = []
    var reply: String? = nil
}

/// Page `page` (from 1) of a product's reviews; `summary` is nil when the widget carries none.
struct ReviewPage: Equatable, Sendable {
    let summary: ReviewSummary?
    let reviews: [Review]
    let page: Int
    let hasNextPage: Bool
}

/// Judge.me reviews for a headless store, through its Widget API with the shop's **public** token (the private token
/// must never ship in an app). The app makes one only when JUDGEME_PUBLIC_TOKEN is set. Failures are `ArgonAPIError`s.
final class JudgeMe: Sendable {
    private let shopDomain: String
    private let token: String
    private let session: URLSession

    init(shopDomain: String, token: String, session: URLSession = .shared) {
        self.shopDomain = shopDomain
        self.token = token
        self.session = session
    }

    /// The digits that end a Shopify GID: `gid://shopify/Product/123` is Judge.me's external id `123`.
    static func numericId(_ gid: String) -> String {
        gid.split(separator: "?").first?.split(separator: "/").last.map { String($0) } ?? ""
    }

    /// A page of the reviews of product `productId` (its GID), in the order the store's widget shows them, with the
    /// product's totals.
    func reviews(productId: String, page: Int = 1, perPage: Int = 5) async throws -> ReviewPage {
        var url = URLComponents(string: "https://api.judge.me/api/v1/widgets/product_review")
        url?.queryItems = [
            URLQueryItem(name: "shop_domain", value: shopDomain),
            URLQueryItem(name: "external_id", value: Self.numericId(productId)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        guard let address = url?.url else { throw ArgonAPIError.network(URLError(.badURL)) }
        var request = URLRequest(url: address)
        // the token in a header, not in the URL, which logs and proxies keep
        request.setValue(token, forHTTPHeaderField: "X-Api-Token")
        let body = try await session.graphQL(request)
        // the answer is JSON whose `widget` is the reviews widget's HTML
        guard let answer = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let widget = answer["widget"] as? String else {
            throw ArgonAPIError.decoding(operation: "JudgeMe.reviews", detail: "widget missing")
        }
        return JudgeMeHtml.parse(widget, page: page, perPage: perPage)
    }

    /// Sends a review of product `productId` (its GID). Judge.me asks for no token here; the store publishes the review
    /// once it has approved it.
    func submit(productId: String, name: String, email: String, rating: Int, title: String, body: String) async throws {
        guard let address = URL(string: "https://api.judge.me/api/v1/reviews") else { throw ArgonAPIError.network(URLError(.badURL)) }
        let id = Self.numericId(productId)
        let review: [String: Any] = [
            "shop_domain": shopDomain,
            "platform": "shopify",
            "id": Int64(id).map { $0 as Any } ?? id,
            "name": name,
            "email": email,
            "rating": rating,
            "title": title,
            "body": body,
        ]
        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: review)
        _ = try await session.graphQL(request)
    }
}

// ponytail: this reads Judge.me's widget HTML by its class names with regular expressions (no HTML parser, no WebKit).
// Every field but a review's id and rating is optional, so a markup change on their side shows fewer fields, never a
// crash; an element is read up to the first closing tag of its own name, so one nested in itself would be cut short.
// The upgrade is a JSON reviews endpoint, if Judge.me opens one to public tokens.
enum JudgeMeHtml {
    /// The reviews, and the product's totals, in the widget's `html`. `page` and `perPage` are the ones asked for: with
    /// the total they say whether more follow.
    static func parse(_ html: String, page: Int, perPage: Int) -> ReviewPage {
        var summary: ReviewSummary? = nil
        if let average = attribute("data-average-rating", in: html).flatMap({ Double($0) }),
           let count = attribute("data-number-of-reviews", in: html).flatMap({ Int($0) }) {
            var histogram: [Int: Int] = [:]
            for row in tags("jdgm-histogram__row", in: html) {
                // the "clear filter" row has no rating
                guard let stars = attribute("data-rating", in: row.attributes).flatMap({ Int($0) }), (1...5).contains(stars),
                      let frequency = attribute("data-frequency", in: row.attributes).flatMap({ Int($0) }) else { continue }
                histogram[stars] = frequency
            }
            summary = ReviewSummary(average: average, count: count, histogram: histogram)
        }
        // a review is everything from its opening `class='jdgm-rev ...'` to the next one's
        let chunks = html.replacingOccurrences(of: "class=\"jdgm-rev ", with: "class='jdgm-rev ").components(separatedBy: "class='jdgm-rev ")
        let reviews = chunks.dropFirst().compactMap { review($0) }
        return ReviewPage(summary: summary, reviews: reviews, page: page, hasNextPage: (summary?.count ?? 0) > page * perPage)
    }

    /// `html` as plain text: `</p>` and `<br>` end a line, other tags go, entities are decoded.
    static func text(_ html: String) -> String {
        let lines = replace("</p\\s*>|<br\\s*/?>", in: html) { _ in "\n" }
        return decoded(replace("<[^>]*>", in: lines) { _ in "" }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func review(_ chunk: String) -> Review? {
        // the chunk starts inside the review's own opening tag
        let opening = String(chunk.prefix { $0 != ">" })
        guard let id = attribute("data-review-id", in: opening), !id.isEmpty,
              let rating = tags("jdgm-rev__rating", in: chunk).first.flatMap({ attribute("data-score", in: $0.attributes) }).flatMap({ Int($0) })
        else { return nil }
        func inner(_ name: String) -> String? {
            tags(name, in: chunk).first.map { text($0.inner) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let time = tags("jdgm-rev__timestamp", in: chunk).first?.attributes ?? ""
        return Review(
            id: id,
            rating: rating,
            title: inner("jdgm-rev__title"),
            body: inner("jdgm-rev__body") ?? "",
            author: inner("jdgm-rev__author") ?? "",
            verified: attribute("data-verified-buyer", in: opening) == "true",
            date: attribute("datetime", in: time) ?? attribute("data-content", in: time).flatMap { isoDate($0) },
            pictures: tags("jdgm-rev__pic-link", in: chunk).compactMap { attribute("href", in: $0.attributes) },
            reply: inner("jdgm-rev__reply-content")
        )
    }

    /// "2026-10-09 14:22:31 UTC" as "2026-10-09T14:22:31Z"; nil for any other shape.
    private static func isoDate(_ content: String) -> String? {
        guard content.range(of: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} UTC$", options: .regularExpression) != nil else { return nil }
        return content.dropLast(4).replacingOccurrences(of: " ", with: "T") + "Z"
    }

    /// The value of attribute `name` in `text` (a tag's attributes, or any HTML: the first one wins), entities decoded.
    private static func attribute(_ name: String, in text: String) -> String? {
        let pattern = "(?<![\\w-])" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*(['\"])(.*?)\\1"
        return matches(pattern, in: text).first.map { decoded($0[2]) }
    }

    /// Every element whose class list has `name`: its attributes, and what is inside it (empty for a tag never closed).
    private static func tags(_ name: String, in html: String) -> [(attributes: String, inner: String)] {
        let pattern = "<(\\w+)\\b([^>]*?\\bclass\\s*=\\s*(['\"])(?:[^'\"]*?\\s)?" + NSRegularExpression.escapedPattern(for: name)
            + "(?:\\s[^'\"]*?)?\\3[^>]*)>"
        let text = html as NSString
        return ranges(pattern, in: html).map { groups in
            let rest = text.substring(from: NSMaxRange(groups[0]))
            let close = rest.range(of: "</" + text.substring(with: groups[1]) + ">", options: .caseInsensitive)
            return (attributes: text.substring(with: groups[2]), inner: close.map { String(rest[..<$0.lowerBound]) } ?? "")
        }
    }

    private static let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "\u{2014}"]

    /// `text` with `&amp; &lt; &gt; &quot; &#39; &nbsp; &mdash;` and numeric entities decoded, each once; others stay.
    private static func decoded(_ text: String) -> String {
        replace("&(#[xX][0-9a-fA-F]+|#\\d+|\\w+);", in: text) { groups in
            let name = groups[1]
            if name.hasPrefix("#") {
                let hex = name.dropFirst().lowercased().hasPrefix("x")
                let code = hex ? UInt32(name.dropFirst(2), radix: 16) : UInt32(name.dropFirst())
                return code.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? groups[0]
            }
            return entities[name] ?? groups[0]
        }
    }

    /// The capture groups (0 is the whole match) of every match of `pattern` in `text`, as ranges.
    private static func ranges(_ pattern: String, in text: String) -> [[NSRange]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0) }
        }
    }

    /// The capture groups of every match of `pattern` in `text`, as text (empty for a group that took no part).
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        ranges(pattern, in: text).map { groups in
            groups.map { $0.location == NSNotFound ? "" : (text as NSString).substring(with: $0) }
        }
    }

    /// `text` with every match of `pattern` replaced by what `replacement` makes of its capture groups.
    private static func replace(_ pattern: String, in text: String, with replacement: ([String]) -> String) -> String {
        let result = NSMutableString(string: text)
        // back to front, so the ranges still to replace stay valid
        for groups in ranges(pattern, in: text).reversed() {
            let captured = groups.map { $0.location == NSNotFound ? "" : (text as NSString).substring(with: $0) }
            result.replaceCharacters(in: groups[0], with: replacement(captured))
        }
        return result as String
    }
}
