import Foundation

// Money amounts stay Shopify's decimal strings; formatting is the UI's job.
struct Money: Equatable {
    let amount: String
    let currencyCode: String
}

struct Img: Equatable {
    let url: String
    let alt: String?
    let width: Int?
    let height: Int?
}

struct ProductCard: Equatable {
    let id: String
    let handle: String
    let title: String
    let available: Bool
    let image: Img?
    let price: Money
    let compareAt: Money?
}

struct CollectionCard: Equatable {
    let id: String
    let handle: String
    let title: String
    let image: Img?
}

struct Variant: Equatable {
    let id: String
    let title: String
    let available: Bool
    let options: [String: String]
    let price: Money
    let compareAt: Money?
    let image: Img?
}

struct Product {
    let id: String
    let handle: String
    let title: String
    let vendor: String
    let descriptionHtml: String
    let images: [Img]
    let options: [(name: String, values: [String])]
    let variants: [Variant]
    let metafields: [(namespace: String, key: String, value: String)]
}

struct FilterValue: Equatable {
    let id: String
    let label: String
    let count: Int
    let input: String
}

struct Filter: Equatable {
    let id: String
    let label: String
    let type: String
    let values: [FilterValue]
}

struct ProductPage: Equatable {
    let items: [ProductCard]
    let filters: [Filter]
    let endCursor: String?
    let hasNext: Bool
}

struct CartLine: Equatable {
    let id: String
    let quantity: Int
    let variantId: String
    let variantTitle: String
    let productHandle: String
    let productTitle: String
    let image: Img?
    let price: Money
    let total: Money
}

struct Cart: Equatable {
    let id: String
    let checkoutUrl: String
    let totalQuantity: Int
    let subtotal: Money
    let total: Money
    let lines: [CartLine]
}

// Customer Account API. Dates are ISO-8601 strings and statuses Shopify's enum values; the UI formats both.
struct OrderSummary: Equatable {
    let id: String
    let name: String
    let processedAt: String
    let financialStatus: String?
    let total: Money
}

struct Customer: Equatable {
    let name: String
    let email: String?
    let orders: [OrderSummary]
}

struct OrderLine: Equatable {
    let title: String
    let variantTitle: String?
    let quantity: Int
    let image: Img?
    let total: Money?
}

struct Order: Equatable {
    let name: String
    let processedAt: String
    let financialStatus: String?
    let fulfillments: [String] // one status per fulfillment; empty: nothing fulfilled yet
    let lines: [OrderLine]
    let subtotal: Money?
    let total: Money
}

struct MenuItem: Equatable {
    let title: String
    let route: Route
    let children: [MenuItem]
}

/// `hosts` is ordered: SHOP_DOMAIN first (relative links open against it), then the primary domain.
struct Brand: Equatable {
    let name: String
    let logo: Img?
    let cover: Img?
    let accent: String?
    let hosts: [String]
}

// Inside this module `Section` is this type; SwiftUI's container is `SwiftUI.Section`.
enum Section: Equatable {
    case banner(style: String, image: Img?, heading: String?, text: String?, buttonLabel: String?, link: Route?)
    case products(heading: String?, style: String, items: [ProductCard])
    case collections(heading: String?, items: [CollectionCard])
}

enum Route: Hashable {
    case product(String)
    case collection(String)
    case search(String)
    case web(String)
}
